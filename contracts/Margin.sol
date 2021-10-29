// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IMargin.sol";
import "./libraries/Math.sol";
import "./libraries/SignedDecimal.sol";
import "./utils/Reentrant.sol";

contract Margin is IMargin, Reentrant {
    using SignedDecimal for int256;

    struct Position {
        int256 quoteSize;
        int256 baseSize;
        uint256 tradeSize;
    }

    uint256 constant MAXRATIO = 10000;

    address public override factory;
    address public override amm;
    address public override baseToken;
    address public override quoteToken;
    address public override vault;
    address public override config;
    mapping(address => Position) public traderPositionMap;

    constructor() {
        factory = msg.sender;
    }

    function initialize(
        address _baseToken,
        address _quoteToken,
        address _config,
        address _amm,
        address _vault
    ) external override {
        require(factory == msg.sender, "factory");
        amm = _amm;
        vault = _vault;
        config = _config;
        baseToken = _baseToken;
        quoteToken = _quoteToken;
    }

    function addMargin(address _trader, uint256 _depositAmount) external override nonReentrant {
        require(_depositAmount > 0, ">0");
        Position memory traderPosition = traderPositionMap[_trader];

        uint256 balance = IERC20(baseToken).balanceOf(address(this));
        require(_depositAmount <= balance, "wrong deposit amount");

        traderPosition.baseSize = traderPosition.baseSize.addU(_depositAmount);
        IERC20(baseToken).transfer(address(vault), _depositAmount);

        _setPosition(_trader, traderPosition);
        emit AddMargin(_trader, _depositAmount);
    }

    function removeMargin(uint256 _withdrawAmount) external override nonReentrant {
        require(_withdrawAmount > 0, ">0");
        //fixme
        // address trader = msg.sender;
        address trader = tx.origin;

        Position memory traderPosition = traderPositionMap[trader];
        // check before subtract
        require(_withdrawAmount <= getWithdrawable(trader), "preCheck withdrawable");

        traderPosition.baseSize = traderPosition.baseSize.subU(_withdrawAmount);
        if (traderPosition.quoteSize != 0) {
            // important! check position health, maybe no need because have checked getWithdrawable
            _checkInitMarginRatio(traderPosition);
        }
        _setPosition(trader, traderPosition);

        IVault(vault).withdraw(trader, _withdrawAmount);

        emit RemoveMargin(trader, _withdrawAmount);
    }

    function openPosition(uint8 _side, uint256 _quoteAmount)
        external
        override
        nonReentrant
        returns (uint256 baseAmount)
    {
        require(_side == 0 || _side == 1, "Margin: INVALID_SIDE");
        require(_quoteAmount > 0, ">0");
        //fixme
        // address trader = msg.sender;
        address trader = tx.origin;

        Position memory traderPosition = traderPositionMap[trader];
        bool isLong = _side == 0;
        bool sameDir = traderPosition.quoteSize == 0 ||
            (traderPosition.quoteSize < 0 == isLong) ||
            (traderPosition.quoteSize > 0 == !isLong);

        //swap exact quote to base
        baseAmount = _addPositionWithVAmm(isLong, _quoteAmount);
        require(baseAmount > 0, "tiny quoteAmount");

        //old: quote -10, base 11; add long 5X position 1: quote -5, base +5; new: quote -15, base 16
        //old: quote 10, base -9; add long 5X position: quote -5, base +5; new: quote 5, base -4
        //old: quote 10, base -9; add long 15X position: quote -15, base +15; new: quote -5, base 6
        if (isLong) {
            traderPosition.quoteSize = traderPosition.quoteSize.subU(_quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount);
        } else {
            traderPosition.quoteSize = traderPosition.quoteSize.addU(_quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount);
        }

        if (traderPosition.quoteSize == 0) {
            traderPosition.tradeSize = 0;
        } else if (sameDir) {
            traderPosition.tradeSize = traderPosition.tradeSize + baseAmount;
        } else {
            traderPosition.tradeSize = traderPosition.tradeSize > baseAmount
                ? traderPosition.tradeSize - baseAmount
                : baseAmount - traderPosition.tradeSize;
        }

        _checkInitMarginRatio(traderPosition);
        _setPosition(trader, traderPosition);
        emit OpenPosition(trader, _side, baseAmount, _quoteAmount);
    }

    function closePosition(uint256 _quoteAmount) external override nonReentrant returns (uint256 baseAmount) {
        //fixme
        // address trader = msg.sender;
        address trader = tx.origin;

        Position memory traderPosition = traderPositionMap[trader];
        require(traderPosition.quoteSize != 0 && _quoteAmount != 0, "position cant 0");
        require(_quoteAmount <= traderPosition.quoteSize.abs(), "above position");
        //swap exact quote to base
        bool isLong = traderPosition.quoteSize < 0;
        uint256 debtRatio = calDebtRatio(traderPosition.quoteSize, traderPosition.baseSize);
        // todo test carefully
        //liquidatable
        if (debtRatio >= IConfig(config).liquidateThreshold()) {
            uint256 quoteSize = traderPosition.quoteSize.abs();
            baseAmount = querySwapBaseWithVAmm(isLong, quoteSize);
            if (isLong) {
                int256 remainBaseAmount = traderPosition.baseSize.subU(baseAmount);
                if (remainBaseAmount >= 0) {
                    _minusPositionWithVAmm(isLong, quoteSize);
                    traderPosition.quoteSize = 0;
                    traderPosition.baseSize = remainBaseAmount;
                } else {
                    IAmm(amm).forceSwap(
                        address(baseToken),
                        address(quoteToken),
                        traderPosition.baseSize.abs(),
                        traderPosition.quoteSize.abs()
                    );
                    traderPosition.quoteSize = 0;
                    traderPosition.baseSize = 0;
                    traderPosition.tradeSize = 0;
                }
            } else {
                int256 remainBaseAmount = traderPosition.baseSize.addU(baseAmount);
                if (remainBaseAmount >= 0) {
                    _minusPositionWithVAmm(isLong, quoteSize);
                    traderPosition.quoteSize = 0;
                    traderPosition.baseSize = remainBaseAmount;
                } else {
                    IAmm(amm).forceSwap(
                        address(quoteToken),
                        address(baseToken),
                        traderPosition.quoteSize.abs(),
                        traderPosition.baseSize.abs()
                    );
                    traderPosition.quoteSize = 0;
                    traderPosition.baseSize = 0;
                    traderPosition.tradeSize = 0;
                }
            }
        } else {
            baseAmount = _minusPositionWithVAmm(isLong, _quoteAmount);
            //old: quote -10, base 11; close position: quote 5, base -5; new: quote -5, base 6
            //old: quote 10, base -9; close position: quote -5, base +5; new: quote 5, base -4
            if (isLong) {
                traderPosition.quoteSize = traderPosition.quoteSize.addU(_quoteAmount);
                traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount);
            } else {
                traderPosition.quoteSize = traderPosition.quoteSize.subU(_quoteAmount);
                traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount);
            }

            if (traderPosition.quoteSize != 0) {
                require(traderPosition.tradeSize >= baseAmount, "not closable");
                traderPosition.tradeSize = traderPosition.tradeSize - baseAmount;
                _checkInitMarginRatio(traderPosition);
            } else {
                traderPosition.tradeSize = 0;
            }
        }

        _setPosition(trader, traderPosition);
        emit ClosePosition(trader, _quoteAmount, baseAmount);
    }

    function liquidate(address _trader)
        external
        override
        nonReentrant
        returns (
            uint256 quoteAmount,
            uint256 baseAmount,
            uint256 bonus
        )
    {
        Position memory traderPosition = traderPositionMap[_trader];
        int256 quoteSize = traderPosition.quoteSize;
        require(traderPosition.quoteSize != 0, "position 0");
        require(canLiquidate(_trader), "not liquidatable");

        bool isLong = traderPosition.quoteSize < 0;

        //query swap exact quote to base
        quoteAmount = traderPosition.quoteSize.abs();
        baseAmount = querySwapBaseWithVAmm(isLong, quoteAmount);

        //calc liquidate fee
        uint256 liquidateFeeRatio = IConfig(config).liquidateFeeRatio();
        bonus = (baseAmount * liquidateFeeRatio) / MAXRATIO;
        //update directly
        if (isLong) {
            int256 remainBaseAmount = traderPosition.baseSize.subU(baseAmount - bonus);
            IAmm(amm).forceSwap(
                address(baseToken),
                address(quoteToken),
                remainBaseAmount.abs(),
                traderPosition.quoteSize.abs()
            );
        } else {
            int256 remainBaseAmount = traderPosition.baseSize.addU(baseAmount - bonus);
            IAmm(amm).forceSwap(
                address(quoteToken),
                address(baseToken),
                traderPosition.quoteSize.abs(),
                remainBaseAmount.abs()
            );
        }
        IVault(vault).withdraw(msg.sender, bonus);
        traderPosition.baseSize = 0;
        traderPosition.quoteSize = 0;
        traderPosition.tradeSize = 0;
        _setPosition(_trader, traderPosition);
        emit Liquidate(msg.sender, _trader, quoteSize.abs(), baseAmount, bonus);
    }

    function canLiquidate(address _trader) public view override returns (bool) {
        Position memory traderPosition = traderPositionMap[_trader];
        uint256 debtRatio = calDebtRatio(traderPosition.quoteSize, traderPosition.baseSize);
        return debtRatio >= IConfig(config).liquidateThreshold();
    }

    function queryMaxOpenPosition(uint8 _side, uint256 _margin) external view override returns (uint256 quoteAmount) {
        require(_side == 0 || _side == 1, "Margin: INVALID_SIDE");
        bool isLong = _side == 0;
        uint256 maxBase;
        if (isLong) {
            maxBase = _margin * (MAXRATIO / IConfig(config).initMarginRatio() - 1);
        } else {
            maxBase = (_margin * MAXRATIO) / IConfig(config).initMarginRatio();
        }

        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            maxBase,
            address(baseToken)
        );

        uint256[2] memory result = IAmm(amm).swapQuery(inputToken, outputToken, inputAmount, outputAmount);
        quoteAmount = isLong ? result[0] : result[1];
    }

    function getMarginRatio(address _trader) external view returns (uint256) {
        Position memory position = traderPositionMap[_trader];
        return _calMarginRatio(position.quoteSize, position.baseSize);
    }

    function querySwapBaseWithVAmm(bool isLong, uint256 _quoteAmount) public view returns (uint256) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            _quoteAmount,
            address(quoteToken)
        );

        uint256[2] memory result = IAmm(amm).swapQuery(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[0] : result[1];
    }

    function calDebtRatio(int256 quoteSize, int256 baseSize) public view returns (uint256 debtRatio) {
        if (quoteSize == 0 || (quoteSize > 0 && baseSize >= 0)) {
            debtRatio = 0;
        } else if (quoteSize < 0 && baseSize <= 0) {
            debtRatio = MAXRATIO;
        } else if (quoteSize > 0) {
            //calculate asset
            uint256[2] memory result = IAmm(amm).swapQueryWithAcctSpecMarkPrice(
                address(quoteToken),
                address(baseToken),
                quoteSize.abs(),
                0
            );
            uint256 baseAmount = result[1];
            debtRatio = baseAmount == 0 ? MAXRATIO : baseSize.mul(-1).mulU(MAXRATIO).divU(baseAmount).abs();
        } else {
            //calculate debt
            uint256[2] memory result = IAmm(amm).swapQueryWithAcctSpecMarkPrice(
                address(baseToken),
                address(quoteToken),
                0,
                quoteSize.abs()
            );
            uint256 baseAmount = result[0];
            uint256 ratio = (baseAmount * MAXRATIO) / baseSize.abs();
            debtRatio = MAXRATIO < ratio ? MAXRATIO : ratio;
        }
    }

    function getPosition(address _trader)
        external
        view
        override
        returns (
            int256,
            int256,
            uint256
        )
    {
        Position memory position = traderPositionMap[_trader];
        return (position.baseSize, position.quoteSize, position.tradeSize);
    }

    function getWithdrawable(address _trader) public view override returns (uint256 withdrawableMargin) {
        Position memory traderPosition = traderPositionMap[_trader];
        if (traderPosition.quoteSize == 0) {
            withdrawableMargin = traderPosition.baseSize <= 0 ? 0 : traderPosition.baseSize.abs();
        } else if (traderPosition.quoteSize < 0) {
            uint256[2] memory result = IAmm(amm).swapQuery(
                address(baseToken),
                address(quoteToken),
                0,
                traderPosition.quoteSize.abs()
            );

            uint256 baseAmount = result[0];
            uint256 a = baseAmount * MAXRATIO;
            uint256 b = (MAXRATIO - IConfig(config).initMarginRatio());
            uint256 baseNeeded = a / b;
            if (a % b != 0) {
                baseNeeded += 1;
            }

            withdrawableMargin = traderPosition.baseSize.abs() < baseNeeded
                ? 0
                : traderPosition.baseSize.abs() - baseNeeded;
        } else {
            uint256[2] memory result = IAmm(amm).swapQuery(
                address(quoteToken),
                address(baseToken),
                traderPosition.quoteSize.abs(),
                0
            );

            uint256 baseAmount = result[1];
            uint256 baseNeeded = (baseAmount * (MAXRATIO - IConfig(config).initMarginRatio())) / (MAXRATIO);
            withdrawableMargin = traderPosition.baseSize < int256(-1).mulU(baseNeeded)
                ? 0
                : traderPosition.baseSize.sub(int256(-1).mulU(baseNeeded)).abs();
        }
    }

    function _setPosition(address _trader, Position memory _position) internal {
        traderPositionMap[_trader] = _position;
    }

    function _addPositionWithVAmm(bool isLong, uint256 _quoteAmount) internal returns (uint256) {
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 outputAmount;
        if (isLong) {
            inputToken = quoteToken;
            inputAmount = _quoteAmount;
        } else {
            outputToken = quoteToken;
            outputAmount = _quoteAmount;
        }

        uint256[2] memory result = IAmm(amm).swap(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[1] : result[0];
    }

    function _minusPositionWithVAmm(bool isLong, uint256 _quoteAmount) internal returns (uint256) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            _quoteAmount,
            address(quoteToken)
        );

        uint256[2] memory result = IAmm(amm).swap(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[0] : result[1];
    }

    function _getSwapParam(
        bool isLong,
        uint256 _Amount,
        address _Token
    )
        internal
        pure
        returns (
            address inputToken,
            address outputToken,
            uint256 inputAmount,
            uint256 outputAmount
        )
    {
        if (isLong) {
            outputToken = _Token;
            outputAmount = _Amount;
        } else {
            inputToken = _Token;
            inputAmount = _Amount;
        }
    }

    function _checkInitMarginRatio(Position memory traderPosition) internal view {
        require(
            _calMarginRatio(traderPosition.quoteSize, traderPosition.baseSize) >= IConfig(config).initMarginRatio(),
            "initMarginRatio"
        );
    }

    function _calMarginRatio(int256 quoteSize, int256 baseSize) internal view returns (uint256 marginRatio) {
        if (quoteSize == 0 || (quoteSize > 0 && baseSize >= 0)) {
            marginRatio = MAXRATIO;
        } else if (quoteSize < 0 && baseSize <= 0) {
            marginRatio = 0;
        } else if (quoteSize > 0) {
            //calculate asset
            uint256[2] memory result = IAmm(amm).swapQuery(address(quoteToken), address(baseToken), quoteSize.abs(), 0);
            uint256 baseAmount = result[1];
            marginRatio = (baseSize.abs() >= baseAmount || baseAmount == 0)
                ? 0
                : baseSize.mulU(MAXRATIO).divU(baseAmount).addU(MAXRATIO).abs();
        } else {
            //calculate debt
            uint256[2] memory result = IAmm(amm).swapQuery(address(baseToken), address(quoteToken), 0, quoteSize.abs());
            uint256 baseAmount = result[0];
            uint256 ratio = (baseAmount * (MAXRATIO)) / (baseSize.abs());
            marginRatio = MAXRATIO < ratio ? 0 : MAXRATIO - ratio;
        }
    }
}

// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IMargin.sol";
import "./libraries/Math.sol";
import "./libraries/Decimal.sol";
import "./libraries/SignedDecimal.sol";
import "./utils/Reentrant.sol";

import "hardhat/console.sol";

contract Margin is IMargin {
    bool private entered = false;
    using Decimal for uint256;
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
    ) external override onlyFactory {
        //todo check if has initialized and address != 0
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
        if (traderPosition.quoteSize == 0) {
            require(traderPosition.baseSize >= 0, "insufficient withdrawable");
        } else {
            // important! check position health
            _checkInitMarginRatio(traderPosition);
        }
        _setPosition(trader, traderPosition);

        IVault(vault).withdraw(trader, _withdrawAmount);

        emit RemoveMargin(trader, _withdrawAmount);
    }

    function openPosition(uint8 _side, uint256 _baseAmount) external override nonReentrant returns (uint256) {
        require(_baseAmount > 0, ">0");
        //fixme
        // address trader = msg.sender;
        address trader = tx.origin;

        Position memory traderPosition = traderPositionMap[trader];
        bool isLong = _side == 0;
        bool sameDir = traderPosition.quoteSize == 0 ||
            (traderPosition.quoteSize < 0 == isLong) ||
            (traderPosition.quoteSize > 0 == !isLong);

        //swap exact base to quote
        uint256 quoteAmount = _addPositionWithVAmm(isLong, _baseAmount);

        //old: quote -10, base 11; add long 5X position 1: quote -5, base +5; new: quote -15, base 16
        //old: quote 10, base -9; add long 5X position: quote -5, base +5; new: quote 5, base -4
        //old: quote 10, base -9; add long 15X position: quote -15, base +15; new: quote -5, base 6
        if (isLong) {
            traderPosition.quoteSize = traderPosition.quoteSize.subU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.addU(_baseAmount);
        } else {
            traderPosition.quoteSize = traderPosition.quoteSize.addU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.subU(_baseAmount);
        }

        if (sameDir) {
            traderPosition.tradeSize = traderPosition.tradeSize.add(_baseAmount);
        } else {
            traderPosition.tradeSize = traderPosition.tradeSize > _baseAmount
                ? traderPosition.tradeSize.sub(_baseAmount)
                : _baseAmount.sub(traderPosition.tradeSize);
        }

        _checkInitMarginRatio(traderPosition);
        _setPosition(trader, traderPosition);
        emit OpenPosition(trader, _side, _baseAmount, quoteAmount);

        return quoteAmount;
    }

    function closePosition(uint256 _quoteAmount) external override nonReentrant returns (uint256) {
        //fixme
        // address trader = msg.sender;
        address trader = tx.origin;

        Position memory traderPosition = traderPositionMap[trader];
        require(traderPosition.quoteSize != 0 && _quoteAmount != 0, "position cant 0");
        require(_quoteAmount <= traderPosition.quoteSize.abs(), "above position");
        //swap exact quote to base
        bool isLong = traderPosition.quoteSize < 0;
        uint256 baseAmount = _minusPositionWithVAmm(isLong, _quoteAmount);

        //old: quote -10, base 11; close position: quote 5, base -5; new: quote -5, base 6
        //old: quote 10, base -9; close position: quote -5, base +5; new: quote 5, base -4
        if (isLong) {
            traderPosition.quoteSize = traderPosition.quoteSize.addU(_quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount);
        } else {
            traderPosition.quoteSize = traderPosition.quoteSize.subU(_quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount);
        }
        traderPosition.tradeSize = traderPosition.tradeSize.sub(baseAmount);

        _checkInitMarginRatio(traderPosition);
        _setPosition(trader, traderPosition);
        emit ClosePosition(trader, _quoteAmount, baseAmount);
        return baseAmount;
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
        bonus = baseAmount.mul(liquidateFeeRatio).div(MAXRATIO);
        int256 remainBaseAmount = traderPosition.baseSize.subU(baseAmount.sub(bonus));
        if (remainBaseAmount > 0) {
            _minusPositionWithVAmm(isLong, traderPosition.quoteSize.abs());
            IVault(vault).withdraw(_trader, remainBaseAmount.abs());
        } else {
            //with bad debt, update directly
            if (isLong) {
                IAmm(amm).forceSwap(
                    address(baseToken),
                    address(quoteToken),
                    remainBaseAmount.abs(),
                    traderPosition.quoteSize.abs()
                );
            } else {
                IAmm(amm).forceSwap(
                    address(quoteToken),
                    address(baseToken),
                    traderPosition.quoteSize.abs(),
                    remainBaseAmount.abs()
                );
            }
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

    function queryMaxOpenPosition(uint8 _side, uint256 _baseAmount) external override view returns (uint256) {
        bool isLong = _side == 0;
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            _baseAmount,
            address(baseToken)
        );

        uint256[2] memory result = IAmm(amm).swapQueryWithAcctSpecMarkPrice(
            inputToken,
            outputToken,
            inputAmount,
            outputAmount
        );
        return isLong ? result[0] : result[1];
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

    function calDebtRatio(int256 quoteSize, int256 baseSize) public view returns (uint256) {
        if (quoteSize == 0 || (quoteSize > 0 && baseSize >= 0)) {
            return 0;
        } else if (quoteSize < 0 && baseSize <= 0) {
            return MAXRATIO;
        } else if (quoteSize > 0) {
            //calculate asset
            uint256[2] memory result = IAmm(amm).swapQueryWithAcctSpecMarkPrice(
                address(quoteToken),
                address(baseToken),
                quoteSize.abs(),
                0
            );
            //todo need to delete 10, this 10 is for simulating price fluctuation, bad for long
            uint256 baseAmount = result[1] * 10;
            //fixme max debt ratio is MAXRATIO, ok?
            if (baseAmount == 0) {
                return MAXRATIO;
            }
            return baseSize.mul(-1).mulU(MAXRATIO).divU(baseAmount).abs();
        } else {
            //calculate debt
            uint256[2] memory result = IAmm(amm).swapQueryWithAcctSpecMarkPrice(
                address(baseToken),
                address(quoteToken),
                0,
                quoteSize.abs()
            );
            //todo need to delete 10, this 10 is for simulating price fluctuation, bad for long
            uint256 baseAmount = result[0] * 10;
            uint256 ratio = baseAmount.mul(MAXRATIO).div(baseSize.abs());
            if (MAXRATIO < ratio) {
                return MAXRATIO;
            }
            return ratio;
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

    function getWithdrawable(address _trader) public view override returns (uint256) {
        Position memory traderPosition = traderPositionMap[_trader];
        uint256 withdrawableMargin;
        if (traderPosition.quoteSize < 0) {
            uint256[2] memory result = IAmm(amm).swapQuery(
                address(baseToken),
                address(quoteToken),
                0,
                traderPosition.quoteSize.abs()
            );

            uint256 baseAmount = result[0];
            uint256 baseNeeded = baseAmount.mul(MAXRATIO).div(MAXRATIO - IConfig(config).initMarginRatio());
            if (baseAmount.mul(MAXRATIO) % (MAXRATIO - IConfig(config).initMarginRatio()) != 0) {
                baseNeeded += 1;
            }

            if (traderPosition.baseSize.abs() < baseNeeded) {
                withdrawableMargin = 0;
            } else {
                withdrawableMargin = traderPosition.baseSize.abs().sub(baseNeeded);
            }
        } else {
            uint256[2] memory result = IAmm(amm).swapQuery(
                address(quoteToken),
                address(baseToken),
                traderPosition.quoteSize.abs(),
                0
            );

            uint256 baseAmount = result[1];
            uint256 baseNeeded = baseAmount.mul(MAXRATIO - IConfig(config).initMarginRatio()).div(MAXRATIO);
            if (traderPosition.baseSize < int256(-1).mulU(baseNeeded)) {
                withdrawableMargin = 0;
            } else {
                withdrawableMargin = traderPosition.baseSize.sub(int256(-1).mulU(baseNeeded)).abs();
            }
        }
        return withdrawableMargin;
    }

    function _setPosition(address _trader, Position memory _position) internal {
        traderPositionMap[_trader] = _position;
    }

    function _addPositionWithVAmm(bool isLong, uint256 _baseAmount) internal returns (uint256) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            _baseAmount,
            address(baseToken)
        );

        uint256[2] memory result = IAmm(amm).swap(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[0] : result[1];
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
        uint256 _quoteAmount,
        address _quoteToken
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
            outputToken = _quoteToken;
            outputAmount = _quoteAmount;
        } else {
            inputToken = _quoteToken;
            inputAmount = _quoteAmount;
        }
    }

    function _checkInitMarginRatio(Position memory traderPosition) internal view {
        require(
            _calMarginRatio(traderPosition.quoteSize, traderPosition.baseSize) >= IConfig(config).initMarginRatio(),
            "initMarginRatio"
        );
    }

    function _calMarginRatio(int256 quoteSize, int256 baseSize) internal view returns (uint256) {
        if (quoteSize == 0 || (quoteSize > 0 && baseSize >= 0)) {
            return MAXRATIO;
        } else if (quoteSize < 0 && baseSize <= 0) {
            return 0;
        } else if (quoteSize > 0) {
            //calculate asset
            uint256[2] memory result = IAmm(amm).swapQuery(address(quoteToken), address(baseToken), quoteSize.abs(), 0);
            uint256 baseAmount = result[1];
            if (baseSize.abs() >= baseAmount || baseAmount == 0) {
                return 0;
            }
            return baseSize.mulU(MAXRATIO).divU(baseAmount).addU(MAXRATIO).abs();
        } else {
            //calculate debt
            uint256[2] memory result = IAmm(amm).swapQuery(address(baseToken), address(quoteToken), 0, quoteSize.abs());

            uint256 baseAmount = result[0];
            uint256 ratio = baseAmount.mul(MAXRATIO).div(baseSize.abs());
            if (MAXRATIO < ratio) {
                return 0;
            }
            return MAXRATIO.sub(ratio);
        }
    }

    modifier onlyFactory() {
        require(factory == msg.sender, "factory");
        _;
    }

    modifier nonReentrant() {
        require(entered == false, "Reentrant: reentrant call");
        entered = true;
        _;
        entered = false;
    }
}

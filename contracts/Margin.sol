// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IMargin.sol";
import "./interfaces/IVault.sol";
import "./libraries/SignedDecimal.sol";
import "./utils/Reentrant.sol";

contract Margin is IMargin, IVault, Reentrant {
    using SignedDecimal for int256;

    struct Position {
        int256 quoteSize;
        int256 baseSize;
        uint256 tradeSize;
    }

    uint256 constant MAXRATIO = 10000;

    uint256 public override reserve;

    address public override factory;
    address public override amm;
    address public override baseToken;
    address public override quoteToken;
    address public override config;
    mapping(address => Position) public traderPositionMap;

    uint256 totalLong; //total long quoteSize
    uint256 totalShort; //total short quoteSize
    mapping(address => int256) public traderCPF;
    int256[] cumulativePremiumFractions;
    uint256 updateCPFInterval = 8 hours;
    uint256 fundingRatePrecision = 10000;
    uint256 lastUpdateFundingFee; //last update funding fee

    function updateFundingFee() public {
        //can update after at least fundingPayInterval
        if (block.timestamp < lastUpdateFundingFee + updateCPFInterval) {
            return;
        }

        //settleFunding is (markPrice - indexPrice) * updateCPFInterval / 1day
        // fixme should be amm's settle price
        int256 premiumFraction = 0;
        //to help lp
        int256 delta = premiumFraction > 0
            ? premiumFraction.mulU(totalLong).divU(totalShort)
            : premiumFraction.mulU(totalShort).divU(totalLong);

        cumulativePremiumFractions.push(delta + getLatestCPF());
        lastUpdateFundingFee = block.timestamp;
    }

    //calculate how much fundingFee can earn with quoteSize
    function calFundingFee() public view returns (int256) {
        //tocheck msg.sender is the right person?
        Position memory traderPosition = traderPositionMap[msg.sender];
        int256 diff = getLatestCPF() - traderCPF[msg.sender];
        if (traderPosition.quoteSize == 0 || diff == 0) {
            return 0;
        }

        //tocheck if need to trans quoteSize to base
        uint256[2] memory result;
        //long
        if (traderPosition.quoteSize < 0) {
            result = IAmm(amm).estimateSwap(address(baseToken), address(quoteToken), 0, traderPosition.quoteSize.abs());
            return -1 * diff.mulU(result[0]).divU(fundingRatePrecision);
        }
        //short
        result = IAmm(amm).estimateSwap(address(quoteToken), address(baseToken), traderPosition.quoteSize.abs(), 0);
        return diff.mulU(result[1]).divU(fundingRatePrecision);
    }

    function getLatestCPF() public view returns (int256 latestCPF) {
        uint256 len = cumulativePremiumFractions.length;
        if (len > 0) {
            latestCPF = cumulativePremiumFractions[len - 1];
        }
    }

    function queryRemainAfterFundingFee(uint256 baseAmount) internal view returns (uint256 remainBaseAmount) {
        int256 decimalFundingFee = calFundingFee();
        uint256 fundingFee = decimalFundingFee.abs();
        if (fundingFee > baseAmount && decimalFundingFee < 0) {
            return 0;
        }
        return decimalFundingFee < 0 ? baseAmount - fundingFee : baseAmount + fundingFee;
    }

    constructor() {
        factory = msg.sender;
    }

    function initialize(
        address _baseToken,
        address _quoteToken,
        address _config,
        address _amm
    ) external override {
        require(factory == msg.sender, "factory");
        amm = _amm;
        config = _config;
        baseToken = _baseToken;
        quoteToken = _quoteToken;
    }

    function addMargin(address _trader, uint256 _depositAmount) external override nonReentrant {
        require(_depositAmount > 0, ">0");
        Position memory traderPosition = traderPositionMap[_trader];
        updateFundingFee();

        uint256 balance = IERC20(baseToken).balanceOf(address(this));
        require(_depositAmount <= balance - reserve, "wrong deposit amount");

        traderPosition.baseSize = traderPosition.baseSize.addU(_depositAmount);
        _setPosition(_trader, traderPosition);
        _deposit(_trader, _depositAmount);

        emit AddMargin(_trader, _depositAmount);
    }

    function removeMargin(uint256 _withdrawAmount) external override nonReentrant {
        require(_withdrawAmount > 0, ">0");
        //fixme
        // address trader = msg.sender;
        address trader = tx.origin;

        updateFundingFee();
        Position memory traderPosition = traderPositionMap[trader];
        // check before subtract
        require(_withdrawAmount <= getWithdrawable(trader), "preCheck withdrawable");

        traderPosition.baseSize = traderPosition.baseSize.subU(_withdrawAmount) + calFundingFee();
        if (traderPosition.quoteSize != 0) {
            // important! check position health, maybe no need because have checked getWithdrawable
            _checkInitMarginRatio(traderPosition);
        }
        traderCPF[msg.sender] = getLatestCPF();
        _setPosition(trader, traderPosition);
        _withdraw(trader, trader, _withdrawAmount);

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
        updateFundingFee();

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
            traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount) + calFundingFee();
            totalLong += _quoteAmount;
        } else {
            traderPosition.quoteSize = traderPosition.quoteSize.addU(_quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount) + calFundingFee();
            totalShort += _quoteAmount;
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

        traderCPF[msg.sender] = getLatestCPF();
        _checkInitMarginRatio(traderPosition);
        _setPosition(trader, traderPosition);
        emit OpenPosition(trader, _side, baseAmount, _quoteAmount);
    }

    function closePosition(uint256 _quoteAmount) external override nonReentrant returns (uint256 baseAmount) {
        //fixme
        // address trader = msg.sender;
        address trader = tx.origin;
        updateFundingFee();

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
                totalLong -= quoteSize;
                int256 remainBaseAmount = traderPosition.baseSize.subU(baseAmount) + calFundingFee();
                if (remainBaseAmount >= 0) {
                    _minusPositionWithVAmm(isLong, quoteSize);
                    traderPosition.quoteSize = 0;
                    traderPosition.tradeSize = 0;
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
                totalShort -= quoteSize;
                int256 remainBaseAmount = traderPosition.baseSize.addU(baseAmount) + calFundingFee();
                if (remainBaseAmount >= 0) {
                    _minusPositionWithVAmm(isLong, quoteSize);
                    traderPosition.quoteSize = 0;
                    traderPosition.tradeSize = 0;
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
                totalLong -= _quoteAmount;
                traderPosition.quoteSize = traderPosition.quoteSize.addU(_quoteAmount);
                traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount) + calFundingFee();
            } else {
                totalShort -= _quoteAmount;
                traderPosition.quoteSize = traderPosition.quoteSize.subU(_quoteAmount);
                traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount) + calFundingFee();
            }

            if (traderPosition.quoteSize != 0) {
                require(traderPosition.tradeSize >= baseAmount, "not closable");
                traderPosition.tradeSize = traderPosition.tradeSize - baseAmount;
                _checkInitMarginRatio(traderPosition);
            } else {
                traderPosition.tradeSize = 0;
            }
        }

        traderCPF[msg.sender] = getLatestCPF();
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
        updateFundingFee();
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
            totalLong -= traderPosition.quoteSize.abs();
            int256 remainBaseAmount = traderPosition.baseSize.subU(baseAmount - bonus) + calFundingFee();
            IAmm(amm).forceSwap(
                address(baseToken),
                address(quoteToken),
                remainBaseAmount.abs(),
                traderPosition.quoteSize.abs()
            );
        } else {
            totalShort -= traderPosition.quoteSize.abs();
            int256 remainBaseAmount = traderPosition.baseSize.addU(baseAmount - bonus) + calFundingFee();
            IAmm(amm).forceSwap(
                address(quoteToken),
                address(baseToken),
                traderPosition.quoteSize.abs(),
                remainBaseAmount.abs()
            );
        }
        traderCPF[msg.sender] = getLatestCPF();
        _withdraw(_trader, msg.sender, bonus);
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

        uint256[2] memory result = IAmm(amm).estimateSwap(inputToken, outputToken, inputAmount, outputAmount);
        quoteAmount = isLong ? result[0] : result[1];
    }

    function getMarginRatio(address _trader) external view returns (uint256) {
        Position memory position = traderPositionMap[_trader];
        return _calMarginRatio(position.quoteSize, position.baseSize);
    }

    //when minus position, query first
    function querySwapBaseWithVAmm(bool isLong, uint256 _quoteAmount) public view returns (uint256) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            _quoteAmount,
            address(quoteToken)
        );

        uint256[2] memory result = IAmm(amm).estimateSwap(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[0] : result[1];
    }

    function calDebtRatio(int256 quoteSize, int256 baseSize) public view returns (uint256 debtRatio) {
        baseSize += calFundingFee();
        if (quoteSize == 0 || (quoteSize > 0 && baseSize >= 0)) {
            debtRatio = 0;
        } else if (quoteSize < 0 && baseSize <= 0) {
            debtRatio = MAXRATIO;
        } else if (quoteSize > 0) {
            //calculate asset
            uint256[2] memory result = IAmm(amm).estimateSwapWithMarkPrice(
                address(quoteToken),
                address(baseToken),
                quoteSize.abs(),
                0
            );
            uint256 baseAmount = result[1];
            debtRatio = baseAmount == 0 ? MAXRATIO : (0 - baseSize).mulU(MAXRATIO).divU(baseAmount).abs();
        } else {
            //calculate debt
            uint256[2] memory result = IAmm(amm).estimateSwapWithMarkPrice(
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
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(baseToken),
                address(quoteToken),
                0,
                traderPosition.quoteSize.abs()
            );

            uint256 baseAmount = queryRemainAfterFundingFee(result[0]);
            if (baseAmount == 0) {
                return 0;
            }
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
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(quoteToken),
                address(baseToken),
                traderPosition.quoteSize.abs(),
                0
            );

            uint256 baseAmount = queryRemainAfterFundingFee(result[1]);
            if (baseAmount == 0) {
                return 0;
            }

            uint256 baseNeeded = (baseAmount * (MAXRATIO - IConfig(config).initMarginRatio())) / (MAXRATIO);
            withdrawableMargin = traderPosition.baseSize < int256(-1).mulU(baseNeeded)
                ? 0
                : (traderPosition.baseSize - int256(-1).mulU(baseNeeded)).abs();
        }
    }

    function deposit(address user, uint256 amount) external override nonReentrant {
        require(msg.sender == amm, "Margin: REQUIRE_AMM");
        uint256 balance = IERC20(baseToken).balanceOf(address(this));
        require(amount <= balance - reserve, "Margin: INSUFFICIENT_AMOUNT");
        _deposit(user, amount);
    }

    function withdraw(
        address user,
        address receiver,
        uint256 amount
    ) external override nonReentrant {
        require(msg.sender == amm, "Margin: REQUIRE_AMM");
        _withdraw(user, receiver, amount);
    }

    function _deposit(address user, uint256 amount) internal {
        require(amount > 0, "Margin: AMOUNT_IS_ZERO");
        reserve += amount;
        emit Deposit(user, amount);
    }

    function _withdraw(
        address user,
        address receiver,
        uint256 amount
    ) internal {
        require(amount > 0, "Margin: AMOUNT_IS_ZERO");
        require(amount <= reserve, "Margin: ONT_ENOUGH_RESERVE");
        reserve -= amount;
        IERC20(baseToken).transfer(receiver, amount);
        emit Withdraw(user, receiver, amount);
    }

    function _setPosition(address _trader, Position memory _position) internal {
        traderPositionMap[_trader] = _position;
    }

    function _addPositionWithVAmm(bool isLong, uint256 _quoteAmount) internal returns (uint256) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            !isLong,
            _quoteAmount,
            address(quoteToken)
        );

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

    function _checkInitMarginRatio(Position memory traderPosition) public view {
        require(
            _calMarginRatio(traderPosition.quoteSize, traderPosition.baseSize) >= IConfig(config).initMarginRatio(),
            "initMarginRatio"
        );
    }

    function _calMarginRatio(int256 quoteSize, int256 baseSize) public view returns (uint256 marginRatio) {
        //pay funding fee first
        baseSize += calFundingFee();
        if (quoteSize == 0 || (quoteSize > 0 && baseSize >= 0)) {
            marginRatio = MAXRATIO;
        } else if (quoteSize < 0 && baseSize <= 0) {
            marginRatio = 0;
        } else if (quoteSize > 0) {
            //short, calculate asset
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(quoteToken),
                address(baseToken),
                quoteSize.abs(),
                0
            );
            //asset
            uint256 baseAmount = result[1];
            marginRatio = (baseSize.abs() >= baseAmount || baseAmount == 0)
                ? 0
                : baseSize.mulU(MAXRATIO).divU(baseAmount).addU(MAXRATIO).abs();
        } else {
            //long, calculate debt
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(baseToken),
                address(quoteToken),
                0,
                quoteSize.abs()
            );
            //debt
            uint256 baseAmount = result[0];
            marginRatio = baseSize.abs() < baseAmount ? 0 : MAXRATIO - ((baseAmount * MAXRATIO) / baseSize.abs());
        }
    }
}

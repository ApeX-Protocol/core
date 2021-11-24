// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IMarginFactory.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IMargin.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IPriceOracle.sol";
import "./utils/Reentrant.sol";
import "./libraries/SignedMath.sol";

contract Margin is IMargin, IVault, Reentrant {
    using SignedMath for int256;

    struct Position {
        int256 quoteSize;
        int256 baseSize;
        uint256 tradeSize;
    }

    uint256 constant MAXRATIO = 10000;
    uint256 constant fundingRatePrecision = 1e18;
    uint256 constant maxCPFBoost = 10;

    address public immutable override factory;
    address public override config;
    address public override amm;
    address public override baseToken;
    address public override quoteToken;
    mapping(address => Position) public traderPositionMap;
    mapping(address => int256) public traderCPF;
    uint256 public override reserve;
    uint256 public lastUpdateCPF; //last timestamp update cumulative premium fraction
    uint256 internal totalLong; //total long quoteSize
    uint256 internal totalShort; //total short quoteSize
    int256 internal latestCPF;

    constructor() {
        factory = msg.sender;
    }

    function initialize(
        address baseToken_,
        address quoteToken_,
        address amm_
    ) external override {
        require(factory == msg.sender, "Margin.initialize: FORBIDDEN");
        baseToken = baseToken_;
        quoteToken = quoteToken_;
        amm = amm_;
        config = IMarginFactory(factory).config();
    }

    function addMargin(address trader, uint256 depositAmount) external override nonReentrant {
        require(depositAmount > 0, "Margin.addMargin: ZERO_DEPOSIT_AMOUNT");

        uint256 balance = IERC20(baseToken).balanceOf(address(this));
        uint256 formerReserve = reserve;
        require(depositAmount <= balance - formerReserve, "Margin.addMargin;: WRONG_DEPOSIT_AMOUNT");
        Position storage traderPosition = traderPositionMap[trader];
        traderPosition.baseSize = traderPosition.baseSize.addU(depositAmount);
        reserve = formerReserve + depositAmount;
        emit AddMargin(trader, depositAmount);
    }

    function removeMargin(address trader, uint256 withdrawAmount) external override nonReentrant {
        require(withdrawAmount > 0, "Margin.removeMargin: ZERO_WITHDRAW_AMOUNT");
        if (msg.sender != trader) {
            require(IConfig(config).routerMap(msg.sender), "Margin.removeMargin: FORBIDDEN");
        }
        int256 _latestCPF = updateCPF();

        //tocheck test carefully if withdraw margin more than withdrawable
        require(withdrawAmount <= _getWithdrawable(trader, _latestCPF), "Margin.removeMargin: NOT_ENOUGH_WITHDRAWABLE");

        Position storage traderPosition = traderPositionMap[trader];
        int256 fundingFee = _calFundingFee(_latestCPF);
        traderPosition.baseSize = traderPosition.baseSize.subU(withdrawAmount) + fundingFee;
        traderCPF[trader] = _latestCPF;
        _withdraw(trader, trader, withdrawAmount);

        emit RemoveMargin(trader, withdrawAmount);
    }

    function openPosition(
        address trader,
        uint8 side,
        uint256 quoteAmount
    ) external override nonReentrant returns (uint256 baseAmount) {
        require(side == 0 || side == 1, "Margin.openPosition: INVALID_SIDE");
        require(quoteAmount > 0, "Margin.openPosition: ZERO_QUOTE_AMOUNT");
        if (msg.sender != trader) {
            require(IConfig(config).routerMap(msg.sender), "Margin.removeMargin: FORBIDDEN");
        }
        int256 _latestCPF = updateCPF();

        Position memory traderPosition = traderPositionMap[trader];
        bool isLong = side == 0;
        bool sameDir = traderPosition.quoteSize == 0 ||
            (traderPosition.quoteSize < 0 == isLong) ||
            (traderPosition.quoteSize > 0 == !isLong);

        //swap exact quote to base
        baseAmount = _addPositionWithAmm(isLong, quoteAmount);
        require(baseAmount > 0, "Margin.openPosition: TINY_QUOTE_AMOUNT");

        //old: quote -10, base 11; add long 5X position 1: quote -5, base +5; new: quote -15, base 16
        //old: quote 10, base -9; add long 5X position: quote -5, base +5; new: quote 5, base -4
        //old: quote 10, base -9; add long 15X position: quote -15, base +15; new: quote -5, base 6
        int256 fundingFee = _calFundingFee(_latestCPF);
        if (isLong) {
            traderPosition.quoteSize = traderPosition.quoteSize.subU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount) + fundingFee;
            totalLong += quoteAmount;
        } else {
            traderPosition.quoteSize = traderPosition.quoteSize.addU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount) + fundingFee;
            totalShort += quoteAmount;
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

        traderCPF[msg.sender] = _latestCPF;
        //TODO 是否有必要做这个检查？
        _checkInitMarginRatio(traderPosition, _latestCPF);
        traderPositionMap[trader] = traderPosition;
        emit OpenPosition(trader, side, baseAmount, quoteAmount);
    }

    function closePosition(address trader, uint256 quoteAmount)
        external
        override
        nonReentrant
        returns (uint256 baseAmount)
    {
        if (msg.sender != trader) {
            require(IConfig(config).routerMap(msg.sender), "Margin.closePosition: FORBIDDEN");
        }
        int256 _latestCPF = updateCPF();

        Position memory traderPosition = traderPositionMap[trader];
        require(traderPosition.quoteSize != 0 && quoteAmount != 0, "Margin.closePosition: ZERO_POSITION");
        require(quoteAmount <= traderPosition.quoteSize.abs(), "Margin.closePosition: ABOVE_POSITION");
        //swap exact quote to base
        bool isLong = traderPosition.quoteSize < 0;
        int256 fundingFee = _calFundingFee(_latestCPF);
        uint256 debtRatio = _calDebtRatio(traderPosition.quoteSize, traderPosition.baseSize, fundingFee);
        // todo test carefully
        //liquidatable
        if (debtRatio >= IConfig(config).liquidateThreshold()) {
            uint256 quoteSize = traderPosition.quoteSize.abs();
            baseAmount = _querySwapBaseWithVAmm(isLong, quoteSize);
            if (isLong) {
                totalLong -= quoteSize;
                int256 remainBaseAmount = traderPosition.baseSize.subU(baseAmount) + fundingFee;
                if (remainBaseAmount >= 0) {
                    _minusPositionWithAmm(isLong, quoteSize);
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
                int256 remainBaseAmount = traderPosition.baseSize.addU(baseAmount) + fundingFee;
                if (remainBaseAmount >= 0) {
                    _minusPositionWithAmm(isLong, quoteSize);
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
            baseAmount = _minusPositionWithAmm(isLong, quoteAmount);
            //old: quote -10, base 11; close position: quote 5, base -5; new: quote -5, base 6
            //old: quote 10, base -9; close position: quote -5, base +5; new: quote 5, base -4
            if (isLong) {
                totalLong -= quoteAmount;
                traderPosition.quoteSize = traderPosition.quoteSize.addU(quoteAmount);
                traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount) + fundingFee;
            } else {
                totalShort -= quoteAmount;
                traderPosition.quoteSize = traderPosition.quoteSize.subU(quoteAmount);
                traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount) + fundingFee;
            }

            if (traderPosition.quoteSize != 0) {
                require(traderPosition.tradeSize >= baseAmount, "Margin.closePosition: NOT_CLOSABLE");
                traderPosition.tradeSize = traderPosition.tradeSize - baseAmount;
                _checkInitMarginRatio(traderPosition, _latestCPF);
            } else {
                traderPosition.tradeSize = 0;
            }
        }

        traderCPF[trader] = _latestCPF;
        traderPositionMap[trader] = traderPosition;
        emit ClosePosition(trader, quoteAmount, baseAmount);
    }

    function liquidate(address trader)
        external
        override
        nonReentrant
        returns (
            uint256 quoteAmount,
            uint256 baseAmount,
            uint256 bonus
        )
    {
        int256 _latestCPF = updateCPF();
        Position memory traderPosition = traderPositionMap[trader];
        int256 quoteSize = traderPosition.quoteSize;
        require(quoteSize != 0, "Margin.liquidate: ZERO_POSITION");
        require(_canLiquidate(trader, _latestCPF), "Margin.liquidate: NOT_LIQUIDATABLE");

        bool isLong = quoteSize < 0;
        //query swap exact quote to base
        quoteAmount = quoteSize.abs();
        baseAmount = _querySwapBaseWithVAmm(isLong, quoteAmount);

        //calc liquidate fee
        uint256 liquidateFeeRatio = IConfig(config).liquidateFeeRatio();
        bonus = (baseAmount * liquidateFeeRatio) / MAXRATIO;
        int256 fundingFee = _calFundingFee(_latestCPF);
        int256 remainBaseAmount = traderPosition.baseSize.subU(bonus) + fundingFee;
        if (isLong) {
            totalLong -= quoteAmount;
            IAmm(amm).forceSwap(address(baseToken), address(quoteToken), remainBaseAmount.abs(), quoteAmount);
        } else {
            totalShort -= quoteAmount;
            IAmm(amm).forceSwap(address(quoteToken), address(baseToken), quoteAmount, remainBaseAmount.abs());
        }

        traderCPF[trader] = _latestCPF;
        _withdraw(trader, msg.sender, bonus);

        traderPosition.baseSize = 0;
        traderPosition.quoteSize = 0;
        traderPosition.tradeSize = 0;
        traderPositionMap[trader] = traderPosition;
        emit Liquidate(msg.sender, trader, quoteAmount, baseAmount, bonus);
    }

    function deposit(address user, uint256 amount) external override nonReentrant {
        require(msg.sender == amm, "Margin.deposit: REQUIRE_AMM");
        require(amount > 0, "Margin.deposit: AMOUNT_IS_ZERO");
        uint256 balance = IERC20(baseToken).balanceOf(address(this));
        require(amount <= balance - reserve, "Margin.deposit: INSUFFICIENT_AMOUNT");

        reserve = reserve + amount;

        emit Deposit(user, amount);
    }

    function querySwapBaseWithVAmm(bool isLong, uint256 quoteAmount) external view returns (uint256) {
        return _querySwapBaseWithVAmm(isLong, quoteAmount);
    }

    function withdraw(
        address user,
        address receiver,
        uint256 amount
    ) external override nonReentrant {
        require(msg.sender == amm, "Margin.withdraw: REQUIRE_AMM");

        _withdraw(user, receiver, amount);
    }

    function _withdraw(
        address user,
        address receiver,
        uint256 amount
    ) internal {
        require(amount > 0, "Margin._withdraw: AMOUNT_IS_ZERO");
        require(amount <= reserve, "Margin._withdraw: NOT_ENOUGH_RESERVE");
        reserve = reserve - amount;
        IERC20(baseToken).transfer(receiver, amount);
        emit Withdraw(user, receiver, amount);
    }

    function _addPositionWithAmm(bool isLong, uint256 quoteAmount) internal returns (uint256) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            !isLong,
            quoteAmount,
            address(quoteToken)
        );

        uint256[2] memory result = IAmm(amm).swap(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[1] : result[0];
    }

    function _minusPositionWithAmm(bool isLong, uint256 quoteAmount) internal returns (uint256) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            quoteAmount,
            address(quoteToken)
        );

        uint256[2] memory result = IAmm(amm).swap(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[0] : result[1];
    }

    function updateCPF() public returns (int256 newLatestCPF) {
        uint256 currentTimeStamp = block.timestamp;
        newLatestCPF = _getNewLatestCPF();

        latestCPF = newLatestCPF;
        lastUpdateCPF = currentTimeStamp;
        emit UpdateCPF(currentTimeStamp, newLatestCPF);
    }

    function getPosition(address trader)
        external
        view
        override
        returns (
            int256,
            int256,
            uint256
        )
    {
        Position memory position = traderPositionMap[trader];
        return (position.baseSize, position.quoteSize, position.tradeSize);
    }

    function getMaxOpenPosition(uint8 side, uint256 marginAmount) external view override returns (uint256 quoteAmount) {
        require(side == 0 || side == 1, "Margin.getMaxOpenPosition: INVALID_SIDE");
        bool isLong = side == 0;
        uint256 maxBase;
        if (isLong) {
            maxBase = marginAmount * (MAXRATIO / IConfig(config).initMarginRatio() - 1);
        } else {
            maxBase = (marginAmount * MAXRATIO) / IConfig(config).initMarginRatio();
        }

        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            maxBase,
            address(baseToken)
        );

        uint256[2] memory result = IAmm(amm).estimateSwap(inputToken, outputToken, inputAmount, outputAmount);
        quoteAmount = isLong ? result[0] : result[1];
    }

    function getWithdrawable(address trader) external view override returns (uint256 amount) {
        return _getWithdrawable(trader, _getNewLatestCPF());
    }

    function getMarginRatio(address trader) external view returns (uint256) {
        Position memory position = traderPositionMap[trader];
        return _calMarginRatio(position.quoteSize, position.baseSize, _getNewLatestCPF());
    }

    function canLiquidate(address trader) external view override returns (bool) {
        return _canLiquidate(trader, _getNewLatestCPF());
    }

    function calFundingFee() external view override returns (int256) {
        return _calFundingFee(_getNewLatestCPF());
    }

    function calDebtRatio(int256 quoteSize, int256 baseSize) external view override returns (uint256 debtRatio) {
        int256 fundingFee = _calFundingFee(_getNewLatestCPF());
        return _calDebtRatio(quoteSize, baseSize, fundingFee);
    }

    function _querySwapBaseWithVAmm(bool isLong, uint256 quoteAmount) internal view returns (uint256) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            quoteAmount,
            address(quoteToken)
        );

        uint256[2] memory result = IAmm(amm).estimateSwap(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[0] : result[1];
    }

    function _getNewLatestCPF() internal view returns (int256 newLatestCPF) {
        //premiumFraction is (markPrice - indexPrice) * fundingRatePrecision / 8h / indexPrice
        int256 premiumFraction = IPriceOracle(IConfig(config).priceOracle()).getPremiumFraction(amm);
        int256 delta;
        if (
            totalLong <= maxCPFBoost * totalShort &&
            totalShort <= maxCPFBoost * totalLong &&
            (totalShort != 0 && totalLong != 0)
        ) {
            delta = premiumFraction >= 0
                ? premiumFraction.mulU(totalLong).divU(totalShort)
                : premiumFraction.mulU(totalShort).divU(totalLong);
        } else if (totalLong > maxCPFBoost * totalShort) {
            delta = premiumFraction >= 0 ? premiumFraction.mulU(maxCPFBoost) : premiumFraction.divU(maxCPFBoost);
        } else if (totalShort > maxCPFBoost * totalLong) {
            delta = premiumFraction >= 0 ? premiumFraction.divU(maxCPFBoost) : premiumFraction.mulU(maxCPFBoost);
        } else {
            delta = premiumFraction;
        }

        newLatestCPF = delta.mulU(block.timestamp - lastUpdateCPF) + latestCPF;
    }

    //calculate how much fundingFee can earn with quoteSize
    function _calFundingFee(int256 _latestCPF) internal view returns (int256) {
        //tocheck msg.sender is the right person?
        Position memory traderPosition = traderPositionMap[msg.sender];
        int256 diff = _latestCPF - traderCPF[msg.sender];
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

    function _queryRemainAfterFundingFee(uint256 baseAmount, int256 _latestCPF)
        internal
        view
        returns (uint256 remainBaseAmount)
    {
        int256 decimalFundingFee = _calFundingFee(_latestCPF);
        uint256 fundingFee = decimalFundingFee.abs();
        if (fundingFee >= baseAmount && decimalFundingFee < 0) {
            return 0;
        }
        return decimalFundingFee < 0 ? baseAmount - fundingFee : baseAmount + fundingFee;
    }

    function _getWithdrawable(address trader, int256 _latestCPF) internal view returns (uint256 amount) {
        Position memory traderPosition = traderPositionMap[trader];
        //tocheck calculate the funding fee right now...
        traderPosition.baseSize += _calFundingFee(_latestCPF);

        if (traderPosition.quoteSize == 0) {
            amount = traderPosition.baseSize <= 0 ? 0 : traderPosition.baseSize.abs();
        } else if (traderPosition.quoteSize < 0) {
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(baseToken),
                address(quoteToken),
                0,
                traderPosition.quoteSize.abs()
            );

            uint256 baseAmount = _queryRemainAfterFundingFee(result[0], _latestCPF);
            if (baseAmount == 0) {
                return 0;
            }
            uint256 a = baseAmount * MAXRATIO;
            uint256 b = (MAXRATIO - IConfig(config).initMarginRatio());
            uint256 baseNeeded = a / b;
            if (a % b != 0) {
                baseNeeded += 1;
            }

            amount = traderPosition.baseSize.abs() < baseNeeded ? 0 : traderPosition.baseSize.abs() - baseNeeded;
        } else {
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(quoteToken),
                address(baseToken),
                traderPosition.quoteSize.abs(),
                0
            );

            uint256 baseAmount = _queryRemainAfterFundingFee(result[1], _latestCPF);
            if (baseAmount == 0) {
                return 0;
            }
            uint256 baseNeeded = (baseAmount * (MAXRATIO - IConfig(config).initMarginRatio())) / (MAXRATIO);
            amount = traderPosition.baseSize < int256(-1).mulU(baseNeeded)
                ? 0
                : (traderPosition.baseSize - int256(-1).mulU(baseNeeded)).abs();
        }
    }

    function _canLiquidate(address trader, int256 _latestCPF) internal view returns (bool) {
        Position memory traderPosition = traderPositionMap[trader];
        int256 fundingFee = _calFundingFee(_latestCPF);

        uint256 debtRatio = _calDebtRatio(traderPosition.quoteSize, traderPosition.baseSize, fundingFee);
        return debtRatio >= IConfig(config).liquidateThreshold();
    }

    function _calDebtRatio(
        int256 quoteSize,
        int256 baseSize,
        int256 fundingFee
    ) internal view returns (uint256 debtRatio) {
        baseSize += fundingFee;
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

    function _checkInitMarginRatio(Position memory traderPosition, int256 _latestCPF) internal view {
        require(
            _calMarginRatio(traderPosition.quoteSize, traderPosition.baseSize, _latestCPF) >=
                IConfig(config).initMarginRatio(),
            "initMarginRatio"
        );
    }

    function _calMarginRatio(
        int256 quoteSize,
        int256 baseSize,
        int256 _latestCPF
    ) internal view returns (uint256 marginRatio) {
        //pay funding fee first
        baseSize += _calFundingFee(_latestCPF);

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

    function _getSwapParam(
        bool isLong,
        uint256 amount,
        address token
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
            outputToken = token;
            outputAmount = amount;
        } else {
            inputToken = token;
            inputAmount = amount;
        }
    }
}

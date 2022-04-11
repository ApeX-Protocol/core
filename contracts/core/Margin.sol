// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IMarginFactory.sol";
import "./interfaces/IAmmFactory.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IMargin.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IWETH.sol";
import "../utils/Reentrant.sol";
import "../libraries/SignedMath.sol";
import "../libraries/ChainAdapter.sol";

contract Margin is IMargin, IVault, Reentrant {
    using SignedMath for int256;

    address public immutable override factory;
    address public override config;
    address public override amm;
    address public override baseToken;
    address public override quoteToken;
    mapping(address => Position) public traderPositionMap;
    mapping(address => int256) public traderCPF; //trader's latestCPF checkpoint, to calculate funding fee
    uint256 public override reserve;
    uint256 public lastUpdateCPF; //last timestamp update cpf
    uint256 public totalQuoteLong;
    uint256 public totalQuoteShort;
    int256 internal latestCPF; //latestCPF with 1e18 multiplied

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

    //@notice before add margin, ensure contract's baseToken balance larger than depositAmount
    function addMargin(address trader, uint256 depositAmount) external override nonReentrant {
        uint256 balance = IERC20(baseToken).balanceOf(address(this));
        uint256 _reserve = reserve;
        require(depositAmount <= balance - _reserve, "Margin.addMargin: WRONG_DEPOSIT_AMOUNT");
        Position memory traderPosition = traderPositionMap[trader];

        traderPosition.baseSize = traderPosition.baseSize.addU(depositAmount);
        traderPositionMap[trader] = traderPosition;
        reserve = _reserve + depositAmount;

        emit AddMargin(trader, depositAmount, traderPosition);
    }

    //remove baseToken from trader's fundingFee+unrealizedPnl+margin, remain position need to meet the requirement of initMarginRatio
    function removeMargin(
        address trader,
        address to,
        uint256 withdrawAmount
    ) external override nonReentrant {
        require(withdrawAmount > 0, "Margin.removeMargin: ZERO_WITHDRAW_AMOUNT");
        require(IConfig(config).routerMap(msg.sender), "Margin.removeMargin: FORBIDDEN");
        int256 _latestCPF = updateCPF();
        Position memory traderPosition = traderPositionMap[trader];

        //after last time operating trader's position, new fundingFee to earn.
        int256 fundingFee = _calFundingFee(trader, _latestCPF);
        //if close all position, trader can withdraw how much and earn how much pnl
        (uint256 withdrawableAmount, int256 unrealizedPnl) = _getWithdrawable(
            traderPosition.quoteSize,
            traderPosition.baseSize + fundingFee,
            traderPosition.tradeSize
        );
        require(withdrawAmount <= withdrawableAmount, "Margin.removeMargin: NOT_ENOUGH_WITHDRAWABLE");

        uint256 withdrawAmountFromMargin;
        //withdraw from fundingFee firstly, then unrealizedPnl, finally margin
        int256 uncoverAfterFundingFee = int256(1).mulU(withdrawAmount) - fundingFee;
        if (uncoverAfterFundingFee > 0) {
            //fundingFee cant cover withdrawAmount, use unrealizedPnl and margin.
            //update tradeSize only, no quoteSize, so can sub uncoverAfterFundingFee directly
            if (uncoverAfterFundingFee <= unrealizedPnl) {
                traderPosition.tradeSize -= uncoverAfterFundingFee.abs();
            } else {
                //fundingFee and unrealizedPnl cant cover withdrawAmount, use margin
                withdrawAmountFromMargin = (uncoverAfterFundingFee - unrealizedPnl).abs();
                //update tradeSize to current price to make unrealizedPnl zero
                traderPosition.tradeSize = traderPosition.quoteSize < 0
                    ? (int256(1).mulU(traderPosition.tradeSize) - unrealizedPnl).abs()
                    : (int256(1).mulU(traderPosition.tradeSize) + unrealizedPnl).abs();
            }
        }

        traderPosition.baseSize = traderPosition.baseSize - uncoverAfterFundingFee;

        traderPositionMap[trader] = traderPosition;
        traderCPF[trader] = _latestCPF;
        _withdraw(trader, to, withdrawAmount);

        emit RemoveMargin(trader, to, withdrawAmount, fundingFee, withdrawAmountFromMargin, traderPosition);
    }

    function openPosition(
        address trader,
        uint8 side,
        uint256 quoteAmount
    ) external override nonReentrant returns (uint256 baseAmount) {
        require(side == 0 || side == 1, "Margin.openPosition: INVALID_SIDE");
        require(quoteAmount > 0, "Margin.openPosition: ZERO_QUOTE_AMOUNT");
        require(IConfig(config).routerMap(msg.sender), "Margin.openPosition: FORBIDDEN");
        int256 _latestCPF = updateCPF();

        Position memory traderPosition = traderPositionMap[trader];

        uint256 quoteSizeAbs = traderPosition.quoteSize.abs();
        int256 fundingFee = _calFundingFee(trader, _latestCPF);

        uint256 quoteAmountMax;
        {
            int256 marginAcc;
            if (traderPosition.quoteSize == 0) {
                marginAcc = traderPosition.baseSize + fundingFee;
            } else if (traderPosition.quoteSize > 0) {
                //simulate to close short
                uint256[2] memory result = IAmm(amm).estimateSwap(
                    address(quoteToken),
                    address(baseToken),
                    traderPosition.quoteSize.abs(),
                    0
                );
                marginAcc = traderPosition.baseSize.addU(result[1]) + fundingFee;
            } else {
                //simulate to close long
                uint256[2] memory result = IAmm(amm).estimateSwap(
                    address(baseToken),
                    address(quoteToken),
                    0,
                    traderPosition.quoteSize.abs()
                );
                marginAcc = traderPosition.baseSize.subU(result[0]) + fundingFee;
            }
            require(marginAcc > 0, "Margin.openPosition: INVALID_MARGIN_ACC");
            (, uint112 quoteReserve, ) = IAmm(amm).getReserves();
            (, uint256 _quoteAmountT, bool isIndexPrice) = IPriceOracle(IConfig(config).priceOracle())
                .getMarkPriceInRatio(amm, 0, marginAcc.abs());

            uint256 _quoteAmount = isIndexPrice
                ? _quoteAmountT
                : IAmm(amm).estimateSwap(baseToken, quoteToken, marginAcc.abs(), 0)[1];

            quoteAmountMax =
                (quoteReserve * 10000 * _quoteAmount) /
                ((IConfig(config).initMarginRatio() * quoteReserve) + (200 * _quoteAmount * IConfig(config).beta()));
        }

        bool isLong = side == 0;
        baseAmount = _addPositionWithAmm(trader, isLong, quoteAmount);
        require(baseAmount > 0, "Margin.openPosition: TINY_QUOTE_AMOUNT");

        if (
            traderPosition.quoteSize == 0 ||
            (traderPosition.quoteSize < 0 == isLong) ||
            (traderPosition.quoteSize > 0 == !isLong)
        ) {
            //baseAmount is real base cost
            traderPosition.tradeSize = traderPosition.tradeSize + baseAmount;
        } else {
            if (quoteAmount < quoteSizeAbs) {
                //entry price not change
                traderPosition.tradeSize =
                    traderPosition.tradeSize -
                    (quoteAmount * traderPosition.tradeSize) /
                    quoteSizeAbs;
            } else {
                //after close all opposite position, create new position with new entry price
                traderPosition.tradeSize = ((quoteAmount - quoteSizeAbs) * baseAmount) / quoteAmount;
            }
        }

        if (isLong) {
            traderPosition.quoteSize = traderPosition.quoteSize.subU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount) + fundingFee;
            totalQuoteLong = totalQuoteLong + quoteAmount;
        } else {
            traderPosition.quoteSize = traderPosition.quoteSize.addU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount) + fundingFee;
            totalQuoteShort = totalQuoteShort + quoteAmount;
        }
        require(traderPosition.quoteSize.abs() <= quoteAmountMax, "Margin.openPosition: INIT_MARGIN_RATIO");
        require(
            _calDebtRatio(traderPosition.quoteSize, traderPosition.baseSize) < IConfig(config).liquidateThreshold(),
            "Margin.openPosition: WILL_BE_LIQUIDATED"
        );

        traderCPF[trader] = _latestCPF;
        traderPositionMap[trader] = traderPosition;
        emit OpenPosition(trader, side, baseAmount, quoteAmount, fundingFee, traderPosition);
    }

    function closePosition(address trader, uint256 quoteAmount)
        external
        override
        nonReentrant
        returns (uint256 baseAmount)
    {
        require(IConfig(config).routerMap(msg.sender), "Margin.openPosition: FORBIDDEN");
        int256 _latestCPF = updateCPF();

        Position memory traderPosition = traderPositionMap[trader];
        require(quoteAmount != 0, "Margin.closePosition: ZERO_POSITION");
        uint256 quoteSizeAbs = traderPosition.quoteSize.abs();
        require(quoteAmount <= quoteSizeAbs, "Margin.closePosition: ABOVE_POSITION");

        bool isLong = traderPosition.quoteSize < 0;
        int256 fundingFee = _calFundingFee(trader, _latestCPF);
        require(
            _calDebtRatio(traderPosition.quoteSize, traderPosition.baseSize + fundingFee) <
                IConfig(config).liquidateThreshold(),
            "Margin.closePosition: DEBT_RATIO_OVER"
        );

        baseAmount = _minusPositionWithAmm(trader, isLong, quoteAmount);
        traderPosition.tradeSize -= (quoteAmount * traderPosition.tradeSize) / quoteSizeAbs;

        if (isLong) {
            totalQuoteLong = totalQuoteLong - quoteAmount;
            traderPosition.quoteSize = traderPosition.quoteSize.addU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount) + fundingFee;
        } else {
            totalQuoteShort = totalQuoteShort - quoteAmount;
            traderPosition.quoteSize = traderPosition.quoteSize.subU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount) + fundingFee;
        }
        if (traderPosition.quoteSize == 0 && traderPosition.baseSize < 0) {
            IAmm(amm).forceSwap(trader, quoteToken, baseToken, 0, traderPosition.baseSize.abs());
            traderPosition.baseSize = 0;
        }

        traderCPF[trader] = _latestCPF;
        traderPositionMap[trader] = traderPosition;

        emit ClosePosition(trader, quoteAmount, baseAmount, fundingFee, traderPosition);
    }

    function liquidate(address trader, address to)
        external
        override
        nonReentrant
        returns (
            uint256 quoteAmount,
            uint256 baseAmount,
            uint256 bonus
        )
    {
        require(IConfig(config).routerMap(msg.sender), "Margin.openPosition: FORBIDDEN");
        int256 _latestCPF = updateCPF();
        Position memory traderPosition = traderPositionMap[trader];
        int256 baseSize = traderPosition.baseSize;
        int256 quoteSize = traderPosition.quoteSize;
        require(quoteSize != 0, "Margin.liquidate: ZERO_POSITION");

        quoteAmount = quoteSize.abs();
        bool isLong = quoteSize < 0;
        int256 fundingFee = _calFundingFee(trader, _latestCPF);
        require(
            _calDebtRatio(quoteSize, baseSize + fundingFee) >= IConfig(config).liquidateThreshold(),
            "Margin.liquidate: NOT_LIQUIDATABLE"
        );

        {
            (uint256 _baseAmountT, , bool isIndexPrice) = IPriceOracle(IConfig(config).priceOracle())
                .getMarkPriceInRatio(amm, quoteAmount, 0);

            baseAmount = isIndexPrice ? _baseAmountT : _querySwapBaseWithAmm(isLong, quoteAmount);
            (uint256 _baseAmount, uint256 _quoteAmount) = (baseAmount, quoteAmount);
            bonus = _executeSettle(trader, isIndexPrice, isLong, fundingFee, baseSize, _baseAmount, _quoteAmount);
            if (isLong) {
                totalQuoteLong = totalQuoteLong - quoteSize.abs();
            } else {
                totalQuoteShort = totalQuoteShort - quoteSize.abs();
            }
        }

        traderCPF[trader] = _latestCPF;
        if (bonus > 0) {
            _withdraw(trader, to, bonus);
        }

        delete traderPositionMap[trader];

        emit Liquidate(msg.sender, trader, to, quoteAmount, baseAmount, bonus, fundingFee, traderPosition);
    }

    function _executeSettle(
        address _trader,
        bool isIndexPrice,
        bool isLong,
        int256 fundingFee,
        int256 baseSize,
        uint256 baseAmount,
        uint256 quoteAmount
    ) internal returns (uint256 bonus) {
        int256 remainBaseAmountAfterLiquidate = isLong
            ? baseSize.subU(baseAmount) + fundingFee
            : baseSize.addU(baseAmount) + fundingFee;

        if (remainBaseAmountAfterLiquidate >= 0) {
            bonus = (remainBaseAmountAfterLiquidate.abs() * IConfig(config).liquidateFeeRatio()) / 10000;
            if (!isIndexPrice) {
                if (isLong) {
                    IAmm(amm).forceSwap(_trader, baseToken, quoteToken, baseAmount, quoteAmount);
                } else {
                    IAmm(amm).forceSwap(_trader, quoteToken, baseToken, quoteAmount, baseAmount);
                }
            }

            if (remainBaseAmountAfterLiquidate.abs() > bonus) {
                address treasury = IAmmFactory(IAmm(amm).factory()).feeTo();
                if (treasury != address(0)) {
                    IERC20(baseToken).transfer(treasury, remainBaseAmountAfterLiquidate.abs() - bonus);
                } else {
                    IAmm(amm).forceSwap(
                        _trader,
                        baseToken,
                        quoteToken,
                        remainBaseAmountAfterLiquidate.abs() - bonus,
                        0
                    );
                }
            }
        } else {
            if (!isIndexPrice) {
                if (isLong) {
                    IAmm(amm).forceSwap(
                        _trader,
                        baseToken,
                        quoteToken,
                        ((baseSize.subU(bonus) + fundingFee).abs()),
                        quoteAmount
                    );
                } else {
                    IAmm(amm).forceSwap(
                        _trader,
                        quoteToken,
                        baseToken,
                        quoteAmount,
                        ((baseSize.subU(bonus) + fundingFee).abs())
                    );
                }
            } else {
                IAmm(amm).forceSwap(_trader, quoteToken, baseToken, 0, remainBaseAmountAfterLiquidate.abs());
            }
        }
    }

    function deposit(address user, uint256 amount) external override nonReentrant {
        require(msg.sender == amm, "Margin.deposit: REQUIRE_AMM");
        require(amount > 0, "Margin.deposit: AMOUNT_IS_ZERO");
        uint256 balance = IERC20(baseToken).balanceOf(address(this));
        require(amount <= balance - reserve, "Margin.deposit: INSUFFICIENT_AMOUNT");

        reserve = reserve + amount;

        emit Deposit(user, amount);
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

    //swap exact quote to base
    function _addPositionWithAmm(
        address trader,
        bool isLong,
        uint256 quoteAmount
    ) internal returns (uint256 baseAmount) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            !isLong,
            quoteAmount
        );

        uint256[2] memory result = IAmm(amm).swap(trader, inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[1] : result[0];
    }

    //close position, swap base to get exact quoteAmount, the base has contained pnl
    function _minusPositionWithAmm(
        address trader,
        bool isLong,
        uint256 quoteAmount
    ) internal returns (uint256 baseAmount) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            quoteAmount
        );

        uint256[2] memory result = IAmm(amm).swap(trader, inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[0] : result[1];
    }

    //update global funding fee
    function updateCPF() public override returns (int256 newLatestCPF) {
        uint256 currentTimeStamp = block.timestamp;
        newLatestCPF = _getNewLatestCPF();

        latestCPF = newLatestCPF;
        lastUpdateCPF = currentTimeStamp;

        emit UpdateCPF(currentTimeStamp, newLatestCPF);
    }

    function querySwapBaseWithAmm(bool isLong, uint256 quoteAmount) external view override returns (uint256) {
        return _querySwapBaseWithAmm(isLong, quoteAmount);
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

    function getWithdrawable(address trader) external view override returns (uint256 withdrawable) {
        Position memory position = traderPositionMap[trader];
        int256 fundingFee = _calFundingFee(trader, _getNewLatestCPF());

        (withdrawable, ) = _getWithdrawable(position.quoteSize, position.baseSize + fundingFee, position.tradeSize);
    }

    function getNewLatestCPF() external view override returns (int256) {
        return _getNewLatestCPF();
    }

    function canLiquidate(address trader) external view override returns (bool) {
        Position memory position = traderPositionMap[trader];
        int256 fundingFee = _calFundingFee(trader, _getNewLatestCPF());

        return
            _calDebtRatio(position.quoteSize, position.baseSize + fundingFee) >= IConfig(config).liquidateThreshold();
    }

    function calFundingFee(address trader) public view override returns (int256) {
        return _calFundingFee(trader, _getNewLatestCPF());
    }

    function calDebtRatio(address trader) external view override returns (uint256 debtRatio) {
        Position memory position = traderPositionMap[trader];
        int256 fundingFee = _calFundingFee(trader, _getNewLatestCPF());

        return _calDebtRatio(position.quoteSize, position.baseSize + fundingFee);
    }

    function calUnrealizedPnl(address trader) external view override returns (int256 unrealizedPnl) {
        Position memory position = traderPositionMap[trader];
        if (position.quoteSize.abs() == 0) return 0;
        (uint256 _baseAmountT, , bool isIndexPrice) = IPriceOracle(IConfig(config).priceOracle()).getMarkPriceInRatio(
            amm,
            position.quoteSize.abs(),
            0
        );
        uint256 repayBaseAmount = isIndexPrice
            ? _baseAmountT
            : _querySwapBaseWithAmm(position.quoteSize < 0, position.quoteSize.abs());
        if (position.quoteSize < 0) {
            //borrowed - repay, earn when borrow more and repay less
            unrealizedPnl = int256(1).mulU(position.tradeSize).subU(repayBaseAmount);
        } else if (position.quoteSize > 0) {
            //repay - lent, earn when lent less and repay more
            unrealizedPnl = int256(1).mulU(repayBaseAmount).subU(position.tradeSize);
        }
    }

    function netPosition() external view override returns (int256) {
        require(totalQuoteShort < type(uint128).max, "Margin.netPosition: OVERFLOW");
        return int256(totalQuoteShort).subU(totalQuoteLong);
    }

    function totalPosition() external view override returns (uint256 totalQuotePosition) {
        totalQuotePosition = totalQuoteLong + totalQuoteShort;
    }

    //query swap exact quote to base
    function _querySwapBaseWithAmm(bool isLong, uint256 quoteAmount) internal view returns (uint256) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            quoteAmount
        );

        uint256[2] memory result = IAmm(amm).estimateSwap(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[0] : result[1];
    }

    //@notice returns newLatestCPF with 1e18 multiplied
    function _getNewLatestCPF() internal view returns (int256 newLatestCPF) {
        int256 premiumFraction = IPriceOracle(IConfig(config).priceOracle()).getPremiumFraction(amm);
        uint256 maxCPFBoost = IConfig(config).maxCPFBoost();
        int256 delta;
        if (
            totalQuoteLong <= maxCPFBoost * totalQuoteShort &&
            totalQuoteShort <= maxCPFBoost * totalQuoteLong &&
            !(totalQuoteShort == 0 && totalQuoteLong == 0)
        ) {
            delta = premiumFraction >= 0
                ? premiumFraction.mulU(totalQuoteLong).divU(totalQuoteShort)
                : premiumFraction.mulU(totalQuoteShort).divU(totalQuoteLong);
        } else if (totalQuoteLong > maxCPFBoost * totalQuoteShort) {
            delta = premiumFraction >= 0 ? premiumFraction.mulU(maxCPFBoost) : premiumFraction.divU(maxCPFBoost);
        } else if (totalQuoteShort > maxCPFBoost * totalQuoteLong) {
            delta = premiumFraction >= 0 ? premiumFraction.divU(maxCPFBoost) : premiumFraction.mulU(maxCPFBoost);
        } else {
            delta = premiumFraction;
        }

        newLatestCPF = delta.mulU(block.timestamp - lastUpdateCPF) + latestCPF;
    }

    //@notice withdrawable from fundingFee, unrealizedPnl and margin
    function _getWithdrawable(
        int256 quoteSize,
        int256 baseSize,
        uint256 tradeSize
    ) internal view returns (uint256 amount, int256 unrealizedPnl) {
        if (quoteSize == 0) {
            amount = baseSize <= 0 ? 0 : baseSize.abs();
        } else if (quoteSize < 0) {
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(baseToken),
                address(quoteToken),
                0,
                quoteSize.abs()
            );

            uint256 a = result[0] * 10000;
            uint256 b = (10000 - IConfig(config).initMarginRatio());
            //calculate how many base needed to maintain current position
            uint256 baseNeeded = a / b;
            if (a % b != 0) {
                baseNeeded += 1;
            }
            //borrowed - repay, earn when borrow more and repay less
            unrealizedPnl = int256(1).mulU(tradeSize).subU(result[0]);
            amount = baseSize.abs() <= baseNeeded ? 0 : baseSize.abs() - baseNeeded;
        } else {
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(quoteToken),
                address(baseToken),
                quoteSize.abs(),
                0
            );

            uint256 baseNeeded = (result[1] * (10000 - IConfig(config).initMarginRatio())) / 10000;
            //repay - lent, earn when lent less and repay more
            unrealizedPnl = int256(1).mulU(result[1]).subU(tradeSize);
            int256 remainBase = baseSize.addU(baseNeeded);
            amount = remainBase <= 0 ? 0 : remainBase.abs();
        }
    }

    function _calFundingFee(address trader, int256 _latestCPF) internal view returns (int256) {
        Position memory position = traderPositionMap[trader];

        int256 baseAmountFunding;
        if (position.quoteSize == 0) {
            baseAmountFunding = 0;
        } else {
            baseAmountFunding = position.quoteSize < 0
                ? int256(0).subU(_querySwapBaseWithAmm(true, position.quoteSize.abs()))
                : int256(0).addU(_querySwapBaseWithAmm(false, position.quoteSize.abs()));
        }

        return (baseAmountFunding * (_latestCPF - traderCPF[trader])).divU(1e18);
    }

    function _calDebtRatio(int256 quoteSize, int256 baseSize) internal view returns (uint256 debtRatio) {
        if (quoteSize == 0 || (quoteSize > 0 && baseSize >= 0)) {
            debtRatio = 0;
        } else if (quoteSize < 0 && baseSize <= 0) {
            debtRatio = 10000;
        } else if (quoteSize > 0) {
            uint256 quoteAmount = quoteSize.abs();
            //simulate to close short, markPriceAcc bigger, asset undervalue
            uint256 baseAmount = IPriceOracle(IConfig(config).priceOracle()).getMarkPriceAcc(
                amm,
                IConfig(config).beta(),
                quoteAmount,
                false
            );

            debtRatio = baseAmount == 0 ? 10000 : (baseSize.abs() * 10000) / baseAmount;
        } else {
            uint256 quoteAmount = quoteSize.abs();
            //simulate to close long, markPriceAcc smaller, debt overvalue
            uint256 baseAmount = IPriceOracle(IConfig(config).priceOracle()).getMarkPriceAcc(
                amm,
                IConfig(config).beta(),
                quoteAmount,
                true
            );

            debtRatio = (baseAmount * 10000) / baseSize.abs();
        }
    }

    function _getSwapParam(bool isCloseLongOrOpenShort, uint256 amount)
        internal
        view
        returns (
            address inputToken,
            address outputToken,
            uint256 inputAmount,
            uint256 outputAmount
        )
    {
        if (isCloseLongOrOpenShort) {
            outputToken = quoteToken;
            outputAmount = amount;
            inputToken = baseToken;
        } else {
            inputToken = quoteToken;
            inputAmount = amount;
            outputToken = baseToken;
        }
    }
}

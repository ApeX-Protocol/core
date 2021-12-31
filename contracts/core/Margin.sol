// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IMarginFactory.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IMargin.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IArbSys.sol";
import "../utils/Reentrant.sol";
import "../libraries/SignedMath.sol";

//@notice cpf means cumulative premium fraction
contract Margin is IMargin, IVault, Reentrant {
    using SignedMath for int256;

    address public immutable override factory;
    address public override config;
    address public override amm;
    address public override baseToken;
    address public override quoteToken;
    address public arbSys = address(100); //fixme use hardcode address(100)
    mapping(address => Position) public traderPositionMap; //all users' position
    mapping(address => int256) public traderCPF; //one trader's latest cpf, to calculate funding fee
    mapping(address => uint256) public traderLatestOperation; //to prevent flash loan attack
    uint256 public override reserve;
    uint256 public lastUpdateCPF; //last timestamp update cpf
    int256 public override netPosition; //base token
    uint256 internal totalQuoteLong;
    uint256 internal totalQuoteShort;
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
        //test case: 1. no transfer, add nonZero margin; 2. no transfer, add contractRemain margin
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
        //tocheck can remove this require?
        require(withdrawAmount > 0, "Margin.removeMargin: ZERO_WITHDRAW_AMOUNT");
        if (msg.sender != trader) {
            //tocheck if new router is harmful
            require(IConfig(config).routerMap(msg.sender), "Margin.removeMargin: FORBIDDEN");
        }
        int256 _latestCPF = updateCPF();

        //tocheck test carefully if withdraw margin more than withdrawable
        Position memory traderPosition = traderPositionMap[trader];

        int256 baseAmountFunding;
        if (traderPosition.quoteSize == 0) {
            baseAmountFunding = 0;
        } else {
            baseAmountFunding = traderPosition.quoteSize < 0
                ? int256(0).subU(_querySwapBaseWithAmm(true, traderPosition.quoteSize.abs()))
                : int256(0).addU(_querySwapBaseWithAmm(false, traderPosition.quoteSize.abs()));
        }

        //after last time operating trader's position, new fundingFee to earn.
        int256 fundingFee = (baseAmountFunding * (_latestCPF - traderCPF[trader])).divU(1e18);
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
        uint256 arbBlockNumber = IArbSys(arbSys).arbBlockNumber();
        require(traderLatestOperation[trader] != arbBlockNumber, "Margin.openPosition: ONE_BLOCK_TWICE_OPERATION");
        traderLatestOperation[trader] = arbBlockNumber;
        require(side == 0 || side == 1, "Margin.openPosition: INVALID_SIDE");
        require(quoteAmount > 0, "Margin.openPosition: ZERO_QUOTE_AMOUNT");
        if (msg.sender != trader) {
            require(IConfig(config).routerMap(msg.sender), "Margin.openPosition: FORBIDDEN");
        }
        int256 _latestCPF = updateCPF();

        Position memory traderPosition = traderPositionMap[trader];

        uint256 quoteSizeAbs = traderPosition.quoteSize.abs();
        int256 baseAmountFunding;
        if (traderPosition.quoteSize == 0) {
            baseAmountFunding = 0;
        } else {
            baseAmountFunding = traderPosition.quoteSize < 0
                ? int256(0).subU(_querySwapBaseWithAmm(true, quoteSizeAbs))
                : int256(0).addU(_querySwapBaseWithAmm(false, quoteSizeAbs));
        }

        int256 fundingFee = (baseAmountFunding * (_latestCPF - traderCPF[trader])).divU(1e18);

        uint256 quoteAmountMax;
        {
            int256 marginAcc;
            if (traderPosition.quoteSize == 0) {
                marginAcc = traderPosition.baseSize + fundingFee;
            } else if (traderPosition.quoteSize > 0) {
                //close short
                uint256[2] memory result = IAmm(amm).estimateSwap(
                    address(quoteToken),
                    address(baseToken),
                    traderPosition.quoteSize.abs(),
                    0
                );
                marginAcc = traderPosition.baseSize.addU(result[1]) + fundingFee;
            } else {
                //close long
                uint256[2] memory result = IAmm(amm).estimateSwap(
                    address(baseToken),
                    address(quoteToken),
                    0,
                    traderPosition.quoteSize.abs()
                );
                marginAcc = traderPosition.baseSize.subU(result[0]) + fundingFee;
            }
            require(marginAcc > 0, "Margin.openPosition: INVALID_MARGIN_ACC");
            (uint112 baseReserve, uint112 quoteReserve, ) = IAmm(amm).getReserves();
            quoteAmountMax =
                (quoteReserve * 10000 * marginAcc.abs()) /
                ((IConfig(config).initMarginRatio() * baseReserve) + (200 * marginAcc.abs() * IConfig(config).beta()));
        }

        bool isLong = side == 0;
        baseAmount = _addPositionWithAmm(isLong, quoteAmount);
        require(baseAmount > 0, "Margin.openPosition: TINY_QUOTE_AMOUNT");

        if (
            traderPosition.quoteSize == 0 ||
            (traderPosition.quoteSize < 0 == isLong) ||
            (traderPosition.quoteSize > 0 == !isLong)
        ) {
            //baseAmount is real base cost
            traderPosition.tradeSize = traderPosition.tradeSize + baseAmount;
        } else {
            //baseAmount is not real base cost, need to sub real base cost
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
            netPosition = netPosition.addU(baseAmount);
        } else {
            traderPosition.quoteSize = traderPosition.quoteSize.addU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount) + fundingFee;
            totalQuoteShort = totalQuoteShort + quoteAmount;
            netPosition = netPosition.subU(baseAmount);
        }
        require(traderPosition.quoteSize.abs() <= quoteAmountMax, "Margin.openPosition: INIT_MARGIN_RATIO");

        traderCPF[trader] = _latestCPF;
        traderPositionMap[trader] = traderPosition;
        emit OpenPosition(trader, side, baseAmount, quoteAmount, traderPosition);
    }

    function closePosition(address trader, uint256 quoteAmount)
        external
        override
        nonReentrant
        returns (uint256 baseAmount)
    {
        uint256 arbBlockNumber = IArbSys(arbSys).arbBlockNumber();
        require(traderLatestOperation[trader] != arbBlockNumber, "Margin.closePosition: ONE_BLOCK_TWICE_OPERATION");
        traderLatestOperation[trader] = arbBlockNumber;
        if (msg.sender != trader) {
            require(IConfig(config).routerMap(msg.sender), "Margin.closePosition: FORBIDDEN");
        }
        int256 _latestCPF = updateCPF();

        Position memory traderPosition = traderPositionMap[trader];
        require(quoteAmount != 0, "Margin.closePosition: ZERO_POSITION");
        uint256 quoteSizeAbs = traderPosition.quoteSize.abs();
        require(quoteAmount <= quoteSizeAbs, "Margin.closePosition: ABOVE_POSITION");

        bool isLong = traderPosition.quoteSize < 0;
        int256 baseAmountFunding = isLong
            ? int256(0).subU(_querySwapBaseWithAmm(true, quoteSizeAbs))
            : int256(0).addU(_querySwapBaseWithAmm(false, quoteSizeAbs));
        int256 fundingFee = (baseAmountFunding * (_latestCPF - traderCPF[trader])).divU(1e18);

        if (
            _calDebtRatio(traderPosition.quoteSize, traderPosition.baseSize + fundingFee) >=
            IConfig(config).liquidateThreshold()
        ) {
            //unhealthy position, liquidate self
            int256 remainBaseAmount;
            baseAmount = _querySwapBaseWithAmm(isLong, quoteSizeAbs);
            if (isLong) {
                totalQuoteLong = totalQuoteLong - quoteSizeAbs;
                netPosition = netPosition.subU(baseAmount);
                remainBaseAmount = traderPosition.baseSize.subU(baseAmount) + fundingFee;
                if (remainBaseAmount < 0) {
                    IAmm(amm).forceSwap(
                        address(baseToken),
                        address(quoteToken),
                        (traderPosition.baseSize + fundingFee).abs(),
                        quoteSizeAbs
                    );
                    traderPosition.quoteSize = 0;
                    traderPosition.baseSize = 0;
                    traderPosition.tradeSize = 0;
                }
            } else {
                totalQuoteShort = totalQuoteShort - quoteSizeAbs;
                netPosition = netPosition.addU(baseAmount);
                remainBaseAmount = traderPosition.baseSize.addU(baseAmount) + fundingFee;
                if (remainBaseAmount < 0) {
                    IAmm(amm).forceSwap(
                        address(quoteToken),
                        address(baseToken),
                        quoteSizeAbs,
                        (traderPosition.baseSize + fundingFee).abs()
                    );
                    traderPosition.quoteSize = 0;
                    traderPosition.baseSize = 0;
                    traderPosition.tradeSize = 0;
                }
            }
            if (remainBaseAmount >= 0) {
                _minusPositionWithAmm(isLong, quoteSizeAbs);
                traderPosition.quoteSize = 0;
                traderPosition.tradeSize = 0;
                traderPosition.baseSize = remainBaseAmount;
            }
        } else {
            //healthy position, close position safely
            baseAmount = _minusPositionWithAmm(isLong, quoteAmount);

            //when close position, keep quoteSize/tradeSize not change, cant sub baseAmount because baseAmount contains pnl
            traderPosition.tradeSize -= (quoteAmount * traderPosition.tradeSize) / quoteSizeAbs;

            if (isLong) {
                totalQuoteLong = totalQuoteLong - quoteAmount;
                netPosition = netPosition.subU(baseAmount);
                traderPosition.quoteSize = traderPosition.quoteSize.addU(quoteAmount);
                traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount) + fundingFee;
            } else {
                totalQuoteShort = totalQuoteShort - quoteAmount;
                netPosition = netPosition.addU(baseAmount);
                traderPosition.quoteSize = traderPosition.quoteSize.subU(quoteAmount);
                traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount) + fundingFee;
            }
        }

        traderCPF[trader] = _latestCPF;
        traderPositionMap[trader] = traderPosition;

        emit ClosePosition(trader, quoteAmount, baseAmount, fundingFee, traderPosition);
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
        require(
            traderLatestOperation[msg.sender] != IArbSys(arbSys).arbBlockNumber(),
            "Margin.liquidate: ONE_BLOCK_TWICE_OPERATION"
        );

        int256 _latestCPF = updateCPF();
        Position memory traderPosition = traderPositionMap[trader];
        int256 quoteSize = traderPosition.quoteSize;
        require(quoteSize != 0, "Margin.liquidate: ZERO_POSITION");

        quoteAmount = quoteSize.abs();
        bool isLong = quoteSize < 0;
        int256 baseAmountFunding = isLong
            ? int256(0).subU(_querySwapBaseWithAmm(true, quoteAmount))
            : int256(0).addU(_querySwapBaseWithAmm(false, quoteAmount));

        int256 fundingFee = (baseAmountFunding * (_latestCPF - traderCPF[trader])).divU(1e18);
        require(
            _calDebtRatio(quoteSize, traderPosition.baseSize + fundingFee) >= IConfig(config).liquidateThreshold(),
            "Margin.liquidate: NOT_LIQUIDATABLE"
        );

        baseAmount = _querySwapBaseWithAmm(isLong, quoteAmount);
        //calc remain base after liquidate
        int256 remainBaseAmountAfterLiquidate = isLong
            ? traderPosition.baseSize.subU(baseAmount) + fundingFee
            : traderPosition.baseSize.addU(baseAmount) + fundingFee;

        if (remainBaseAmountAfterLiquidate > 0) {
            //calc liquidate reward
            bonus = (remainBaseAmountAfterLiquidate.abs() * IConfig(config).liquidateFeeRatio()) / 10000;
        }

        if (isLong) {
            totalQuoteLong = totalQuoteLong - quoteAmount;
            netPosition = netPosition.subU(baseAmount);
            IAmm(amm).forceSwap(
                address(baseToken),
                address(quoteToken),
                (traderPosition.baseSize.subU(bonus) + fundingFee).abs(),
                quoteAmount
            );
        } else {
            totalQuoteShort = totalQuoteShort - quoteAmount;
            netPosition = netPosition.addU(baseAmount);
            IAmm(amm).forceSwap(
                address(quoteToken),
                address(baseToken),
                quoteAmount,
                (traderPosition.baseSize.subU(bonus) + fundingFee).abs()
            );
        }

        traderCPF[trader] = _latestCPF;
        if (bonus > 0) {
            _withdraw(trader, msg.sender, bonus);
        }

        delete traderPositionMap[trader];

        emit Liquidate(msg.sender, trader, quoteAmount, baseAmount, bonus, traderPosition);
    }

    function deposit(address user, uint256 amount) external override nonReentrant {
        require(msg.sender == amm, "Margin.deposit: REQUIRE_AMM");
        require(amount > 0, "Margin.deposit: AMOUNT_IS_ZERO");
        uint256 balance = IERC20(baseToken).balanceOf(address(this));
        //tocheck if balance contains protocol profit?
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
        //tocheck can remove this following two require?
        require(amount > 0, "Margin._withdraw: AMOUNT_IS_ZERO");
        require(amount <= reserve, "Margin._withdraw: NOT_ENOUGH_RESERVE");
        reserve = reserve - amount;
        IERC20(baseToken).transfer(receiver, amount);

        emit Withdraw(user, receiver, amount);
    }

    //swap exact quote to base
    function _addPositionWithAmm(bool isLong, uint256 quoteAmount) internal returns (uint256 baseAmount) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            !isLong,
            quoteAmount
        );

        uint256[2] memory result = IAmm(amm).swap(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[1] : result[0];
    }

    //close position, swap base to get exact quoteAmount, the base has contained pnl
    function _minusPositionWithAmm(bool isLong, uint256 quoteAmount) internal returns (uint256 baseAmount) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            quoteAmount
        );

        uint256[2] memory result = IAmm(amm).swap(inputToken, outputToken, inputAmount, outputAmount);
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

        int256 baseAmountFunding;
        if (position.quoteSize == 0) {
            baseAmountFunding = 0;
        } else {
            baseAmountFunding = position.quoteSize < 0
                ? int256(0).subU(_querySwapBaseWithAmm(true, position.quoteSize.abs()))
                : int256(0).addU(_querySwapBaseWithAmm(false, position.quoteSize.abs()));
        }

        (withdrawable, ) = _getWithdrawable(
            position.quoteSize,
            position.baseSize + (baseAmountFunding * (_getNewLatestCPF() - traderCPF[trader])).divU(1e18),
            position.tradeSize
        );
    }

    function getNewLatestCPF() external view override returns (int256) {
        return _getNewLatestCPF();
    }

    function canLiquidate(address trader) external view override returns (bool) {
        Position memory position = traderPositionMap[trader];

        int256 baseAmountFunding;
        if (position.quoteSize == 0) {
            baseAmountFunding = 0;
        } else {
            baseAmountFunding = position.quoteSize < 0
                ? int256(0).subU(_querySwapBaseWithAmm(true, position.quoteSize.abs()))
                : int256(0).addU(_querySwapBaseWithAmm(false, position.quoteSize.abs()));
        }

        return
            _calDebtRatio(
                position.quoteSize,
                position.baseSize + (baseAmountFunding * (_getNewLatestCPF() - traderCPF[trader])).divU(1e18)
            ) >= IConfig(config).liquidateThreshold();
    }

    function calFundingFee(address trader) external view override returns (int256) {
        Position memory position = traderPositionMap[trader];

        int256 baseAmountFunding;
        if (position.quoteSize == 0) {
            baseAmountFunding = 0;
        } else {
            baseAmountFunding = position.quoteSize < 0
                ? int256(0).subU(_querySwapBaseWithAmm(true, position.quoteSize.abs()))
                : int256(0).addU(_querySwapBaseWithAmm(false, position.quoteSize.abs()));
        }

        return (baseAmountFunding * (_getNewLatestCPF() - traderCPF[trader])).divU(1e18);
    }

    function calDebtRatio(address trader) external view override returns (uint256 debtRatio) {
        Position memory position = traderPositionMap[trader];

        int256 baseAmountFunding;
        if (position.quoteSize == 0) {
            baseAmountFunding = 0;
        } else {
            baseAmountFunding = position.quoteSize < 0
                ? int256(0).subU(_querySwapBaseWithAmm(true, position.quoteSize.abs()))
                : int256(0).addU(_querySwapBaseWithAmm(false, position.quoteSize.abs()));
        }

        return
            _calDebtRatio(
                position.quoteSize,
                position.baseSize + (baseAmountFunding * (_getNewLatestCPF() - traderCPF[trader])).divU(1e18)
            );
    }

    function calUnrealizedPnl(address trader) external view override returns (int256 unrealizedPnl) {
        Position memory position = traderPositionMap[trader];
        if (position.quoteSize < 0) {
            //borrowed - repay, earn when borrow more and repay less
            unrealizedPnl = int256(1).mulU(position.tradeSize).subU(
                _querySwapBaseWithAmm(true, position.quoteSize.abs())
            );
        } else if (position.quoteSize > 0) {
            //repay - lent, earn when lent less and repay more
            unrealizedPnl = int256(1).mulU(_querySwapBaseWithAmm(false, position.quoteSize.abs())).subU(
                position.tradeSize
            );
        }
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
        //premiumFraction is (markPrice - indexPrice) * 1e18 / 8h / indexPrice
        int256 premiumFraction = IPriceOracle(IConfig(config).priceOracle()).getPremiumFraction(amm);
        uint256 maxCPFBoost = IConfig(config).maxCPFBoost();
        int256 delta;
        //todo change amplifier to configurable
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
            //tocheck need to consider this case
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

    //debt*10000/asset
    //tocheck if no repair the MarkPriceAcc equation, have chance to liquidate a little bit late when debtRatio triggered
    function _calDebtRatio(int256 quoteSize, int256 baseSize) internal view returns (uint256 debtRatio) {
        if (quoteSize == 0 || (quoteSize > 0 && baseSize >= 0)) {
            debtRatio = 0;
        } else if (quoteSize < 0 && baseSize <= 0) {
            debtRatio = 10000;
        } else if (quoteSize > 0) {
            uint256 quoteAmount = quoteSize.abs();
            //close short, markPriceAcc bigger, asset undervalue
            uint256 baseAmount = IPriceOracle(IConfig(config).priceOracle()).getMarkPriceAcc(
                amm,
                IConfig(config).beta(),
                quoteAmount,
                false
            );

            //tocheck debtRatio range?
            debtRatio = baseAmount == 0 ? 10000 : (baseSize.abs() * 10000) / baseAmount;
        } else {
            uint256 quoteAmount = quoteSize.abs();
            //close long, markPriceAcc smaller, debt overvalue
            uint256 baseAmount = IPriceOracle(IConfig(config).priceOracle()).getMarkPriceAcc(
                amm,
                IConfig(config).beta(),
                quoteAmount,
                true
            );

            uint256 ratio = (baseAmount * 10000) / baseSize.abs();
            //tocheck debtRatio range?
            debtRatio = 10000 < ratio ? 10000 : ratio;
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

    //just for dev use
    function queryMaxOpenPosition(address trader)
        external
        view
        returns (
            int256 baseAmountFunding,
            int256 fundingFee,
            int256 marginAcc,
            uint112 baseReserve,
            uint112 quoteReserve,
            uint256 quoteAmountMax
        )
    {
        int256 _latestCPF = _getNewLatestCPF();

        Position memory traderPosition = traderPositionMap[trader];

        uint256 quoteSizeAbs = traderPosition.quoteSize.abs();

        if (traderPosition.quoteSize == 0) {
            baseAmountFunding = 0;
        } else {
            baseAmountFunding = traderPosition.quoteSize < 0
                ? int256(0).subU(_querySwapBaseWithAmm(true, quoteSizeAbs))
                : int256(0).addU(_querySwapBaseWithAmm(false, quoteSizeAbs));
        }

        fundingFee = (baseAmountFunding * (_latestCPF - traderCPF[trader])).divU(1e18);

        if (traderPosition.quoteSize == 0) {
            marginAcc = traderPosition.baseSize + fundingFee;
        } else if (traderPosition.quoteSize > 0) {
            //close short
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(quoteToken),
                address(baseToken),
                traderPosition.quoteSize.abs(),
                0
            );
            marginAcc = traderPosition.baseSize.addU(result[1]) + fundingFee;
        } else {
            //close long
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(baseToken),
                address(quoteToken),
                0,
                traderPosition.quoteSize.abs()
            );
            marginAcc = traderPosition.baseSize.subU(result[0]) + fundingFee;
        }
        require(marginAcc > 0, "Margin.openPosition: INVALID_MARGIN_ACC");
        (baseReserve, quoteReserve, ) = IAmm(amm).getReserves();
        quoteAmountMax =
            (quoteReserve * 10000 * marginAcc.abs()) /
            ((IConfig(config).initMarginRatio() * baseReserve) + (200 * marginAcc.abs() * IConfig(config).beta()));
    }

    //just for dev use
    function calDebtRatio(int256 quoteSize, int256 baseSize)
        external
        view
        returns (uint256 baseAmount, uint256 debtRatio)
    {
        if (quoteSize == 0 || (quoteSize > 0 && baseSize >= 0)) {
            debtRatio = 0;
        } else if (quoteSize < 0 && baseSize <= 0) {
            debtRatio = 10000;
        } else if (quoteSize > 0) {
            uint256 quoteAmount = quoteSize.abs();
            //close short, markPriceAcc bigger, asset undervalue
            baseAmount = IPriceOracle(IConfig(config).priceOracle()).getMarkPriceAcc(
                amm,
                IConfig(config).beta(),
                quoteAmount,
                false
            );

            //tocheck debtRatio range?
            debtRatio = baseAmount == 0 ? 10000 : (baseSize.abs() * 10000) / baseAmount;
        } else {
            uint256 quoteAmount = quoteSize.abs();
            //close long, markPriceAcc smaller, debt overvalue
            baseAmount = IPriceOracle(IConfig(config).priceOracle()).getMarkPriceAcc(
                amm,
                IConfig(config).beta(),
                quoteAmount,
                true
            );

            uint256 ratio = (baseAmount * 10000) / baseSize.abs();
            //tocheck debtRatio range?
            debtRatio = 10000 < ratio ? 10000 : ratio;
        }
    }

    //just for dev use
    function queryWithdrawable(
        int256 quoteSize,
        int256 baseSize,
        uint256 tradeSize
    )
        external
        view
        returns (
            uint256 resultBase,
            uint256 baseNeeded,
            uint256 amount,
            int256 unrealizedPnl
        )
    {
        if (quoteSize == 0) {
            amount = baseSize <= 0 ? 0 : baseSize.abs();
        } else if (quoteSize < 0) {
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(baseToken),
                address(quoteToken),
                0,
                quoteSize.abs()
            );

            resultBase = result[0];
            uint256 a = result[0] * 10000;
            uint256 b = (10000 - IConfig(config).initMarginRatio());
            //calculate how many base needed to maintain current position
            baseNeeded = a / b;
            //tocheck need to consider this case
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
            resultBase = result[1];
            baseNeeded = (result[1] * (10000 - IConfig(config).initMarginRatio())) / 10000;
            //repay - lent, earn when lent less and repay more
            unrealizedPnl = int256(1).mulU(result[1]).subU(tradeSize);
            int256 remainBase = baseSize.addU(baseNeeded);
            amount = remainBase <= 0 ? 0 : remainBase.abs();
        }
    }

    //just for dev use
    function setArbSys(address _arbSys) external {
        arbSys = _arbSys;
    }
}

// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IMarginFactory.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IMargin.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IPriceOracle.sol";
import "../utils/Reentrant.sol";
import "../libraries/SignedMath.sol";

//@notice take price=1 in the following example
contract Margin is IMargin, IVault, Reentrant {
    using SignedMath for int256;

    struct Position {
        int256 quoteSize;
        int256 baseSize;
        uint256 tradeSize;
    }

    uint256 constant MAXRATIO = 10000;
    uint256 constant fundingRatePrecision = 1e18;
    //fixme move to config.sol
    uint256 constant maxCPFBoost = 10;

    address public immutable override factory;
    address public override config;
    address public override amm;
    address public override baseToken;
    address public override quoteToken;
    mapping(address => Position) public traderPositionMap;
    mapping(address => int256) public traderCPF; //one trader's latest cpf
    uint256 public override reserve;
    uint256 public lastUpdateCPF; //last timestamp update cumulative premium fraction
    uint256 internal totalQuoteLong;
    uint256 internal totalQuoteShort;
    int256 internal latestCPF; //latestCPF with fundingRatePrecision multiplied

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
        require(depositAmount <= balance - reserve, "Margin.addMargin;: WRONG_DEPOSIT_AMOUNT");
        Position storage traderPosition = traderPositionMap[trader];
        traderPosition.baseSize = traderPosition.baseSize.addU(depositAmount);
        reserve = reserve + depositAmount;

        emit AddMargin(trader, depositAmount);
    }

    function removeMargin(address trader, uint256 withdrawAmount) external override nonReentrant {
        require(withdrawAmount > 0, "Margin.removeMargin: ZERO_WITHDRAW_AMOUNT");
        if (msg.sender != trader) {
            require(IConfig(config).routerMap(msg.sender), "Margin.removeMargin: FORBIDDEN");
        }
        int256 _latestCPF = updateCPF();

        //tocheck test carefully if withdraw margin more than withdrawable
        Position memory traderPosition = traderPositionMap[trader];
        int256 fundingFee = _calFundingFee(traderPosition.quoteSize, _latestCPF - traderCPF[trader]);
        require(
            withdrawAmount <= _getWithdrawable(traderPosition.quoteSize, traderPosition.baseSize + fundingFee),
            "Margin.removeMargin: NOT_ENOUGH_WITHDRAWABLE"
        );

        traderPosition.baseSize = traderPosition.baseSize.subU(withdrawAmount) + fundingFee;
        //tocheck need check marginRatio?
        require(
            _calMarginRatio(traderPosition.quoteSize, traderPosition.baseSize) >= IConfig(config).initMarginRatio(),
            "initMarginRatio"
        );

        traderPositionMap[trader] = traderPosition;
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
            require(IConfig(config).routerMap(msg.sender), "Margin.openPosition: FORBIDDEN");
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

        int256 fundingFee = _calFundingFee(traderPosition.quoteSize, _latestCPF - traderCPF[trader]);
        if (isLong) {
            traderPosition.quoteSize = traderPosition.quoteSize.subU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount) + fundingFee;
            totalQuoteLong += quoteAmount;
        } else {
            traderPosition.quoteSize = traderPosition.quoteSize.addU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount) + fundingFee;
            totalQuoteShort += quoteAmount;
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

        //tocheck 是否有必要做这个检查？
        require(
            _calMarginRatio(traderPosition.quoteSize, traderPosition.baseSize) >= IConfig(config).initMarginRatio(),
            "Margin.openPosition: INIT_MARGIN_RATIO"
        );
        traderCPF[trader] = _latestCPF;
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

        bool isLong = traderPosition.quoteSize < 0;
        int256 fundingFee = _calFundingFee(traderPosition.quoteSize, _latestCPF - traderCPF[trader]);
        uint256 quoteSize = traderPosition.quoteSize.abs();
        // todo test carefully
        //liquidate self when arrive at the threshold
        if (
            _calDebtRatio(traderPosition.quoteSize, traderPosition.baseSize + fundingFee) >=
            IConfig(config).liquidateThreshold()
        ) {
            baseAmount = _querySwapBaseWithAmm(isLong, quoteSize);
            if (isLong) {
                totalQuoteLong -= quoteSize;
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
                        (traderPosition.baseSize + fundingFee).abs(),
                        quoteSize
                    );
                    traderPosition.quoteSize = 0;
                    traderPosition.baseSize = 0;
                    traderPosition.tradeSize = 0;
                }
            } else {
                totalQuoteShort -= quoteSize;
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
                        quoteSize,
                        (traderPosition.baseSize + fundingFee).abs()
                    );
                    traderPosition.quoteSize = 0;
                    traderPosition.baseSize = 0;
                    traderPosition.tradeSize = 0;
                }
            }
        } else {
            baseAmount = _minusPositionWithAmm(isLong, quoteAmount);
            //close example
            //long old: quote -10, base 11; close position: quote 5, base -5; new: quote -5, base 6
            //short old: quote 10, base -9; close position: quote -5, base +5; new: quote 5, base -4
            if (isLong) {
                totalQuoteLong -= quoteAmount;
                traderPosition.quoteSize = traderPosition.quoteSize.addU(quoteAmount);
                traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount) + fundingFee;
            } else {
                totalQuoteShort -= quoteAmount;
                traderPosition.quoteSize = traderPosition.quoteSize.subU(quoteAmount);
                traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount) + fundingFee;
            }

            if (traderPosition.quoteSize != 0) {
                require(traderPosition.tradeSize >= baseAmount, "Margin.closePosition: NOT_CLOSABLE");
                traderPosition.tradeSize = traderPosition.tradeSize - baseAmount;
                require(
                    _calMarginRatio(traderPosition.quoteSize, traderPosition.baseSize) >=
                        IConfig(config).initMarginRatio(),
                    "initMarginRatio"
                );
            } else {
                traderPosition.tradeSize = 0;
            }
        }

        traderCPF[trader] = _latestCPF;
        traderPositionMap[trader] = traderPosition;

        emit ClosePosition(trader, quoteAmount, baseAmount, quoteSize, isLong);
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
        int256 fundingFee = _calFundingFee(quoteSize, _latestCPF - traderCPF[trader]);
        require(quoteSize != 0, "Margin.liquidate: ZERO_POSITION");
        require(
            _calDebtRatio(quoteSize, traderPosition.baseSize + fundingFee) >= IConfig(config).liquidateThreshold(),
            "Margin.liquidate: NOT_LIQUIDATABLE"
        );

        bool isLong = quoteSize < 0;

        quoteAmount = quoteSize.abs();
        baseAmount = _querySwapBaseWithAmm(isLong, quoteAmount);
        //calc remain base after liquidate
        int256 remainBaseAmountAfterLiquidate = isLong
            ? traderPosition.baseSize.subU(baseAmount) + fundingFee
            : traderPosition.baseSize.addU(baseAmount) + fundingFee;

        if (remainBaseAmountAfterLiquidate > 0) {
            //calc liquidate reward
            bonus = (remainBaseAmountAfterLiquidate.abs() * IConfig(config).liquidateFeeRatio()) / MAXRATIO;
        }

        if (isLong) {
            totalQuoteLong -= quoteAmount;
            IAmm(amm).forceSwap(
                address(baseToken),
                address(quoteToken),
                (traderPosition.baseSize.subU(bonus) + fundingFee).abs(),
                quoteAmount
            );
        } else {
            totalQuoteShort -= quoteAmount;
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
            address(quoteToken),
            address(baseToken)
        );

        uint256[2] memory result = IAmm(amm).swap(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[1] : result[0];
    }

    function _minusPositionWithAmm(bool isLong, uint256 quoteAmount) internal returns (uint256) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            quoteAmount,
            address(quoteToken),
            address(baseToken)
        );

        uint256[2] memory result = IAmm(amm).swap(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[0] : result[1];
    }

    //update global funding fee
    function updateCPF() public returns (int256 newLatestCPF) {
        uint256 currentTimeStamp = block.timestamp;
        newLatestCPF = _getNewLatestCPF();

        latestCPF = newLatestCPF;
        lastUpdateCPF = currentTimeStamp;

        emit UpdateCPF(currentTimeStamp, newLatestCPF);
    }

    function querySwapBaseWithAmm(bool isLong, uint256 quoteAmount) external view returns (uint256) {
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

    function getWithdrawable(address trader) external view override returns (uint256) {
        Position memory position = traderPositionMap[trader];

        return
            _getWithdrawable(
                position.quoteSize,
                position.baseSize + _calFundingFee(position.quoteSize, _getNewLatestCPF() - traderCPF[trader])
            );
    }

    function getMarginRatio(address trader) external view returns (uint256) {
        Position memory position = traderPositionMap[trader];

        return
            _calMarginRatio(
                position.quoteSize,
                position.baseSize + _calFundingFee(position.quoteSize, _getNewLatestCPF() - traderCPF[trader])
            );
    }

    function canLiquidate(address trader) external view override returns (bool) {
        Position memory position = traderPositionMap[trader];

        return
            _calDebtRatio(
                position.quoteSize,
                position.baseSize + _calFundingFee(position.quoteSize, _getNewLatestCPF() - traderCPF[trader])
            ) >= IConfig(config).liquidateThreshold();
    }

    function calFundingFee(address trader) external view override returns (int256) {
        Position memory position = traderPositionMap[trader];
        return _calFundingFee(position.quoteSize, _getNewLatestCPF() - traderCPF[trader]);
    }

    function calDebtRatio(
        address trader,
        int256 quoteSize,
        int256 baseSize
    ) external view override returns (uint256 debtRatio) {
        int256 fundingFee = _calFundingFee(quoteSize, _getNewLatestCPF() - traderCPF[trader]);
        return _calDebtRatio(quoteSize, baseSize + fundingFee);
    }

    //query swap exact quote to base
    function _querySwapBaseWithAmm(bool isLong, uint256 quoteAmount) internal view returns (uint256) {
        (address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount) = _getSwapParam(
            isLong,
            quoteAmount,
            address(quoteToken),
            address(baseToken)
        );

        uint256[2] memory result = IAmm(amm).estimateSwap(inputToken, outputToken, inputAmount, outputAmount);
        return isLong ? result[0] : result[1];
    }

    //returns newLatestCPF with fundingRatePrecision multiplied
    function _getNewLatestCPF() internal view returns (int256 newLatestCPF) {
        //premiumFraction is (markPrice - indexPrice) * fundingRatePrecision / 8h / indexPrice
        int256 premiumFraction = IPriceOracle(IConfig(config).priceOracle()).getPremiumFraction(amm);
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

    //calculate how much fundingFee can earn with quoteSize
    function _calFundingFee(int256 quoteSize, int256 diff) internal view returns (int256) {
        if (quoteSize == 0 || diff == 0) {
            return 0;
        }

        //tocheck if need to trans quoteSize to base
        uint256[2] memory result;
        //long
        if (quoteSize < 0) {
            result = IAmm(amm).estimateSwap(address(baseToken), address(quoteToken), 0, quoteSize.abs());
            //long pay short when diff > 0
            return -1 * diff.mulU(result[0]).divU(fundingRatePrecision);
        }
        //short
        result = IAmm(amm).estimateSwap(address(quoteToken), address(baseToken), quoteSize.abs(), 0);
        //short earn when diff > 0
        return diff.mulU(result[1]).divU(fundingRatePrecision);
    }

    //@notice withdrawable from margin, unrealizedPnl and fundingFee
    function _getWithdrawable(int256 quoteSize, int256 baseSize) internal view returns (uint256 amount) {
        if (quoteSize == 0) {
            amount = baseSize <= 0 ? 0 : baseSize.abs();
        } else if (quoteSize < 0) {
            //long example: quoteSize -10, baseSize 11
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(baseToken),
                address(quoteToken),
                0,
                quoteSize.abs()
            );

            uint256 a = result[0] * MAXRATIO;
            uint256 b = (MAXRATIO - IConfig(config).initMarginRatio());
            uint256 baseNeeded = a / b;
            //need to consider this case
            if (a % b != 0) {
                baseNeeded += 1;
            }

            amount = baseSize.abs() <= baseNeeded ? 0 : baseSize.abs() - baseNeeded;
        } else {
            //short example: quoteSize 10, baseSize -9
            uint256[2] memory result = IAmm(amm).estimateSwap(
                address(quoteToken),
                address(baseToken),
                quoteSize.abs(),
                0
            );

            uint256 baseNeeded = (result[1] * (MAXRATIO - IConfig(config).initMarginRatio())) / (MAXRATIO);

            amount = baseSize.addU(baseNeeded) <= 0 ? 0 : (baseSize.addU(baseNeeded)).abs();
        }
    }

    function _calDebtRatio(int256 quoteSize, int256 baseSize) internal view returns (uint256 debtRatio) {
        if (quoteSize == 0 || (quoteSize > 0 && baseSize >= 0)) {
            debtRatio = 0;
        } else if (quoteSize < 0 && baseSize <= 0) {
            debtRatio = MAXRATIO;
        } else if (quoteSize > 0) {
            uint256 quoteAmount = quoteSize.abs();
            //calculate asset
            uint256 price = IPriceOracle(IConfig(config).priceOracle()).getMarkPriceAcc(
                amm,
                IConfig(config).beta(),
                quoteAmount,
                false
            );
            uint256 baseAmount = quoteAmount / price;
            //baseSize must be negative
            debtRatio = baseAmount == 0 ? MAXRATIO : (baseSize.abs() * MAXRATIO) / baseAmount;
        } else {
            uint256 quoteAmount = quoteSize.abs();
            //calculate debt
            uint256 price = IPriceOracle(IConfig(config).priceOracle()).getMarkPriceAcc(
                amm,
                IConfig(config).beta(),
                quoteAmount,
                true
            );

            uint256 baseAmount = quoteAmount / price;
            uint256 ratio = (baseAmount * MAXRATIO) / baseSize.abs();
            debtRatio = MAXRATIO < ratio ? MAXRATIO : ratio;
        }
    }

    function _calMarginRatio(int256 quoteSize, int256 baseSize) internal view returns (uint256 marginRatio) {
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
        address token,
        address anotherToken
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
            inputToken = anotherToken;
        } else {
            inputToken = token;
            inputAmount = amount;
            outputToken = anotherToken;
        }
    }
}

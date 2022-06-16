// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/IAmmFactory.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IPairFactory.sol";
import "../interfaces/IAmm.sol";
import "../interfaces/IMargin.sol";
import "../interfaces/ILiquidityERC20.sol";
import "../interfaces/IConfig.sol";
import "../interfaces/IWETH.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/SignedMath.sol";
import "../libraries/ChainAdapter.sol";
import "../utils/Initializable.sol";

contract Router is IRouter, Initializable {
    using SignedMath for int256;

    address public override config;
    address public override pairFactory;
    address public override pcvTreasury;
    address public override WETH;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        _;
    }

    modifier onlyEOA() {
        require(tx.origin == msg.sender, "Router: ONLY_EOA");
        _;
    }

    modifier notEmergency() {
        bool inEmergency = IConfig(config).inEmergency(address(this));
        require(inEmergency == false, "Router: IN_EMERGENCY");
        _;
    }

    function initialize(
        address config_,
        address pairFactory_,
        address pcvTreasury_,
        address _WETH
    ) external initializer {
        config = config_;
        pairFactory = pairFactory_;
        pcvTreasury = pcvTreasury_;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function addLiquidity(
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 quoteAmountMin,
        uint256 deadline,
        bool pcv
    ) external override ensure(deadline) notEmergency onlyEOA returns (uint256 quoteAmount, uint256 liquidity) {
        address amm = IPairFactory(pairFactory).getAmm(baseToken, quoteToken);
        if (amm == address(0)) {
            (amm, ) = IPairFactory(pairFactory).createPair(baseToken, quoteToken);
        }
        TransferHelper.safeTransferFrom(baseToken, msg.sender, amm, baseAmount);
        if (pcv) {
            (, quoteAmount, liquidity) = IAmm(amm).mint(address(this));
            TransferHelper.safeTransfer(amm, pcvTreasury, liquidity);
        } else {
            (, quoteAmount, liquidity) = IAmm(amm).mint(msg.sender);
        }
        require(quoteAmount >= quoteAmountMin, "Router.addLiquidity: INSUFFICIENT_QUOTE_AMOUNT");
    }

    function addLiquidityETH(
        address quoteToken,
        uint256 quoteAmountMin,
        uint256 deadline,
        bool pcv
    )
        external
        payable
        override
        ensure(deadline)
        notEmergency
        onlyEOA
        returns (
            uint256 ethAmount,
            uint256 quoteAmount,
            uint256 liquidity
        )
    {
        address amm = IPairFactory(pairFactory).getAmm(WETH, quoteToken);
        if (amm == address(0)) {
            (amm, ) = IPairFactory(pairFactory).createPair(WETH, quoteToken);
        }
        ethAmount = msg.value;
        IWETH(WETH).deposit{value: ethAmount}();
        assert(IWETH(WETH).transfer(amm, ethAmount));
        if (pcv) {
            (, quoteAmount, liquidity) = IAmm(amm).mint(address(this));
            TransferHelper.safeTransfer(amm, pcvTreasury, liquidity);
        } else {
            (, quoteAmount, liquidity) = IAmm(amm).mint(msg.sender);
        }
        require(quoteAmount >= quoteAmountMin, "Router.addLiquidityETH: INSUFFICIENT_QUOTE_AMOUNT");
    }

    function removeLiquidity(
        address baseToken,
        address quoteToken,
        uint256 liquidity,
        uint256 baseAmountMin,
        uint256 deadline
    ) external override ensure(deadline) notEmergency onlyEOA returns (uint256 baseAmount, uint256 quoteAmount) {
        address amm = IPairFactory(pairFactory).getAmm(baseToken, quoteToken);
        TransferHelper.safeTransferFrom(amm, msg.sender, amm, liquidity);
        (baseAmount, quoteAmount, ) = IAmm(amm).burn(msg.sender);
        require(baseAmount >= baseAmountMin, "Router.removeLiquidity: INSUFFICIENT_BASE_AMOUNT");
    }

    function removeLiquidityETH(
        address quoteToken,
        uint256 liquidity,
        uint256 ethAmountMin,
        uint256 deadline
    ) external override ensure(deadline) notEmergency onlyEOA returns (uint256 ethAmount, uint256 quoteAmount) {
        address amm = IPairFactory(pairFactory).getAmm(WETH, quoteToken);
        TransferHelper.safeTransferFrom(amm, msg.sender, amm, liquidity);
        (ethAmount, quoteAmount, ) = IAmm(amm).burn(address(this));
        require(ethAmount >= ethAmountMin, "Router.removeLiquidityETH: INSUFFICIENT_ETH_AMOUNT");
        IWETH(WETH).withdraw(ethAmount);
        TransferHelper.safeTransferETH(msg.sender, ethAmount);
    }

    function deposit(
        address baseToken,
        address quoteToken,
        address holder,
        uint256 amount
    ) external override notEmergency {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router.deposit: NOT_FOUND_MARGIN");
        TransferHelper.safeTransferFrom(baseToken, msg.sender, margin, amount);
        IMargin(margin).addMargin(holder, amount);
    }

    function depositETH(address quoteToken, address holder) external payable override notEmergency {
        address margin = IPairFactory(pairFactory).getMargin(WETH, quoteToken);
        require(margin != address(0), "Router.depositETH: NOT_FOUND_MARGIN");
        uint256 amount = msg.value;
        IWETH(WETH).deposit{value: amount}();
        assert(IWETH(WETH).transfer(margin, amount));
        IMargin(margin).addMargin(holder, amount);
    }

    function withdraw(
        address baseToken,
        address quoteToken,
        uint256 amount
    ) external override {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router.withdraw: NOT_FOUND_MARGIN");
        (uint256 withdrawable, ) = _getWithdrawable(baseToken, quoteToken, msg.sender);
        require(amount <= withdrawable, "Router.withdraw: NOT_ENOUGH_WITHDRAWABLE");
        IMargin(margin).removeMargin(msg.sender, msg.sender, amount);
        uint256 debtRatio = IMargin(margin).calDebtRatio(msg.sender);
        require(debtRatio < 10000, "Router.withdraw: DEBT_RATIO_OVER");
    }

    function withdrawETH(address quoteToken, uint256 amount) external override {
        address margin = IPairFactory(pairFactory).getMargin(WETH, quoteToken);
        require(margin != address(0), "Router.withdrawETH: NOT_FOUND_MARGIN");
        (uint256 withdrawable, ) = _getWithdrawable(WETH, quoteToken, msg.sender);
        require(amount <= withdrawable, "Router.withdrawETH: NOT_ENOUGH_WITHDRAWABLE");
        IMargin(margin).removeMargin(msg.sender, address(this), amount);
        IWETH(WETH).withdraw(amount);
        TransferHelper.safeTransferETH(msg.sender, amount);
        uint256 debtRatio = IMargin(margin).calDebtRatio(msg.sender);
        require(debtRatio < 10000, "Router.withdrawETH: DEBT_RATIO_OVER");
    }

    function openPositionWithWallet(
        address baseToken,
        address quoteToken,
        uint8 side,
        uint256 marginAmount,
        uint256 quoteAmount,
        uint256 baseAmountLimit,
        uint256 deadline
    ) external override ensure(deadline) notEmergency onlyEOA returns (uint256 baseAmount) {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router.openPositionWithWallet: NOT_FOUND_MARGIN");
        require(side == 0 || side == 1, "Router.openPositionWithWallet: INSUFFICIENT_SIDE");
        TransferHelper.safeTransferFrom(baseToken, msg.sender, margin, marginAmount);
        IMargin(margin).addMargin(msg.sender, marginAmount);
        baseAmount = IMargin(margin).openPosition(msg.sender, side, quoteAmount);
        if (side == 0) {
            require(baseAmount >= baseAmountLimit, "Router.openPositionWithWallet: INSUFFICIENT_QUOTE_AMOUNT");
            _collectFee(baseAmount, margin);
        } else {
            require(baseAmount <= baseAmountLimit, "Router.openPositionWithWallet: INSUFFICIENT_QUOTE_AMOUNT");
        }
    }

    function openPositionETHWithWallet(
        address quoteToken,
        uint8 side,
        uint256 quoteAmount,
        uint256 baseAmountLimit,
        uint256 deadline
    ) external payable override ensure(deadline) notEmergency onlyEOA returns (uint256 baseAmount) {
        address margin = IPairFactory(pairFactory).getMargin(WETH, quoteToken);
        require(margin != address(0), "Router.openPositionETHWithWallet: NOT_FOUND_MARGIN");
        require(side == 0 || side == 1, "Router.openPositionETHWithWallet: INSUFFICIENT_SIDE");
        uint256 marginAmount = msg.value;
        IWETH(WETH).deposit{value: marginAmount}();
        assert(IWETH(WETH).transfer(margin, marginAmount));
        IMargin(margin).addMargin(msg.sender, marginAmount);
        baseAmount = IMargin(margin).openPosition(msg.sender, side, quoteAmount);
        if (side == 0) {
            require(baseAmount >= baseAmountLimit, "Router.openPositionETHWithWallet: INSUFFICIENT_QUOTE_AMOUNT");
            _collectFee(baseAmount, margin);
        } else {
            require(baseAmount <= baseAmountLimit, "Router.openPositionETHWithWallet: INSUFFICIENT_QUOTE_AMOUNT");
        }
    }

    function openPositionWithMargin(
        address baseToken,
        address quoteToken,
        uint8 side,
        uint256 quoteAmount,
        uint256 baseAmountLimit,
        uint256 deadline
    ) external override ensure(deadline) notEmergency onlyEOA returns (uint256 baseAmount) {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router.openPositionWithMargin: NOT_FOUND_MARGIN");
        require(side == 0 || side == 1, "Router.openPositionWithMargin: INSUFFICIENT_SIDE");
        baseAmount = IMargin(margin).openPosition(msg.sender, side, quoteAmount);
        if (side == 0) {
            require(baseAmount >= baseAmountLimit, "Router.openPositionWithMargin: INSUFFICIENT_QUOTE_AMOUNT");
            _collectFee(baseAmount, margin);
        } else {
            require(baseAmount <= baseAmountLimit, "Router.openPositionWithMargin: INSUFFICIENT_QUOTE_AMOUNT");
        }
    }

    function closePosition(
        address baseToken,
        address quoteToken,
        uint256 quoteAmount,
        uint256 deadline,
        bool autoWithdraw
    ) external override ensure(deadline) onlyEOA returns (uint256 baseAmount, uint256 withdrawAmount) {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router.closePosition: NOT_FOUND_MARGIN");
        (, int256 quoteSizeBefore, ) = IMargin(margin).getPosition(msg.sender);
        if (!autoWithdraw) {
            baseAmount = IMargin(margin).closePosition(msg.sender, quoteAmount);
            if (quoteSizeBefore > 0) {
                _collectFee(baseAmount, margin);
            }
        } else {
            baseAmount = IMargin(margin).closePosition(msg.sender, quoteAmount);
            if (quoteSizeBefore > 0) {
                _collectFee(baseAmount, margin);
            }

            (int256 baseSize, int256 quoteSizeAfter, uint256 tradeSize) = IMargin(margin).getPosition(msg.sender);
            int256 unrealizedPnl = IMargin(margin).calUnrealizedPnl(msg.sender);
            int256 traderMargin;
            if (quoteSizeAfter < 0) { // long, traderMargin = baseSize - tradeSize + unrealizedPnl
                traderMargin = baseSize.subU(tradeSize) + unrealizedPnl;
            } else { // short, traderMargin = baseSize + tradeSize + unrealizedPnl
                traderMargin = baseSize.addU(tradeSize) + unrealizedPnl;
            }
            withdrawAmount = traderMargin.abs() - traderMargin.abs() * quoteSizeAfter.abs() / quoteSizeBefore.abs();
            uint256 withdrawable = IMargin(margin).getWithdrawable(msg.sender);
            if (withdrawable < withdrawAmount) {
                withdrawAmount = withdrawable;
            }
            
            if (withdrawAmount > 0) {
                IMargin(margin).removeMargin(msg.sender, msg.sender, withdrawAmount);
            }
        }
    }

    function closePositionETH(
        address quoteToken,
        uint256 quoteAmount,
        uint256 deadline
    ) external override ensure(deadline) onlyEOA returns (uint256 baseAmount, uint256 withdrawAmount) {
        address margin = IPairFactory(pairFactory).getMargin(WETH, quoteToken);
        require(margin != address(0), "Router.closePosition: NOT_FOUND_MARGIN");
        
        (, int256 quoteSizeBefore, ) = IMargin(margin).getPosition(msg.sender);
        baseAmount = IMargin(margin).closePosition(msg.sender, quoteAmount);
        if (quoteSizeBefore > 0) {
            _collectFee(baseAmount, margin);
        }
        
        (int256 baseSize, int256 quoteSizeAfter, uint256 tradeSize) = IMargin(margin).getPosition(msg.sender);
        int256 unrealizedPnl = IMargin(margin).calUnrealizedPnl(msg.sender);
        int256 traderMargin;
        if (quoteSizeAfter < 0) { // long, traderMargin = baseSize - tradeSize + unrealizedPnl
            traderMargin = baseSize.subU(tradeSize) + unrealizedPnl;
        } else { // short, traderMargin = baseSize + tradeSize + unrealizedPnl
            traderMargin = baseSize.addU(tradeSize) + unrealizedPnl;
        }
        withdrawAmount = traderMargin.abs() - traderMargin.abs() * quoteSizeAfter.abs() / quoteSizeBefore.abs();
        uint256 withdrawable = IMargin(margin).getWithdrawable(msg.sender);
        if (withdrawable < withdrawAmount) {
            withdrawAmount = withdrawable;
        }
        if (withdrawAmount > 0) {
            IMargin(margin).removeMargin(msg.sender, address(this), withdrawAmount);
            IWETH(WETH).withdraw(withdrawAmount);
            TransferHelper.safeTransferETH(msg.sender, withdrawAmount);
        }
    }

    function liquidate(
        address baseToken,
        address quoteToken,
        address trader,
        address to
    ) external override returns (uint256 quoteAmount, uint256 baseAmount, uint256 bonus) {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router.closePosition: NOT_FOUND_MARGIN");
        (quoteAmount, baseAmount, bonus) = IMargin(margin).liquidate(trader, to);
    }

    function getReserves(address baseToken, address quoteToken)
        external
        view
        override
        returns (uint256 reserveBase, uint256 reserveQuote)
    {
        address amm = IPairFactory(pairFactory).getAmm(baseToken, quoteToken);
        (reserveBase, reserveQuote, ) = IAmm(amm).getReserves();
    }

    function getQuoteAmount(
        address baseToken,
        address quoteToken,
        uint8 side,
        uint256 baseAmount
    ) external view override returns (uint256 quoteAmount) {
        address amm = IPairFactory(pairFactory).getAmm(baseToken, quoteToken);
        (uint256 reserveBase, uint256 reserveQuote, ) = IAmm(amm).getReserves();
        if (side == 0) {
            quoteAmount = _getAmountIn(baseAmount, reserveQuote, reserveBase);
        } else {
            quoteAmount = _getAmountOut(baseAmount, reserveBase, reserveQuote);
        }
    }

    function getWithdrawable(
        address baseToken,
        address quoteToken,
        address holder
    ) external view override returns (uint256 amount) {
        (amount, ) = _getWithdrawable(baseToken, quoteToken, holder);
    }

    function getPosition(
        address baseToken,
        address quoteToken,
        address holder
    )
        external
        view
        override
        returns (
            int256 baseSize,
            int256 quoteSize,
            uint256 tradeSize
        )
    {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        (baseSize, quoteSize, tradeSize) = IMargin(margin).getPosition(holder);
    }

    function _collectFee(uint256 baseAmount, address margin) internal {
        uint256 fee = baseAmount / 1000;
        address feeTreasury = IAmmFactory(IPairFactory(pairFactory).ammFactory()).feeTo();
        IMargin(margin).removeMargin(msg.sender, feeTreasury, fee);
        emit CollectFee(msg.sender, margin, fee);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "Router.getAmountOut: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "Router.getAmountOut: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 999;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "Router.getAmountIn: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "Router.getAmountIn: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 999;
        amountIn = numerator / denominator + 1;
    }

    //@notice withdrawable from fundingFee, unrealizedPnl and margin
    function _getWithdrawable(
        address baseToken,
        address quoteToken,
        address holder
    ) internal view returns (uint256 amount, int256 unrealizedPnl) {
        address amm = IPairFactory(pairFactory).getAmm(baseToken, quoteToken);
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        (int256 baseSize, int256 quoteSize, uint256 tradeSize) = IMargin(margin).getPosition(holder);
        int256 fundingFee = IMargin(margin).calFundingFee(holder);
        baseSize = baseSize + fundingFee;
        if (quoteSize == 0) {
            amount = baseSize <= 0 ? 0 : baseSize.abs();
        } else if (quoteSize < 0) {
            uint256 baseAmount = IPriceOracle(IConfig(config).priceOracle()).getMarkPriceAcc(
                amm,
                IConfig(config).beta(),
                quoteSize.abs(),
                true
            );

            uint256 a = baseAmount * 10000;
            uint256 b = (10000 - IConfig(config).initMarginRatio());
            //calculate how many base needed to maintain current position
            uint256 baseNeeded = a / b;
            if (a % b != 0) {
                baseNeeded += 1;
            }
            //borrowed - repay, earn when borrow more and repay less
            unrealizedPnl = int256(1).mulU(tradeSize).subU(baseAmount);
            amount = baseSize.abs() <= baseNeeded ? 0 : baseSize.abs() - baseNeeded;
        } else {
            uint256 baseAmount = IPriceOracle(IConfig(config).priceOracle()).getMarkPriceAcc(
                amm,
                IConfig(config).beta(),
                quoteSize.abs(),
                false
            );

            uint256 baseNeeded = (baseAmount * (10000 - IConfig(config).initMarginRatio())) / 10000;
            //repay - lent, earn when lent less and repay more
            unrealizedPnl = int256(1).mulU(baseAmount).subU(tradeSize);
            int256 remainBase = baseSize.addU(baseNeeded);
            amount = remainBase <= 0 ? 0 : remainBase.abs();
        }
    }
}

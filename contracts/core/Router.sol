// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IRouter.sol";
import "./interfaces/IPairFactory.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IMargin.sol";
import "./interfaces/ILiquidityERC20.sol";
import "./interfaces/IWETH.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/FullMath.sol";

contract Router is IRouter {
    address public immutable override pairFactory;
    address public immutable override pcvTreasury;
    address public immutable override WETH;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        _;
    }

    constructor(
        address pairFactory_,
        address pcvTreasury_,
        address _WETH
    ) {
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
    ) external override ensure(deadline) returns (uint256 quoteAmount, uint256 liquidity) {
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
    ) external override ensure(deadline) returns (uint256 baseAmount, uint256 quoteAmount) {
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
    ) external override ensure(deadline) returns (uint256 ethAmount, uint256 quoteAmount) {
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
    ) external override {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router.deposit: NOT_FOUND_MARGIN");
        TransferHelper.safeTransferFrom(baseToken, msg.sender, margin, amount);
        IMargin(margin).addMargin(holder, amount);
    }

    function depositETH(address quoteToken, address holder) external payable override {
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
        IMargin(margin).removeMargin(msg.sender, msg.sender, amount);
    }

    function withdrawETH(address quoteToken, uint256 amount) external override {
        address margin = IPairFactory(pairFactory).getMargin(WETH, quoteToken);
        require(margin != address(0), "Router.withdraw: NOT_FOUND_MARGIN");
        IMargin(margin).removeMargin(msg.sender, address(this), amount);
        IWETH(WETH).withdraw(amount);
        TransferHelper.safeTransferETH(msg.sender, amount);
    }

    function openPositionWithWallet(
        address baseToken,
        address quoteToken,
        uint8 side,
        uint256 marginAmount,
        uint256 quoteAmount,
        uint256 baseAmountLimit,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 baseAmount) {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router.openPositionWithWallet: NOT_FOUND_MARGIN");
        require(side == 0 || side == 1, "Router.openPositionWithWallet: INSUFFICIENT_SIDE");
        TransferHelper.safeTransferFrom(baseToken, msg.sender, margin, marginAmount);
        IMargin(margin).addMargin(msg.sender, marginAmount);
        baseAmount = IMargin(margin).openPosition(msg.sender, side, quoteAmount);
        if (side == 0) {
            require(baseAmount >= baseAmountLimit, "Router.openPositionWithWallet: INSUFFICIENT_QUOTE_AMOUNT");
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
    ) external payable override ensure(deadline) returns (uint256 baseAmount) {
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
    ) external override ensure(deadline) returns (uint256 baseAmount) {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router.openPositionWithMargin: NOT_FOUND_MARGIN");
        require(side == 0 || side == 1, "Router.openPositionWithMargin: INSUFFICIENT_SIDE");
        baseAmount = IMargin(margin).openPosition(msg.sender, side, quoteAmount);
        if (side == 0) {
            require(baseAmount >= baseAmountLimit, "Router.openPositionWithMargin: INSUFFICIENT_QUOTE_AMOUNT");
        } else {
            require(baseAmount <= baseAmountLimit, "Router.openPositionWithMargin: INSUFFICIENT_QUOTE_AMOUNT");
        }
    }

    function closePosition(
        address baseToken,
        address quoteToken,
        uint256 quoteAmount,
        uint256 userMargin,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 baseAmount, uint256 withdrawAmount) {
        address margin;
        (margin, baseAmount, withdrawAmount) = _closePosition(msg.sender, baseToken, quoteToken, quoteAmount, userMargin);
        if (withdrawAmount > 0) {
            uint256 withdrawable = IMargin(margin).getWithdrawable(msg.sender);
            require(withdrawable >= withdrawAmount, "Router.closePosition: NOT_ENOUGH_WITHDRAWABLE");
            IMargin(margin).removeMargin(msg.sender, msg.sender, withdrawAmount);
        }
    }

    function closePositionETH(
        address quoteToken,
        uint256 quoteAmount,
        uint256 userMargin,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 baseAmount, uint256 withdrawAmount) {
        address margin;
        (margin, baseAmount, withdrawAmount) = _closePosition(msg.sender, WETH, quoteToken, quoteAmount, userMargin);
        if (withdrawAmount > 0) {
            uint256 withdrawable = IMargin(margin).getWithdrawable(msg.sender);
            require(withdrawable >= withdrawAmount, "Router.closePosition: NOT_ENOUGH_WITHDRAWABLE");
            IMargin(margin).removeMargin(msg.sender, address(this), withdrawAmount);
            IWETH(WETH).withdraw(withdrawAmount);
            TransferHelper.safeTransferETH(msg.sender, withdrawAmount);
        }
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
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        amount = IMargin(margin).getWithdrawable(holder);
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

    // positionValueBefore / userMarginBefore = positionValueAfter / userMarginAfter  =>
    // quoteSizeBefore / priceBefore / userMarginBefore = quoteSizeAfter / priceAfter / userMarginAfter  =>
    // (quoteSizeBefore * reserveBaseBefore / reserveQuoteBefore) / userMarginBefore = (quoteSizeAfter * reserveBaseAfter / reserveQuoteAfter) / userMarginAfter
    function _closePosition(
        address trader,
        address baseToken,
        address quoteToken,
        uint256 quoteAmount,
        uint256 userMargin
    ) internal returns (address margin, uint256 baseAmount, uint256 withdrawAmount) {
        address amm = IPairFactory(pairFactory).getAmm(baseToken, quoteToken);
        margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router.closePosition: NOT_FOUND_MARGIN");

        (uint256 reserveBase, uint256 reserveQuote, ) = IAmm(amm).getReserves();
        (, int quoteSize, ) = IMargin(margin).getPosition(trader);
        uint256 quoteSizeU = quoteSize >= 0 ? uint256(quoteSize) : uint256(0 - quoteSize);
        uint256 valueBefore = FullMath.mulDiv(quoteSizeU, reserveBase, reserveQuote);

        baseAmount = IMargin(margin).closePosition(trader, quoteAmount);

        (reserveBase, reserveQuote, ) = IAmm(amm).getReserves();
        (, quoteSize, ) = IMargin(margin).getPosition(trader);
        quoteSizeU = quoteSize >= 0 ? uint256(quoteSize) : uint256(0 - quoteSize);
        uint256 valueAfter = FullMath.mulDiv(quoteSizeU, reserveBase, reserveQuote);

        uint256 userMarginAfter = valueAfter * userMargin / valueBefore;
        withdrawAmount = (userMarginAfter >= userMargin) ? (userMarginAfter - userMargin) : (userMargin - userMarginAfter);
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
}

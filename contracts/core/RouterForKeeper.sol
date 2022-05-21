// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/IRouterForKeeper.sol";
import "../interfaces/IOrderBook.sol";
import "../interfaces/IPairFactory.sol";
import "../interfaces/IMargin.sol";
import "../interfaces/IAmm.sol";
import "../interfaces/IWETH.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/SignedMath.sol";
import "../libraries/FullMath.sol";
import "../utils/Ownable.sol";

contract RouterForKeeper is IRouterForKeeper, Ownable {
    using SignedMath for int256;
    using FullMath for uint256;

    address public immutable override pairFactory;
    address public immutable override WETH;
    address public orderBook;
    mapping(address => mapping(address => uint256)) public balanceOf;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "RouterForKeeper: EXPIRED");
        _;
    }

    modifier onlyOrderBook() {
        require(msg.sender == orderBook, "RouterForKeeper:only orderboook");
        _;
    }

    constructor(address pairFactory_, address _WETH) {
        owner = msg.sender;
        pairFactory = pairFactory_;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function setOrderBook(address newOrderBook) external override onlyOwner {
        require(newOrderBook != address(0), "RouterForKeeper.setOrderBook: ZERO_ADDRESS");
        orderBook = newOrderBook;
    }

    function openPositionWithWallet(IOrderBook.OpenPositionOrder memory order, uint256 slippageRatio)
        external
        override
        ensure(order.deadline)
        returns (uint256 baseAmount)
    {
        address margin = IPairFactory(pairFactory).getMargin(order.baseToken, order.quoteToken);
        require(margin != address(0), "RouterForKeeper.openPositionWithWallet: NOT_FOUND_MARGIN");
        require(order.side == 0 || order.side == 1, "RouterForKeeper.openPositionWithWallet: INVALID_SIDE");

        TransferHelper.safeTransferFrom(order.baseToken, order.trader, margin, order.baseAmount);

        IMargin(margin).addMargin(order.trader, order.baseAmount);
        baseAmount = IMargin(margin).openPosition(order.trader, order.side, order.quoteAmount);

        require(
            (order.side == 0)
                ? slippageRatio < ((order.quoteAmount * 1e18) / baseAmount)
                : slippageRatio > ((order.quoteAmount * 1e18) / baseAmount),
            "RouterForKeeper.openPositionWithWallet: INSUFFICIENT_QUOTE_AMOUNT"
        );
    }

    function openPositionWithMargin(IOrderBook.OpenPositionOrder memory order, uint256 slippageRatio)
        external
        override
        ensure(order.deadline)
        onlyOrderBook
        returns (uint256 baseAmount)
    {
        address margin = IPairFactory(pairFactory).getMargin(order.baseToken, order.quoteToken);
        require(margin != address(0), "RouterForKeeper.openPositionWithMargin: NOT_FOUND_MARGIN");
        require(order.side == 0 || order.side == 1, "RouterForKeeper.openPositionWithMargin: INVALID_SIDE");
        baseAmount = IMargin(margin).openPosition(order.trader, order.side, order.quoteAmount);

        require(
            (order.side == 0)
                ? slippageRatio < ((order.quoteAmount * 1e18) / baseAmount)
                : slippageRatio > ((order.quoteAmount * 1e18) / baseAmount),
            "RouterForKeeper.openPositionWithMargin: INSUFFICIENT_QUOTE_AMOUNT"
        );
    }

    function closePosition(IOrderBook.ClosePositionOrder memory order)
        external
        override
        ensure(order.deadline)
        returns (uint256 baseAmount, uint256 withdrawAmount)
    {
        address margin = IPairFactory(pairFactory).getMargin(order.baseToken, order.quoteToken);
        require(margin != address(0), "RouterForKeeper.closePosition: NOT_FOUND_MARGIN");
        (, int256 quoteSizeBefore, ) = IMargin(margin).getPosition(order.trader);
        require(
            quoteSizeBefore > 0 ? order.side == 1 : order.side == 0,
            "RouterForKeeper.closePosition: SIDE_NOT_MATCH"
        );
        if (!order.autoWithdraw) {
            baseAmount = IMargin(margin).closePosition(order.trader, order.quoteAmount);
        } else {
            {
                baseAmount = IMargin(margin).closePosition(order.trader, order.quoteAmount);
                (int256 baseSize, int256 quoteSizeAfter, uint256 tradeSize) = IMargin(margin).getPosition(order.trader);
                int256 unrealizedPnl = IMargin(margin).calUnrealizedPnl(order.trader);
                int256 traderMargin;
                if (quoteSizeAfter < 0) {
                    // long, traderMargin = baseSize - tradeSize + unrealizedPnl
                    traderMargin = baseSize.subU(tradeSize) + unrealizedPnl;
                } else {
                    // short, traderMargin = baseSize + tradeSize + unrealizedPnl
                    traderMargin = baseSize.addU(tradeSize) + unrealizedPnl;
                }
                withdrawAmount =
                    traderMargin.abs() -
                    (traderMargin.abs() * quoteSizeAfter.abs()) /
                    quoteSizeBefore.abs();
            }

            uint256 withdrawable = IMargin(margin).getWithdrawable(order.trader);
            if (withdrawable < withdrawAmount) {
                withdrawAmount = withdrawable;
            }
            if (withdrawAmount > 0) {
                IMargin(margin).removeMargin(order.trader, order.trader, withdrawAmount);
            }
        }
    }

    //if eth is 2000usdc, then here return 2000*1e18, 18, 6
    function getSpotPriceWithMultiplier(address baseToken, address quoteToken)
        external
        view
        override
        returns (
            uint256 spotPriceWithMultiplier,
            uint256 baseDecimal,
            uint256 quoteDecimal
        )
    {
        address amm = IPairFactory(pairFactory).getAmm(baseToken, quoteToken);
        (uint256 reserveBase, uint256 reserveQuote, ) = IAmm(amm).getReserves();

        uint256 baseDecimals = IERC20(baseToken).decimals();
        uint256 quoteDecimals = IERC20(quoteToken).decimals();
        uint256 exponent = uint256(10**(18 + baseDecimals - quoteDecimals));

        return (exponent.mulDiv(reserveQuote, reserveBase), baseDecimals, quoteDecimals);
    }
}

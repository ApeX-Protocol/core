// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/IAmmFactory.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IRouterForKeeper.sol";
import "../interfaces/IConfig.sol";
import "../interfaces/IOrderBook.sol";
import "../interfaces/IPairFactory.sol";
import "../interfaces/IMargin.sol";
import "../interfaces/IAmm.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IPriceOracle.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/SignedMath.sol";
import "../libraries/FullMath.sol";
import "../utils/Ownable.sol";

contract RouterForKeeper is IRouterForKeeper, Ownable {
    using SignedMath for int256;
    using FullMath for uint256;

    address public immutable override config;
    address public immutable override pairFactory;
    address public immutable override WETH;
    address public immutable override USDC;
    address public override orderBook;
    address public override keeper;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "RFK: EXPIRED");
        _;
    }

    modifier onlyOrderBook() {
        require(msg.sender == orderBook, "RFK:only orderboook");
        _;
    }

    constructor(address config_, address pairFactory_, address WETH_, address USDC_) {
        owner = msg.sender;
        config = config_;
        pairFactory = pairFactory_;
        WETH = WETH_;
        USDC = USDC_;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function setOrderBook(address newOrderBook) external override onlyOwner {
        require(newOrderBook != address(0), "RFK.SOB: ZERO_ADDRESS");
        orderBook = newOrderBook;
    }

    function setKeeper(address keeper_) external override onlyOwner {
        require(keeper_ != address(0), "RFK.SK: ZERO_ADDRESS");
        keeper = keeper_;
    }

    function openPositionWithWallet(IOrderBook.OpenPositionOrder memory order)
        external
        override
        ensure(order.deadline)
        onlyOrderBook
        returns (uint256 baseAmount)
    {
        address margin = IPairFactory(pairFactory).getMargin(order.baseToken, order.quoteToken);
        require(margin != address(0), "RFK.OPWW: NOT_FOUND_MARGIN");
        require(order.side == 0 || order.side == 1, "RFK.OPWW: INVALID_SIDE");

        TransferHelper.safeTransferFrom(order.baseToken, order.trader, margin, order.baseAmount);

        IMargin(margin).addMargin(order.trader, order.baseAmount);
        baseAmount = IMargin(margin).openPosition(order.trader, order.side, order.quoteAmount);
        if (order.side == 0) {
            _collectFee(baseAmount, margin, order.trader);
        }
        _rewardForKeeper(margin, order.trader, order.baseToken);
    }

    function openPositionWithMargin(IOrderBook.OpenPositionOrder memory order)
        external
        override
        ensure(order.deadline)
        onlyOrderBook
        returns (uint256 baseAmount)
    {
        address margin = IPairFactory(pairFactory).getMargin(order.baseToken, order.quoteToken);
        require(margin != address(0), "RFK.OPWM: NOT_FOUND_MARGIN");
        require(order.side == 0 || order.side == 1, "RFK.OPWM: INVALID_SIDE");
        baseAmount = IMargin(margin).openPosition(order.trader, order.side, order.quoteAmount);
        if (order.side == 0) {
            _collectFee(baseAmount, margin, order.trader);
        }
        _rewardForKeeper(margin, order.trader, order.baseToken);
    }

    function closePosition(IOrderBook.ClosePositionOrder memory order)
        external
        override
        ensure(order.deadline)
        onlyOrderBook
    returns (uint256 baseAmount, uint256 withdrawAmount)
    {
        address margin = IPairFactory(pairFactory).getMargin(order.baseToken, order.quoteToken);
        require(margin != address(0), "RFK.CP: NOT_FOUND_MARGIN");
        (, int256 quoteSizeBefore, ) = IMargin(margin).getPosition(order.trader);
        require(
            quoteSizeBefore > 0 ? order.side == 1 : order.side == 0,
            "RFK.CP: SIDE_NOT_MATCH"
        );
        _rewardForKeeper(margin, order.trader, order.baseToken);
        if (!order.autoWithdraw) {
            baseAmount = IMargin(margin).closePosition(order.trader, order.quoteAmount);
            if (quoteSizeBefore > 0) {
                _collectFee(baseAmount, margin, order.trader);
            }
        } else {
            {
                baseAmount = IMargin(margin).closePosition(order.trader, order.quoteAmount);
                if (quoteSizeBefore > 0) {
                    _collectFee(baseAmount, margin, order.trader);
                }
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

    function _collectFee(uint256 baseAmount, address margin, address trader) internal {
        uint256 fee = baseAmount / 1000;
        address feeTreasury = IAmmFactory(IPairFactory(pairFactory).ammFactory()).feeTo();
        IMargin(margin).removeMargin(trader, feeTreasury, fee);
        emit CollectFee(trader, margin, fee);
    }

    function _rewardForKeeper(address margin, address trader, address baseToken) internal {
        IPriceOracle oracle = IPriceOracle(IConfig(config).priceOracle());
        uint8 baseDecimals = IERC20(baseToken).decimals();
        uint8 usdcDecimals = IERC20(USDC).decimals();
        (uint256 usdcAmount, ) = oracle.quote(baseToken, USDC, 10**(baseDecimals));
        uint256 reward = 10**(baseDecimals + usdcDecimals) / usdcAmount;
        IMargin(margin).removeMargin(trader, keeper, reward);
        emit RewardForKeeper(trader, margin, reward);
    }
}

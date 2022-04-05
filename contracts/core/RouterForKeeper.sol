// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IRouterForKeeper.sol";
import "./interfaces/IPairFactory.sol";
import "./interfaces/IMargin.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IWETH.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/SignedMath.sol";
import "../libraries/FullMath.sol";
import "hardhat/console.sol";

contract RouterForKeeper is IRouterForKeeper {
    using SignedMath for int256;
    using FullMath for uint256;

    address public immutable override pairFactory;
    address public immutable override WETH;
    mapping(address => mapping(address => uint256)) public balanceOf;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "RouterForKeeper: EXPIRED");
        _;
    }

    constructor(address pairFactory_, address _WETH) {
        pairFactory = pairFactory_;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function deposit(
        address baseToken,
        address to,
        uint256 amount
    ) external override {
        TransferHelper.safeTransferFrom(baseToken, msg.sender, address(this), amount);
        balanceOf[baseToken][to] += amount;
        emit Deposit(baseToken, msg.sender, to, amount);
    }

    function depositETH(address to) external payable override {
        uint256 amount = msg.value;
        IWETH(WETH).deposit{value: amount}();
        balanceOf[WETH][to] += amount;
        emit DepositETH(msg.sender, to, amount);
    }

    function withdraw(
        address baseToken,
        address to,
        uint256 amount
    ) external override {
        uint256 balance = balanceOf[baseToken][msg.sender];
        require(amount <= balance, "RouterForKeeper.withdraw: INSUFFICIENT_BASE_TOKEN");
        TransferHelper.safeTransfer(baseToken, to, amount);
        balanceOf[baseToken][msg.sender] -= amount;

        emit Withdraw(baseToken, msg.sender, to, amount);
    }

    function withdrawETH(address to, uint256 amount) external override {
        uint256 balance = balanceOf[WETH][msg.sender];
        require(amount <= balance, "RouterForKeeper.withdrawETH: INSUFFICIENT_WETH");
        IWETH(WETH).withdraw(amount);
        TransferHelper.safeTransferETH(to, amount);
        balanceOf[WETH][msg.sender] = balance - amount;

        emit WithdrawETH(msg.sender, to, amount);
    }

    function openPositionWithWallet(
        address baseToken,
        address quoteToken,
        address from,
        address holder,
        uint8 side,
        uint256 marginAmount,
        uint256 quoteAmount,
        uint256 baseAmountLimit,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 baseAmount) {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "RouterForKeeper.openPositionWithWallet: NOT_FOUND_MARGIN");
        require(side == 0 || side == 1, "RouterForKeeper.openPositionWithWallet: INVALID_SIDE");
        uint256 balance = balanceOf[baseToken][from];
        require(marginAmount <= balance, "RouterForKeeper.openPositionWithWallet: NO_SUFFICIENT_MARGIN");

        TransferHelper.safeTransfer(baseToken, margin, marginAmount);
        balanceOf[baseToken][from] = balance - marginAmount;

        IMargin(margin).addMargin(holder, marginAmount);
        baseAmount = IMargin(margin).openPosition(holder, side, quoteAmount);
        if (side == 0) {
            require(baseAmount >= baseAmountLimit, "RouterForKeeper.openPositionWithWallet: INSUFFICIENT_QUOTE_AMOUNT");
        } else {
            require(baseAmount <= baseAmountLimit, "RouterForKeeper.openPositionWithWallet: INSUFFICIENT_QUOTE_AMOUNT");
        }
    }

    function openPositionWithMargin(
        address baseToken,
        address quoteToken,
        address holder,
        uint8 side,
        uint256 quoteAmount,
        uint256 baseAmountLimit,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 baseAmount) {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "RouterForKeeper.openPositionWithMargin: NOT_FOUND_MARGIN");
        require(side == 0 || side == 1, "RouterForKeeper.openPositionWithMargin: INVALID_SIDE");
        baseAmount = IMargin(margin).openPosition(holder, side, quoteAmount);
        if (side == 0) {
            require(baseAmount >= baseAmountLimit, "RouterForKeeper.openPositionWithMargin: INSUFFICIENT_QUOTE_AMOUNT");
        } else {
            require(baseAmount <= baseAmountLimit, "RouterForKeeper.openPositionWithMargin: INSUFFICIENT_QUOTE_AMOUNT");
        }
    }

    function closePosition(
        address baseToken,
        address quoteToken,
        address holder,
        address to,
        uint256 quoteAmount,
        uint256 deadline,
        bool autoWithdraw
    ) external override ensure(deadline) returns (uint256 baseAmount, uint256 withdrawAmount) {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "RouterForKeeper.closePosition: NOT_FOUND_MARGIN");
        if (!autoWithdraw) {
            baseAmount = IMargin(margin).closePosition(holder, quoteAmount);
        } else {
            {
                (, int256 quoteSizeBefore, ) = IMargin(margin).getPosition(holder);
                baseAmount = IMargin(margin).closePosition(holder, quoteAmount);
                (int256 baseSize, int256 quoteSizeAfter, uint256 tradeSize) = IMargin(margin).getPosition(holder);
                int256 unrealizedPnl = IMargin(margin).calUnrealizedPnl(holder);
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

            uint256 withdrawable = IMargin(margin).getWithdrawable(holder);
            if (withdrawable < withdrawAmount) {
                withdrawAmount = withdrawable;
            }
            if (withdrawAmount > 0) {
                IMargin(margin).removeMargin(holder, to, withdrawAmount);
            }
        }
    }

    //if eth is 2000usdc, then here return 2000*1e18
    function getSpotPriceWithMultiplier(address baseToken, address quoteToken)
        external
        view
        override
        returns (uint256 spotPriceWithMultiplier)
    {
        address amm = IPairFactory(pairFactory).getAmm(baseToken, quoteToken);
        (uint256 reserveBase, uint256 reserveQuote, ) = IAmm(amm).getReserves();

        uint256 baseDecimals = IERC20(baseToken).decimals();
        uint256 quoteDecimals = IERC20(quoteToken).decimals();
        uint256 exponent = uint256(10**(18 + baseDecimals - quoteDecimals));

        return exponent.mulDiv(reserveQuote, reserveBase);
    }
}

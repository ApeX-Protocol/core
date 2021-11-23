//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./interfaces/IRouter.sol";
import "./interfaces/IPairFactory.sol";
import "./interfaces/IStakingFactory.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IMargin.sol";
import "./interfaces/ILiquidityERC20.sol";
import "./interfaces/IStaking.sol";
import "./libraries/TransferHelper.sol";

contract Router is IRouter {
    address public immutable override pairFactory;
    address public immutable override stakingFactory;
    address public immutable override WETH;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        _;
    }

    constructor(
        address pairFactory_,
        address stakingFactory_,
        address _WETH
    ) {
        pairFactory = pairFactory_;
        stakingFactory = stakingFactory_;
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
        bool autoStake
    ) external override ensure(deadline) returns (uint256 quoteAmount, uint256 liquidity) {
        if (IPairFactory(pairFactory).getAmm(baseToken, quoteToken) == address(0)) {
            IPairFactory(pairFactory).createPair(baseToken, quoteToken);
        }
        address amm = IPairFactory(pairFactory).getAmm(baseToken, quoteToken);
        TransferHelper.safeTransferFrom(baseToken, msg.sender, amm, baseAmount);
        if (autoStake) {
            (, quoteAmount, liquidity) = IAmm(amm).mint(address(this));
            address staking = IStakingFactory(stakingFactory).getStaking(amm);
            if (staking == address(0)) {
                staking = IStakingFactory(stakingFactory).createStaking(baseToken, quoteToken);
            }
            ILiquidityERC20(amm).approve(staking, liquidity);
            IStaking(staking).stake(liquidity);
        } else {
            (, quoteAmount, liquidity) = IAmm(amm).mint(msg.sender);
        }
        require(quoteAmount >= quoteAmountMin, "Router: INSUFFICIENT_QUOTE_AMOUNT");
    }

    function removeLiquidity(
        address baseToken,
        address quoteToken,
        uint256 liquidity,
        uint256 baseAmountMin,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 baseAmount, uint256 quoteAmount) {
        address amm = IPairFactory(pairFactory).getAmm(baseToken, quoteToken);
        ILiquidityERC20(amm).transferFrom(msg.sender, amm, liquidity);
        (baseAmount, quoteAmount, ) = IAmm(amm).burn(msg.sender);
        require(baseAmount >= baseAmountMin, "Router: INSUFFICIENT_BASE_AMOUNT");
    }

    function deposit(
        address baseToken,
        address quoteToken,
        address holder,
        uint256 amount
    ) external override {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router: ZERO_ADDRESS");
        TransferHelper.safeTransferFrom(baseToken, msg.sender, margin, amount);
        IMargin(margin).addMargin(holder, amount);
    }

    function withdraw(
        address baseToken,
        address quoteToken,
        uint256 amount
    ) external override {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router: ZERO_ADDRESS");
        IMargin(margin).removeMargin(msg.sender, amount);
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
        require(margin != address(0), "Router: ZERO_ADDRESS");
        require(side == 0 || side == 1, "Router: INSUFFICIENT_SIDE");
        TransferHelper.safeTransferFrom(baseToken, msg.sender, margin, marginAmount);
        IMargin(margin).addMargin(msg.sender, marginAmount);
        baseAmount = IMargin(margin).openPosition(msg.sender, side, quoteAmount);
        if (side == 0) {
            require(baseAmount >= baseAmountLimit, "Router: INSUFFICIENT_QUOTE_AMOUNT");
        } else {
            require(baseAmount <= baseAmountLimit, "Router: INSUFFICIENT_QUOTE_AMOUNT");
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
        require(margin != address(0), "Router: ZERO_ADDRESS");
        require(side == 0 || side == 1, "Router: INSUFFICIENT_SIDE");
        baseAmount = IMargin(margin).openPosition(msg.sender, side, quoteAmount);
        if (side == 0) {
            require(baseAmount >= baseAmountLimit, "Router: INSUFFICIENT_QUOTE_AMOUNT");
        } else {
            require(baseAmount <= baseAmountLimit, "Router: INSUFFICIENT_QUOTE_AMOUNT");
        }
    }

    function closePosition(
        address baseToken,
        address quoteToken,
        uint256 quoteAmount,
        uint256 deadline,
        bool autoWithdraw
    ) external override ensure(deadline) returns (uint256 baseAmount, uint256 withdrawAmount) {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        require(margin != address(0), "Router: ZERO_ADDRESS");
        baseAmount = IMargin(margin).closePosition(msg.sender, quoteAmount);
        if (autoWithdraw) {
            withdrawAmount = IMargin(margin).getWithdrawable(msg.sender);
            if (withdrawAmount > 0) {
                IMargin(margin).removeMargin(msg.sender, withdrawAmount);
            }
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
            quoteAmount = getAmountIn(baseAmount, reserveQuote, reserveBase);
        } else {
            quoteAmount = getAmountOut(baseAmount, reserveBase, reserveQuote);
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

    function queryMaxOpenPosition(
        address baseToken,
        address quoteToken,
        uint8 side,
        uint256 baseAmount
    ) external view override returns (uint256 quoteAmount) {
        address margin = IPairFactory(pairFactory).getMargin(baseToken, quoteToken);
        return IMargin(margin).getMaxOpenPosition(side, baseAmount);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "Router: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "Router: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 999;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "Router: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "Router: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 999;
        amountIn = numerator / denominator + 1;
    }
}

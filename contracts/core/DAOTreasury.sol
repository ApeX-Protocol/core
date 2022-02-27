// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IAmm.sol";
import "../utils/Ownable.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/TickMath.sol";
import "../core/interfaces/uniswapV3/IUniswapV3Factory.sol";
import "../core/interfaces/uniswapV3/IUniswapV3Pool.sol";
import "../core/interfaces/IWETH.sol";

contract DAOTreasury is Ownable {
    event RecipientChanged(address indexed oldRecipient, address indexed newRecipient);
    event OperatorChanged(address indexed oldOperator, address indexed newOperator);

    address public recipient;
    address public operator;

    address public WETH;
    address public v3Factory;
    uint24[3] public v3Fees;

    modifier onlyOperator() {
        require(msg.sender == operator, "FORBIDDEN");
        _;
    }

    constructor(address WETH_, address v3Factory_, address recipient_, address operator_) {
        owner = msg.sender;
        WETH = WETH_;
        v3Factory = v3Factory_;
        recipient = recipient_;
        operator = operator_;
        v3Fees[0] = 500;
        v3Fees[1] = 3000;
        v3Fees[2] = 10000;
    }

    function setRecipient(address recipient_) external onlyOwner {
        require(recipient != address(0), "ZERO_ADDRESS");
        emit RecipientChanged(recipient, recipient_);
        recipient = recipient_;
    }

    function setOperator(address operator_) external onlyOwner {
        require(operator_ != address(0), "ZERO_ADDRESS");
        emit OperatorChanged(operator, operator_);
        operator = operator_;
    }

    function batchRemoveLiquidity(address[] memory amms) external onlyOperator {
        for (uint256 i = 0; i < amms.length; i++) {
            address amm = amms[i];
            uint256 liquidity = IERC20(amm).balanceOf(address(this));
            if (liquidity == 0) continue;
            TransferHelper.safeTransfer(amm, amm, liquidity);
            IAmm(amm).burn(address(this));
        }
    }

    function batchSwapToETH(address[] memory tokens) external onlyOperator {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (token != WETH && balance > 0) {
                // query target pool
                address pool;
                uint256 poolLiquidity;
                for (uint256 j = 0; j < v3Fees.length; j++) {
                    address tempPool = IUniswapV3Factory(v3Factory).getPool(token, WETH, v3Fees[j]);
                    if (tempPool == address(0)) continue;
                    uint256 tempLiquidity = uint256(IUniswapV3Pool(tempPool).liquidity());
                    // use the max liquidity pool as target pool
                    if (tempLiquidity > poolLiquidity) {
                        poolLiquidity = tempLiquidity;
                        pool = tempPool;
                    }
                }

                // swap token to WETH
                bool zeroForOne = token < WETH;
                IUniswapV3Pool(pool).swap(
                    address(this),
                    zeroForOne,
                    int256(balance),
                    zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                    ""
                );
            }
        }
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        IWETH(WETH).withdraw(wethBalance);
    }

    function withdrawUSDC(address[] memory amms) external onlyOwner {

    }

    function _getPool(address token) internal view returns (address pool) {
        uint256 poolLiquidity;
        for (uint256 i = 0; i < v3Fees.length; i++) {
            address tempPool = IUniswapV3Factory(v3Factory).getPool(token, WETH, v3Fees[i]);
            if (tempPool == address(0)) continue;
            uint256 tempLiquidity = uint256(IUniswapV3Pool(tempPool).liquidity());
            // use the max liquidity pool as target pool
            if (tempLiquidity > poolLiquidity) {
                poolLiquidity = tempLiquidity;
                pool = tempPool;
            }
        }
    }
}
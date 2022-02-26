// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IAmm.sol";
import "../utils/Ownable.sol";
import "../libraries/TransferHelper.sol";
import "../core/interfaces/uniswapV3/IUniswapV3Factory.sol";
import "../core/interfaces/uniswapV3/IUniswapV3Pool.sol";

contract FeeToTreasury is Ownable {
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

    function swapETH(address[] memory tokens) external onlyOperator {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (token != WETH && balance > 0) {
                address pool;
                uint256 poolLiquidity;
                for (uint256 j = 0; j < v3Fees.length; j++) {
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
    }

    function withdrawUSDC(address[] memory amms) external onlyOwner {

    }

    function getBestPool() internal {
        // find out the pool with best liquidity as target pool
        address pool;
        address tempPool;
        uint256 poolLiquidity;
        uint256 tempLiquidity;
        // for (uint256 i = 0; i < v3Fees.length; i++) {
        //     tempPool = IUniswapV3Factory(v3Factory).getPool(baseToken, quoteToken, v3Fees[i]);
        //     if (tempPool == address(0)) continue;
        //     tempLiquidity = uint256(IUniswapV3Pool(tempPool).liquidity());
        //     // use the max liquidity pool as index price source
        //     if (tempLiquidity > poolLiquidity) {
        //         poolLiquidity = tempLiquidity;
        //         pool = tempPool;
        //     }
        // }
    }
}
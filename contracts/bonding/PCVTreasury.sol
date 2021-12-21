// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IPCVTreasury.sol";
import "./interfaces/IPCVPolicy.sol";
import "../core/interfaces/IERC20.sol";
import "../libraries/TransferHelper.sol";
import "../utils/Ownable.sol";

///@notice PCVTreasury contract manager all PCV(Protocol Controlled Value) assets
///@dev apeXToken for bonding is need to be transferred into this contract before bonding really setup
contract PCVTreasury is IPCVTreasury, Ownable {
    address public immutable override apeXToken;
    mapping(address => bool) public override isLiquidityToken;
    mapping(address => bool) public override isBondPool;

    constructor(address apeXToken_) {
        owner = msg.sender;
        apeXToken = apeXToken_;
    }

    function addLiquidityToken(address lpToken) external override onlyOwner {
        require(lpToken != address(0), "PCVTreasury.addLiquidityToken: ZERO_ADDRESS");
        require(!isLiquidityToken[lpToken], "PCVTreasury.addLiquidityToken: ALREADY_ADDED");
        isLiquidityToken[lpToken] = true;
        emit NewLiquidityToken(lpToken);
    }

    function addBondPool(address pool) external override onlyOwner {
        require(pool != address(0), "PCVTreasury.addBondPool: ZERO_ADDRESS");
        require(!isBondPool[pool], "PCVTreasury.addBondPool: ALREADY_ADDED");
        isBondPool[pool] = true;
        emit NewBondPool(pool);
    }

    function deposit(
        address lpToken,
        uint256 amountIn,
        uint256 payout
    ) external override {
        require(isBondPool[msg.sender], "PCVTreasury.deposit: FORBIDDEN");
        require(isLiquidityToken[lpToken], "PCVTreasury.deposit: NOT_LIQUIDITY_TOKEN");
        require(amountIn > 0, "PCVTreasury.deposit: ZERO_AMOUNT_IN");
        require(payout > 0, "PCVTreasury.deposit: ZERO_PAYOUT");
        uint256 apeXBalance = IERC20(apeXToken).balanceOf(address(this));
        require(payout <= apeXBalance, "PCVTreasury.deposit: NOT_ENOUGH_APEX");
        TransferHelper.safeTransferFrom(lpToken, msg.sender, address(this), amountIn);
        TransferHelper.safeTransfer(apeXToken, msg.sender, payout);
        emit Deposit(msg.sender, lpToken, amountIn, payout);
    }

    /// @notice Call this function can withdraw specified lp token to a policy contract
    /// @param lpToken The lp token address want to be withdraw
    /// @param policy The policy contract address to receive the lp token
    /// @param amount Withdraw amount of lp token
    /// @param data Other data want to send to the policy
    function withdraw(
        address lpToken,
        address policy,
        uint256 amount,
        bytes calldata data
    ) external override onlyOwner {
        require(isLiquidityToken[lpToken], "PCVTreasury.deposit: NOT_LIQUIDITY_TOKEN");
        require(policy != address(0), "PCVTreasury.deposit: ZERO_ADDRESS");
        require(amount > 0, "PCVTreasury.deposit: ZERO_AMOUNT");
        uint256 balance = IERC20(lpToken).balanceOf(address(this));
        require(amount <= balance, "PCVTreasury.deposit: NOT_ENOUGH_BALANCE");
        TransferHelper.safeTransfer(lpToken, policy, amount);
        IPCVPolicy(policy).execute(lpToken, amount, data);
        emit Withdraw(lpToken, policy, amount);
    }

    /// @notice left apeXToken in this contract can be granted out by owner
    /// @param to the address receive the apeXToken
    /// @param amount the amount want to be granted
    function grantApeX(address to, uint256 amount) external override onlyOwner {
        require(to != address(0), "PCVTreasury.grantApeX: ZERO_ADDRESS");
        require(amount > 0, "PCVTreasury.grantApeX: ZERO_AMOUNT");
        uint256 balance = IERC20(apeXToken).balanceOf(address(this));
        require(amount <= balance, "PCVTreasury.grantApeX: NOT_ENOUGH_BALANCE");
        TransferHelper.safeTransfer(apeXToken, to, amount);
        emit ApeXGranted(to, amount);
    }
}

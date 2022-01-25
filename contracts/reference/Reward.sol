// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../utils/Reentrant.sol";
import "../utils/Ownable.sol";
import "../libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Reward is Reentrant, Ownable {
    using ECDSA for bytes32;
    
    event SetEmergency(bool emergency);
    event SetSigner(address signer, bool state);
    event Claim(address user, uint256 amount, uint256 nonce);

    bool public emergency;
    address public rewardToken;
    mapping(address => bool) public signers;
    mapping(uint256 => bool) public usedNonce;

    constructor(address rewardToken_) {
        owner = msg.sender;
        rewardToken = rewardToken_;
    }

    function setSigner(address signer, bool state) external onlyOwner {
        require(signer != address(0), "ZERO_ADDRESS");
        signers[signer] = state;
        emit SetSigner(signer, state);
    }

    function setEmergency(bool emergency_) external onlyOwner {
        emergency = emergency_;
        emit SetEmergency(emergency_);
    }

    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        require(emergency, "NOT_EMERGENCY");
        TransferHelper.safeTransfer(token, to, amount);
    }

    function claim(
        address user,
        uint256 amount,
        uint256 nonce,
        uint256 expireAt,
        bytes memory signature
    ) external nonReentrant {
        require(!emergency, "EMERGENCY");
        verify(user, amount, nonce, expireAt, signature);
        usedNonce[nonce] = true;
        TransferHelper.safeTransfer(rewardToken, user, amount);
        emit Claim(user, amount, nonce);
    }

    function verify(
        address user,
        uint256 amount,
        uint256 nonce,
        uint256 expireAt,
        bytes memory signature
    ) public view returns (bool) {
        address recover = keccak256(
            abi.encode(user, amount, nonce, expireAt, address(this))
        ).toEthSignedMessageHash().recover(signature);
        require(signers[recover], "NOT_SIGNER");
        require(!usedNonce[nonce], "NONCE_USED");
        require(expireAt > block.timestamp, "EXPIRED");
        return true;
    }
}
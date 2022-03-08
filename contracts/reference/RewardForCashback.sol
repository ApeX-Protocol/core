// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../core/interfaces/IERC20.sol";
import "../utils/Reentrant.sol";
import "../utils/Ownable.sol";
import "../libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract RewardForCashback is Reentrant, Ownable {
    using ECDSA for bytes32;

    event SetEmergency(bool emergency);
    event SetSigner(address signer, bool state);
    event Claim(address indexed user, address[] tokens, uint256[] amounts, bytes nonce);

    address public WETH;
    bool public emergency;
    mapping(address => bool) public signers;
    mapping(bytes => bool) public usedNonce;

    constructor(address WETH_) {
        owner = msg.sender;
        WETH = WETH_;
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

    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(emergency, "NOT_EMERGENCY");
        TransferHelper.safeTransfer(token, to, amount);
    }

    function claim(
        address user,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata nonce,
        uint256 expireAt,
        bytes memory signature
    ) external nonReentrant {
        require(!emergency, "EMERGENCY");
        verify(user, tokens, amounts, nonce, expireAt, signature);
        usedNonce[nonce] = true;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == WETH) {
                TransferHelper.safeTransferETH(user, amounts[i]);
            } else {
                TransferHelper.safeTransfer(tokens[i], user, amounts[i]);
            }
        }
        emit Claim(user, tokens, amounts, nonce);
    }

    function verify(
        address user,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata nonce,
        uint256 expireAt,
        bytes memory signature
    ) public view returns (bool) {
        address recover = keccak256(abi.encode(user, tokens, amounts, nonce, expireAt, address(this)))
            .toEthSignedMessageHash()
            .recover(signature);
        require(signers[recover], "NOT_SIGNER");
        require(!usedNonce[nonce], "NONCE_USED");
        require(expireAt > block.timestamp, "EXPIRED");
        return true;
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../core/interfaces/IERC20.sol";
import "../utils/Reentrant.sol";
import "../utils/Ownable.sol";
import "../libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract NFTRebate is Reentrant, Ownable {
    using ECDSA for bytes32;

    event SetEmergency(bool emergency);
    event SetSigner(address signer, bool state);
    event Claim(address indexed user, bytes nonce, uint256 amount);

    uint256 public eachNFT;
    uint16 public maxCount;
    uint16 public claimedCount;
    
    mapping(address => bool) public signers;
    mapping(bytes => bool) public usedNonce;

    bool public emergency;

    constructor(uint256 eachNFT_, uint16 maxCount_) {
        owner = msg.sender;
        eachNFT = eachNFT_;
        maxCount = maxCount_;
    }
    
    receive() external payable { }

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
        address to,
        uint256 amount
    ) external onlyOwner {
        require(emergency, "NOT_EMERGENCY");
        TransferHelper.safeTransferETH(to, amount);
    }

    function claim(
        address user,
        uint16 count,
        bytes calldata nonce,
        bytes memory signature
    ) external nonReentrant {
        require(!emergency, "EMERGENCY");
        verify(user, count, nonce, signature);
        usedNonce[nonce] = true;
        uint256 amount = eachNFT * count;
        claimedCount += count;
        TransferHelper.safeTransferETH(user, amount);
        emit Claim(user, nonce, amount);
    }

    function verify(
        address user,
        uint16 count,
        bytes calldata nonce,
        bytes memory signature
    ) public view returns (bool) {
        address recover = keccak256(abi.encode(user, count, nonce, address(this)))
            .toEthSignedMessageHash()
            .recover(signature);
        require(signers[recover], "NOT_SIGNER");
        require(!usedNonce[nonce], "NONCE_USED");
        require(count <= maxCount - claimedCount, "OVER_COUNT");
        return true;
    }
}
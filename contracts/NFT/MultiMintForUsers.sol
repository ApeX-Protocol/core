// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./INftSquid.sol";

contract MultiMintForUsers {
    address public nftAddress;

    constructor(address nft) {
        nftAddress = nft;
    }

    function multiMint(uint256 amount) external payable  {
        require(amount <= 20, "mint amount exceed!");
        require(amount * 0.45 ether == msg.value, "amount not match");
        address to = msg.sender ; 
        for (uint256 i = 0; i < amount; i++) {
            INftSquid(nftAddress).claimApeXNFT{value: 0.45 ether}(i);
            uint256 id = INftSquid(nftAddress).tokenOfOwnerByIndex( address(this),0);
            INftSquid(nftAddress).transferFrom(address(this), to, id);
        }
    }
}

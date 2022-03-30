// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface INftSquid {
    // player can buy before startTime
    function claimApeXNFT(uint256 userSeed) external payable;

    function burnAndEarn(uint256 tokenId) external;
    
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function tokenOfOwnerByIndex(address owner, uint256 index) external view  returns (uint256);
}

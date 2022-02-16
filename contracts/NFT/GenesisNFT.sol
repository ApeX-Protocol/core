// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../core/interfaces/IERC20.sol";

contract GenesisNFT is ERC721PresetMinterPauserAutoId, Ownable {
  
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI
    ) ERC721PresetMinterPauserAutoId(_name, _symbol, _baseTokenURI) {
    }
}

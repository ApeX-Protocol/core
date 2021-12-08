pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";

contract ApeXNFT is ERC721PresetMinterPauserAutoId {
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI
    ) ERC721PresetMinterPauserAutoId(_name, _symbol, _baseTokenURI) {}
}

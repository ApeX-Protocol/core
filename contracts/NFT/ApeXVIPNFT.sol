pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ApeXVIPNFT is ERC721PresetMinterPauserAutoId, Ownable {
    uint256 public price = 40 ether;
    uint256 public totalEth = 0;
    uint256 public remainOwners = 20;
    uint256 public id = 0;
    uint256 public startTime;
    mapping(address => bool) public whitelist;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI,
        uint256 _startTime
    ) ERC721PresetMinterPauserAutoId(_name, _symbol, _baseTokenURI) {
        startTime = _startTime;
    }

    function addManyToWhitelist(address[] calldata _beneficiaries) external onlyOwner {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            whitelist[_beneficiaries[i]] = true;
        }
    }

    function removeFromWhitelist(address _beneficiary) external onlyOwner {
        whitelist[_beneficiary] = false;
    }

    function claimApeXVIPNFT() external payable isWhitelisted(msg.sender) {
        require(msg.value == price, "value not match");
        totalEth = totalEth + price;
        require(remainOwners > 0, "SOLD_OUT");
        _mint(msg.sender, id);
        require(block.timestamp >= startTime, "GAME_IS_ALREADY_BEGIN");
        id++;
        remainOwners--;
    }

    function withdrawETH(address to) public onlyOwner {
        payable(to).transfer(totalEth);
    }

    modifier isWhitelisted(address _beneficiary) {
        require(whitelist[_beneficiary]);
        _;
    }
}

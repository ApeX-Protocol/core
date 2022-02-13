// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../core/interfaces/IERC20.sol";

contract ApeXVIPNFT is ERC721PresetMinterPauserAutoId, Ownable {
    uint256 public totalEth;
    uint256 public remainOwners = 20;
    uint256 public id;

    mapping(address => bool) public whitelist;
    mapping(address => bool) public buyer;

    uint256 public startTime;
    uint256 public cliffTime;
    uint256 public endTime;
    // every buyer get
    uint256 public totalAmount = 1041666;
    // nft per price 
    // uint256 public price = 50 ether;
    uint256 public price = 0.01 ether; // for test
    mapping(address => uint256) public claimed;
    address public token;

    event Claimed(address indexed user, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI,
        address _token,
        uint256 _startTime,
        uint256 _cliff,
        uint256 _duration
    ) ERC721PresetMinterPauserAutoId(_name, _symbol, _baseTokenURI) {
        token = _token;
        startTime = _startTime;
        endTime = _startTime + _duration;
        cliffTime = _startTime + _cliff;
        _mint(msg.sender, id);
        id++;
    }

    function setTotalAmount(uint256 _totalAmount) external onlyOwner {
        totalAmount = _totalAmount;
    }

    function addManyToWhitelist(address[] calldata _beneficiaries) external onlyOwner {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            whitelist[_beneficiaries[i]] = true;
        }
    }

    function removeFromWhitelist(address _beneficiary) public onlyOwner {
        _removeFromWhitelist(_beneficiary);
    }

    function claimApeXVIPNFT() external payable isWhitelisted(msg.sender) {
        require(msg.value == price, "value not match");
        totalEth = totalEth + price;
        require(remainOwners > 0, "SOLD_OUT");
        _mint(msg.sender, id);
        require(block.timestamp <= startTime, "PLEASE_CLAIM_NFT_BEFORE_RELEASE_BEGIN");
        id++;
        remainOwners--;
        _removeFromWhitelist(msg.sender);
        buyer[msg.sender] = true;
    }

    function claimAPEX() external {
        address user = msg.sender;
        require(buyer[user], "ONLY_VIP_NFT_BUYER_CAN_CLAIM");

        uint256 unClaimed = claimableAmount(user);
        require(unClaimed > 0, "unClaimed_AMOUNT_MUST_BIGGER_THAN_ZERO");

        claimed[user] = claimed[user] + unClaimed;

        IERC20(token).transfer(user, unClaimed);

        emit Claimed(user, unClaimed);
    }

    function withdrawETH(address to) external onlyOwner {
        payable(to).transfer(address(this).balance);
    }

    function claimableAmount(address user) public view returns (uint256) {
        return vestedAmount() - (claimed[user]);
    }

    function vestedAmount() public view returns (uint256) {
        if (block.timestamp < cliffTime) {
            return 0;
        } else if (block.timestamp >= endTime) {
            return totalAmount;
        } else {
            return (totalAmount * (block.timestamp - cliffTime)) / (endTime - cliffTime);
        }
    }

    function _removeFromWhitelist(address _beneficiary) internal {
        whitelist[_beneficiary] = false;
    }

    modifier isWhitelisted(address _beneficiary) {
        require(whitelist[_beneficiary]);
        _;
    }
}

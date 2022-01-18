// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../core/interfaces/IERC20.sol";

contract ApeXVIPNFT is ERC721PresetMinterPauserAutoId, Ownable {
    uint256 constant nftMaxAmount = 20;
    uint256 public price = 40 ether;
    uint256 public id;
    mapping(address => bool) public whitelist;
    mapping(address => bool) public buyer;
    uint256 public startTime;
    uint256 public cliffTime;
    uint256 public endTime;
    uint256 public totalAmount;
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
        require(_cliff < _duration, "INVALID_CLIFF_OR_DURATION");
        token = _token;
        startTime = _startTime;
        cliffTime = _startTime + _cliff;
        endTime = _startTime + _duration;
    }

    function setTotalAmount(uint256 _totalAmount) external onlyOwner {
        totalAmount = _totalAmount;
    }

    function addToWhitelist(address[] calldata _beneficiaries) external onlyOwner {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            whitelist[_beneficiaries[i]] = true;
        }
    }

    function removeFromWhitelist(address[] calldata _beneficiaries) external onlyOwner {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            delete whitelist[_beneficiaries[i]];
        }
    }

    function withdrawETH(address to) external onlyOwner {
        payable(to).transfer(address(this).balance);
    }

    function claimApeXVIPNFT() external payable {
        require(whitelist[msg.sender], "WHITELIST");
        require(msg.value == price, "VALUE_NOT_MATCH");
        require(id < nftMaxAmount, "SOLD_OUT");
        require(block.timestamp <= startTime, "ENDED");
        _mint(msg.sender, id);

        id++;
        delete whitelist[msg.sender];
        buyer[msg.sender] = true;
    }

    function claimAPEX() external {
        address user = msg.sender;
        require(buyer[user], "ONLY_VIP_NFT_BUYER_CAN_CLAIM");

        uint256 claimable = _vestedAmount() - claimed[user];
        require(claimable > 0, "CLAIMABLE_AMOUNT_MUST_BIGGER_THAN_ZERO");

        claimed[user] = claimed[user] + claimable;

        IERC20(token).transfer(user, claimable);

        emit Claimed(user, claimable);
    }

    function claimableAmount(address user) external view returns (uint256) {
        return _vestedAmount() - claimed[user];
    }

    function vestedAmount() external view returns (uint256) {
        return _vestedAmount();
    }

    function _vestedAmount() internal view returns (uint256) {
        if (block.timestamp <= cliffTime) {
            return 0;
        } else if (block.timestamp >= endTime) {
            return totalAmount;
        } else {
            return (totalAmount * (block.timestamp - cliffTime)) / (endTime - cliffTime);
        }
    }
}

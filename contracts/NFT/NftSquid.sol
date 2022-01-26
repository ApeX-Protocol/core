// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../core/interfaces/IERC20.sol";

contract NftSquid is ERC721PresetMinterPauserAutoId, Ownable {
    uint256 private constant HALF_YEAR = 180 days;
    uint256 private constant MULTIPLIER = 1e18;
    uint256 internal constant BURN_DISCOUNT = 40;
    //todo
    uint256 internal constant BONUS_PERPAX = 1500 * 10**18;
    //todo
    uint256 internal constant BASE_AMOUNT = 3000 * 10**18;
    //todo
    uint256 public constant price = 0.001 ether;

    uint256 public vaultAmount;
    uint256 public startTime;

    //todo  <4560
    uint256 public remainOwners;
    
    uint256 public id;
    address public token;
    uint256 public totalEth;

    // reserved for whitelist address
    mapping(address => bool) public reserved;
    // left reserved that not claim yet
    uint16 public reservedCount;
    // if turn to false, then all reserved will become invalid
    bool public reservedOn = true;

    event Mint(address indexed owner, uint256 tokenId);
    event Burn(uint256 tokenId, uint256 withdrawAmount, address indexed sender);

    //"APEX NFT", "APEXNFT", "https://apexNFT/"
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI,
        address _token
    ) ERC721PresetMinterPauserAutoId(_name, _symbol, _baseTokenURI) {
        token = _token;
    }

    function setReservedOff() external onlyOwner {
        reservedOn = false;
    }

    function addToReserved(address[] memory list) external onlyOwner {
        require(block.timestamp < startTime, "GAME_ALREADY_START");
        for (uint16 i = 0; i < list.length; i++) {
            if (!reserved[list[i]]) {
                reserved[list[i]] = true;
                reservedCount++;
            }
        }
    }

    function removeFromReserved(address[] memory list) external onlyOwner {
        require(block.timestamp < startTime, "GAME_ALREADY_START");
        for (uint16 i = 0; i < list.length; i++) {
            if (reserved[list[i]]) {
                delete reserved[list[i]];
                reservedCount--;
            }
        }
    }

    // The time players are able to burn
    function setStartTime(uint256 _startTime) external onlyOwner {
        require(_startTime > block.timestamp, "START_TIME_MUST_BIGGER_THAN_NOW");
        startTime = _startTime; //unix time
    }

    // player can buy before startTime
    function claimApeXNFT() external payable {
        require(msg.value == price, "value not match");
        totalEth = totalEth + price;
        _mint(msg.sender, id);
        emit Mint(msg.sender, id);
        require(block.timestamp < startTime, "GAME_IS_ALREADY_BEGIN");
        id++;
        remainOwners++;
        require(remainOwners <= 5, "SOLD_OUT");
        if (reservedOn) {
            require(remainOwners <= 5 - reservedCount, "SOLD_OUT_NORMAL");
            if (reserved[msg.sender]) {
                delete reserved[msg.sender];
                reservedCount--;
            }
        }
    }

    // player burn their nft
    function burnAndEarn(uint256 tokenId) external {
        uint256 _remainOwners = remainOwners;
        require(_remainOwners > 0, "ALL_BURNED");
        require(ownerOf(tokenId) == msg.sender, "NO_AUTHORITY");
        require(startTime != 0 && block.timestamp >= startTime, "GAME_IS_NOT_BEGIN");
        _burn(tokenId);
        (uint256 withdrawAmount, uint256 bonus) = _calWithdrawAmountAndBonus();

        if (_remainOwners > 1) {
            vaultAmount =  vaultAmount + BONUS_PERPAX - bonus;
        }

        remainOwners = _remainOwners - 1;
        emit Burn(tokenId, withdrawAmount, msg.sender);
        require(IERC20(token).transfer(msg.sender, withdrawAmount));
    }

    function withdrawETH(address to) external onlyOwner {
        payable(to).transfer(address(this).balance);
    }

    function withdrawERC20Token(address to) external onlyOwner returns (bool) {
        require(IERC20(token).balanceOf(address(this)) >= 0);
        require(IERC20(token).transfer(to, IERC20(token).balanceOf(address(this))));
        return true;
    }

    function calWithdrawAmountAndBonus() external view returns (uint256 withdrawAmount, uint256 bonus) {
        return _calWithdrawAmountAndBonus();
    }

    function _calWithdrawAmountAndBonus() internal view returns (uint256 withdrawAmount, uint256 bonus) {
        uint256 endTime = startTime + HALF_YEAR;
        uint256 nowTime = block.timestamp;
        uint256 diffTime = nowTime < endTime ? nowTime - startTime : endTime - startTime;

        // the last one is special
        if (remainOwners == 1) {
            withdrawAmount = BASE_AMOUNT + BONUS_PERPAX + vaultAmount;
            return (withdrawAmount, BONUS_PERPAX + vaultAmount);
        }

        // (t/6*5000+ vaultAmount/N)60%
        bonus =
            (
                (diffTime * BONUS_PERPAX * (100 - BURN_DISCOUNT)) /HALF_YEAR +
                (vaultAmount * (100 - BURN_DISCOUNT)) /
                remainOwners) / 100;

        // drain the pool
        if ( bonus > vaultAmount + BONUS_PERPAX ) {
            bonus = vaultAmount + BONUS_PERPAX;
        }

        withdrawAmount = BASE_AMOUNT + bonus;
    }
}

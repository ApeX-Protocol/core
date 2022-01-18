// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../core/interfaces/IERC20.sol";

contract NftSquid is ERC721PresetMinterPauserAutoId, Ownable {
    uint256 private constant HALF_YEAR = 180 days;
    uint256 private constant MULTIPLIER = 1e18;
    uint256 public startTime;
    uint256 public existNftAmount;
    uint256 internal BONUS_PERPAX = 5000 * 10**18;
    uint256 internal BASE_AMOUNT = 10000 * 10**18;
    uint256 internal BURN_DISCOUNT = 40;
    uint256 public vault;
    //todo
    uint256 public price = 2.5 ether;
    address public token;

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

    // The time players are able to burn
    function setStartTime(uint256 _startTime) external onlyOwner {
        require(_startTime > block.timestamp, "START_TIME_MUST_BIGGER_THAN_NOW");
        startTime = _startTime; //unix time
    }

    function withdrawETH(address to, uint256 amount) external onlyOwner {
        payable(to).transfer(amount);
    }

    function withdrawERC20Token(address to, uint256 amount) external onlyOwner {
        uint256 _balance = IERC20(token).balanceOf(address(this));
        require(amount <= _balance && amount != 0, "nft.withdrawERC20Token: NO_ENOUGH_TOKEN");
        IERC20(token).transfer(to, amount);
    }

    // player can  buy before startTime
    function claimApeXNFT() external payable {
        require(msg.value == price, "value not match");
        require(block.timestamp < startTime, "GAME_IS_ALREADY_BEGIN");
        _mint(msg.sender, existNftAmount);
        existNftAmount++;
    }

    // player burn their nft
    function burnAndEarn(uint256 tokenId) external {
        require(existNftAmount > 0, "ALL_BURNED");
        require(ownerOf(tokenId) == msg.sender, "NO_AUTHORITY");
        require(startTime != 0 && block.timestamp >= startTime, "GAME_IS_NOT_BEGIN");
        _burn(tokenId);
        uint256 withdrawAmount = calculateWithdrawAmount();
        emit Burn(tokenId, withdrawAmount, msg.sender);
        IERC20(token).transfer(msg.sender, withdrawAmount);
    }

    function calculateWithdrawAmount() internal returns (uint256 withdrawAmount) {
        uint256 _startTime = startTime;
        uint256 endTime = _startTime + HALF_YEAR;
        uint256 nowTime = block.timestamp;
        require(nowTime >= _startTime, "NOT_STARTED");
        uint256 diffTime = nowTime < endTime ? nowTime - _startTime : endTime - _startTime;

        // the last one is special
        if (existNftAmount == 1) {
            withdrawAmount = BASE_AMOUNT + BONUS_PERPAX + vault;
            return withdrawAmount;
        }

        // (t/6*5000+ vault/N)60%
        uint256 bonus = (((diffTime * BONUS_PERPAX) / HALF_YEAR + vault / existNftAmount) * 60) / 100;

        withdrawAmount = BASE_AMOUNT + bonus;

        // vault += 5000-bonus (may negative)
        vault = vault + BONUS_PERPAX - bonus;
        existNftAmount = existNftAmount - 1;
    }
}

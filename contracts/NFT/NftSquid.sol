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
    uint256 public constant price = 0.45 ether;

    uint256 public vaultAmount;
    uint256 public squidStartTime;
    uint256 public nftStartTime;
    uint256 public nftEndTime;


    uint256 public remainOwners;
    uint256 public constant MAX_PLAYERS = 4560;

    uint256 public id;
    address public token;
    uint256 public totalEth;

    // reserved for whitelist address
    mapping(address => bool) public reserved;
    // left reserved that not claim yet
    uint16 public reservedCount;
    // if turn to false, then all reserved will become invalid
    bool public reservedOn = true;
    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    event Mint(address indexed owner, uint256 tokenId);
    event Burn(uint256 tokenId, uint256 withdrawAmount, address indexed sender);

    //"APEX NFT", "APEXNFT", "https://apexNFT/"
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI,
        address _token,
        uint256 _nftStartTime,
        uint256 _nftEndTime
    ) ERC721PresetMinterPauserAutoId(_name, _symbol, _baseTokenURI) {
        token = _token;
        nftStartTime = _nftStartTime;
        nftEndTime = _nftEndTime;
        _mint(msg.sender, MAX_PLAYERS);
    }

    function setReservedOff() external onlyOwner {
        reservedOn = false;
    }

    function addToReserved(address[] memory list) external onlyOwner {
        require(block.timestamp < nftEndTime, "NFT_SALE_TIME_END");
        for (uint16 i = 0; i < list.length; i++) {
            if (!reserved[list[i]]) {
                reserved[list[i]] = true;
                reservedCount++;
            }
        }
    }

    function removeFromReserved(address[] memory list) external onlyOwner {
        require(block.timestamp < nftEndTime, "NFT_SALE_TIME_END");
        for (uint16 i = 0; i < list.length; i++) {
            if (reserved[list[i]]) {
                delete reserved[list[i]];
                reservedCount--;
            }
        }
    }

    // The time players are able to burn
    function setSquidStartTime(uint256 _squidStartTime) external onlyOwner {
        require(_squidStartTime > nftEndTime, "SQUID_START_TIME_MUST_BIGGER_THAN_NFT_END_TIME");
        squidStartTime = _squidStartTime; //unix time
    }  
     function setNFTStartTime(uint256 _nftStartTime) external onlyOwner {
        require(_nftStartTime > block.timestamp, "NFT_START_TIME_MUST_BIGGER_THAN_NOW");
        nftStartTime = _nftStartTime; //unix time
    }  
     function setNFTEndTime(uint256 _nftEndTime) external onlyOwner {
        require(_nftEndTime > nftStartTime, "NFT_END_TIME_MUST_AFTER_START_TIME");
        nftEndTime = _nftEndTime; //unix time
    }

    // player can buy before startTime
    function claimApeXNFT(uint256 userSeed) external payable {
        require(msg.value == price, "value not match");
        totalEth = totalEth + price;
        uint256 randRaw = random(userSeed);
        uint256 rand = getUnusedRandom(randRaw);
        _mint(msg.sender, rand);
        _setClaimed(rand);
        emit Mint(msg.sender, rand);
        require(block.timestamp <= nftEndTime  , "GAME_IS_ALREADY_END");
        require(block.timestamp >= nftStartTime  , "GAME_IS_NOT_BEGIN");
        id++;
        remainOwners++;
        require(remainOwners <= MAX_PLAYERS, "SOLD_OUT");
        if (reservedOn) {
            require(remainOwners <= MAX_PLAYERS - reservedCount, "SOLD_OUT_NORMAL");
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
        require(squidStartTime != 0 && block.timestamp >= squidStartTime, "GAME_IS_NOT_BEGIN");
        _burn(tokenId);
        (uint256 withdrawAmount, uint256 bonus) = _calWithdrawAmountAndBonus();

        if (_remainOwners > 1) {
            vaultAmount = vaultAmount + BONUS_PERPAX - bonus;
        }

        remainOwners = _remainOwners - 1;
        emit Burn(tokenId, withdrawAmount, msg.sender);
        require(IERC20(token).transfer(msg.sender, withdrawAmount));
    }

    function random(uint256 userSeed) public view returns (uint256) {
        return
            uint256(keccak256(abi.encodePacked(block.timestamp, block.number, userSeed, blockhash(block.number)))) %
            MAX_PLAYERS;
    }

    function getUnusedRandom(uint256 randomNumber) internal view returns (uint256) {
        while (isClaimed(randomNumber)) {
            randomNumber++;
            if (randomNumber == MAX_PLAYERS) {
                randomNumber = randomNumber % MAX_PLAYERS;
            }
        }

        return randomNumber;
    }

    function isClaimed(uint256 index) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
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
        uint256 endTime = squidStartTime + HALF_YEAR;
        uint256 nowTime = block.timestamp;
        uint256 diffTime = nowTime < endTime ? nowTime - squidStartTime : endTime - squidStartTime;

        // the last one is special
        if (remainOwners == 1) {
            withdrawAmount = BASE_AMOUNT + BONUS_PERPAX + vaultAmount;
            return (withdrawAmount, BONUS_PERPAX + vaultAmount);
        }

        // (t/6*5000+ vaultAmount/N)60%
        bonus =
            ((diffTime * BONUS_PERPAX * (100 - BURN_DISCOUNT)) /
                HALF_YEAR +
                (vaultAmount * (100 - BURN_DISCOUNT)) /
                remainOwners) /
            100;

        // drain the pool
        if (bonus > vaultAmount + BONUS_PERPAX) {
            bonus = vaultAmount + BONUS_PERPAX;
        }

        withdrawAmount = BASE_AMOUNT + bonus;
    }
}

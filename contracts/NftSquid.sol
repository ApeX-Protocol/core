pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NftSquid is ERC721, Ownable {
    uint256 private constant NFT_COUNT = 456;
    uint256 private constant HALF_YEAR = 180 days;
    uint256 private constant MULTIPLIER = 1e18;
    uint256 public poolSizeReward;
    uint256 public startTime;
    uint256 public remainOwners = 456;
    uint256 internal bonusPerPax = 5000;
    uint256 internal burnDiscount = 40; //%
    uint256 internal lastBurnTime;
    uint256 internal lastBonus;

    constructor() ERC721("APEX NFT", "APEXNFT") {
        _mint(msg.sender, 0);
    }

    function setStartTime(uint256 _startTime) external onlyOwner {
        require(_startTime > block.timestamp, "INVALID_START_TIME");
        startTime = _startTime; //unix time
    }

    function burn(uint256 tokenId) external {
        require(remainOwners > 0, "ALL_BURNED");
        require(ownerOf(tokenId) == msg.sender, "NO_AUTHORITY");
        require(startTime != 0 && block.timestamp >= startTime, "NOT_STARTED");
        _burn(tokenId);
        update();
        //todo transfer (10000 * MULTIPLIER + lastBonus) ApeX
    }

    function update() internal {
        uint256 endTime = startTime + HALF_YEAR;
        uint256 nowTime = block.timestamp;
        uint256 diffTime = nowTime < endTime ? nowTime - startTime : endTime - startTime;
        if (remainOwners == NFT_COUNT) {
            poolSizeReward = (NFT_COUNT * bonusPerPax * MULTIPLIER * diffTime) / HALF_YEAR;
        } else {
            poolSizeReward =
                (poolSizeReward - lastBonus) +
                (bonusPerPax * MULTIPLIER * (endTime - lastBurnTime)) /
                HALF_YEAR +
                (remainOwners * bonusPerPax * MULTIPLIER * diffTime) /
                HALF_YEAR;
        }

        lastBonus = remainOwners == 1 ? poolSizeReward : (poolSizeReward * (100 - burnDiscount)) / remainOwners / 100;
        lastBurnTime = nowTime < endTime ? nowTime : endTime;
        remainOwners -= 1;
    }
}

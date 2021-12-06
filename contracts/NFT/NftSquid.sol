pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NftSquid is ERC721, Ownable {
    uint256 private constant HALF_YEAR = 180 days;
    uint256 private constant MULTIPLIER = 1e18;
    uint256 public poolSizeReward;
    uint256 public startTime;
    uint256 public remainOwners = 456;
    uint256 internal BONUS_PERPAX = 5000 * 10**18;
    uint256 internal BASE_AMOUNT = 10000 * 10**18;
    uint256 internal BURN_DISCOUNT = 40; 
    uint256 internal lastBurnTime;
    uint256 internal lastBonus;
    uint256 public vault;

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
        withdraw();
        //todo transfer (10000 * MULTIPLIER + lastBonus) ApeX
    }

    // function update() internal {
    //     uint256 endTime = startTime + HALF_YEAR;
    //     uint256 nowTime = block.timestamp;
    //     uint256 diffTime = nowTime < endTime ? nowTime - startTime : endTime - startTime;
    //     if (remainOwners == NFT_COUNT) {
    //         poolSizeReward = (NFT_COUNT * BONUS_PERPAX * MULTIPLIER * diffTime) / HALF_YEAR;
    //     } else {
    //         poolSizeReward =
    //             (poolSizeReward - lastBonus) +
    //             (BONUS_PERPAX * MULTIPLIER * (endTime - lastBurnTime)) /
    //             HALF_YEAR +
    //             (remainOwners * BONUS_PERPAX * MULTIPLIER * diffTime) /
    //             HALF_YEAR;
    //     }

    //     lastBonus = remainOwners == 1 ? poolSizeReward : (poolSizeReward * (100 - burnDiscount)) / remainOwners / 100;
    //     lastBurnTime = nowTime < endTime ? nowTime : endTime;
    //     remainOwners -= 1;
    // }


     function withdraw() internal returns (uint256 withdrawAmount) {
        uint256 endTime = startTime + HALF_YEAR;
        uint256 nowTime = block.timestamp;
        uint256 diffTime = nowTime < endTime ? nowTime - startTime : endTime - startTime;
        // (t/6*5000+ vault/N)60%
        uint256 bouns = (diffTime * BONUS_PERPAX /HALF_YEAR + vault / remainOwners)* 60/100;
        withdrawAmount = BASE_AMOUNT  + bouns;  
        // vault += 5000-bouns
        vault  = vault + (BONUS_PERPAX - bouns);
        remainOwners = remainOwners - 1;
    }
}

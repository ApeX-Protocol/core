pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../core/interfaces/IERC20.sol";

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
    uint256 public price = 0.01 ether;
    uint256 public id = 0;
    address token;

    event Burn(uint256 tokenId, uint256 withdrawAmount, address indexed sender);

    constructor(address _token) ERC721("APEX NFT", "APEXNFT") {
        // _mint(msg.sender, 0);
        token = _token;
    }

    function setStartTime(uint256 _startTime) external onlyOwner {
        require(_startTime > block.timestamp, "INVALID_START_TIME");
        startTime = _startTime; //unix time
    }

    function claimApeXNFT() external payable {
        require(msg.value == price);
        _mint(msg.sender, id);
        require(block.timestamp < startTime, "GAME_NOT_BEGIN");
        id++;
    }

    function burn(uint256 tokenId) external {
        require(remainOwners > 0, "ALL_BURNED");
        require(ownerOf(tokenId) == msg.sender, "NO_AUTHORITY");
        require(startTime != 0 && block.timestamp >= startTime, "NOT_STARTED");
        _burn(tokenId);
        uint256 withdrawAmount = withdraw();
        emit Burn(tokenId, withdrawAmount, msg.sender);
        require(IERC20(token).transfer(msg.sender, withdrawAmount));
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

    // todo 1. internal  2. burn unclaim
    function withdraw() public returns (uint256 withdrawAmount) {
        // unclaimed nft bouns given to the players
        // uint256 claimedAmount = id + 1;
        // vault = 5000 * (456 - claimedAmount);
        uint256 endTime = startTime + HALF_YEAR;
        uint256 nowTime = block.timestamp;
        uint256 diffTime = nowTime < endTime ? nowTime - startTime : endTime - startTime;

        // the last one is special
        if (remainOwners == 1) {
            withdrawAmount = BASE_AMOUNT + BONUS_PERPAX + vault;
            return withdrawAmount;
        }

        // (t/6*5000+ vault/N)60%
        uint256 bouns = (((diffTime * BONUS_PERPAX) / HALF_YEAR + vault / remainOwners) * 60) / 100;

        withdrawAmount = BASE_AMOUNT + bouns;

        // vault += 5000-bouns (may negative)
        vault = vault + BONUS_PERPAX - bouns;
        remainOwners = remainOwners - 1;
    }
}

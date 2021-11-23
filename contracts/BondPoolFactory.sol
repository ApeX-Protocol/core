pragma solidity ^0.8.0;

import "./interfaces/IBondPoolFactory.sol";
import "./utils/Ownable.sol";
import "./BondPool.sol";

contract BondPoolFactory is IBondPoolFactory, Ownable {
    address public immutable apeXToken;
    address public immutable treasury;
    address public immutable priceOracle;
    uint256 public maxPayout;
    uint256 public discount; // [0, 10000]
    uint256 public vestingTerm;

    address[] public allPools;

    constructor(
        address apeXToken_,
        address treasury_,
        address priceOracle_,
        uint256 maxPayout_,
        uint256 discount_,
        uint256 vestingTerm_
    ) {
        apeXToken = apeXToken_;
        treasury = treasury_;
        priceOracle = priceOracle_;
        maxPayout = maxPayout_;
        discount = discount_;
        vestingTerm = vestingTerm_;
    }

    function updateParams(
        uint256 maxPayout_,
        uint256 discount_,
        uint256 vestingTerm_
    ) external onlyAdmin {
        maxPayout = maxPayout_;
        discount = discount_;
        vestingTerm = vestingTerm_;
    }

    function createPool(address amm) external override onlyAdmin returns (address) {
        address pool = address(new BondPool(apeXToken, treasury, priceOracle, amm, maxPayout, discount, vestingTerm));
        allPools.push(pool);
        emit BondPoolCreated(amm, pool);
        return pool;
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BondPool.sol";
import "./interfaces/IBondPoolFactory.sol";
import "../utils/Ownable.sol";

contract BondPoolFactory is IBondPoolFactory, Ownable {
    address public immutable override apeXToken;
    address public immutable override treasury;
    address public override priceOracle;
    uint256 public override maxPayout;
    uint256 public override discount; // [0, 10000]
    uint256 public override vestingTerm;

    address[] public override allPools;
    // amm => pool
    mapping(address => address) public override getPool;

    constructor(
        address apeXToken_,
        address treasury_,
        address priceOracle_,
        uint256 maxPayout_,
        uint256 discount_,
        uint256 vestingTerm_
    ) {
        owner = msg.sender;
        apeXToken = apeXToken_;
        treasury = treasury_;
        priceOracle = priceOracle_;
        maxPayout = maxPayout_;
        discount = discount_;
        vestingTerm = vestingTerm_;
    }

    function setPriceOracle(address newOracle) external override {
        require(newOracle != address(0), "BondPoolFactory.setPriceOracle: ZERO_ADDRESS");
        priceOracle = newOracle;
    }

    function updateParams(
        uint256 maxPayout_,
        uint256 discount_,
        uint256 vestingTerm_
    ) external override onlyOwner {
        maxPayout = maxPayout_;
        require(discount_ <= 10000, "BondPoolFactory.updateParams: DISCOUNT_OVER_100%");
        discount = discount_;
        require(vestingTerm_ >= 129600, "BondPoolFactory.updateParams: MUST_BE_LONGER_THAN_36_HOURS");
        vestingTerm = vestingTerm_;
    }

    function createPool(address amm) external override onlyOwner returns (address) {
        require(getPool[amm] == address(0), "BondPoolFactory.createPool: POOL_EXIST");
        address pool = address(new BondPool(apeXToken, treasury, priceOracle, amm, maxPayout, discount, vestingTerm));
        getPool[amm] = pool;
        allPools.push(pool);
        emit BondPoolCreated(amm, pool);
        return pool;
    }

    function allPoolsLength() external view override returns (uint256) {
        return allPools.length;
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BondPool.sol";
import "./interfaces/IBondPoolFactory.sol";
import "./interfaces/IPCVTreasury.sol";
import "./interfaces/IBondPriceOracle.sol";
import "../utils/Ownable.sol";
import "../core/interfaces/IAmm.sol";

contract BondPoolFactory is IBondPoolFactory, Ownable {
    address public immutable override WETH;
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
        address WETH_,
        address apeXToken_,
        address treasury_,
        address priceOracle_,
        uint256 maxPayout_,
        uint256 discount_,
        uint256 vestingTerm_
    ) {
        owner = msg.sender;
        WETH = WETH_;
        apeXToken = apeXToken_;
        treasury = treasury_;
        priceOracle = priceOracle_;
        maxPayout = maxPayout_;
        discount = discount_;
        vestingTerm = vestingTerm_;
    }

    function setPriceOracle(address newOracle) external override onlyOwner {
        require(newOracle != address(0), "BondPoolFactory.setPriceOracle: ZERO_ADDRESS");
        emit PriceOracleUpdated(priceOracle, newOracle);
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
        require(amm != address(0), "BondPoolFactory.createPool: ZERO_ADDRESS");
        require(getPool[amm] == address(0), "BondPoolFactory.createPool: POOL_EXIST");
        address pool = address(new BondPool(owner, WETH, apeXToken, treasury, priceOracle, amm, maxPayout, discount, vestingTerm));
        getPool[amm] = pool;
        allPools.push(pool);
        address baseToken = IAmm(amm).baseToken();
        IBondPriceOracle(priceOracle).setupTwap(baseToken);
        emit BondPoolCreated(amm, pool);
        return pool;
    }

    function allPoolsLength() external view override returns (uint256) {
        return allPools.length;
    }
}

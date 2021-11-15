//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./interfaces/IStakingFactory.sol";
import "./interfaces/IPairFactory.sol";
import "./Staking.sol";

contract StakingFactory is IStakingFactory {
    address public override config;
    address public override pairFactory;
    mapping(address => address) public override getStaking;

    constructor(address config_, address pairFactory_) {
        config = config_;
        pairFactory = pairFactory_;
    }

    function createStaking(address baseToken, address quoteToken) external override returns (address staking) {
        address amm = IPairFactory(pairFactory).getAmm(baseToken, quoteToken);
        require(amm != address(0), "Factory: PAIR_NOT_EXIST");
        require(getStaking[amm] == address(0), "Factory: STAKING_EXIST");
        staking = address(new Staking(config, amm));
        getStaking[amm] = staking;
        emit NewStaking(baseToken, quoteToken, staking);
    }
}

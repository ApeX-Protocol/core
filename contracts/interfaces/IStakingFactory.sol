//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IStakingFactory {
    event NewStaking(address indexed baseToken, address indexed quoteToken, address indexed staking);

    function config() external view returns (address);

    function pairFactory() external view returns (address);

    function getStaking(address amm) external view returns (address);

    function createStaking(address baseToken, address quoteToken) external returns (address staking);
}

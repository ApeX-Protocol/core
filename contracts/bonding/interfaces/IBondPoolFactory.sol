pragma solidity ^0.8.0;

interface IBondPoolFactory {
    event BondPoolCreated(address indexed amm, address indexed pool);

    function createPool(address amm) external returns (address);
}

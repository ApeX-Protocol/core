// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IPairFactory {
    event NewPair(address indexed baseToken, address indexed quoteToken, address amm, address margin);

    function config() external view returns (address);

    function getAmm(address baseToken, address quoteToken) external view returns (address amm);

    function getMargin(address baseToken, address quoteToken) external view returns (address margin);

    function createPair(address baseToken, address quotoToken) external returns (address amm, address margin);
}

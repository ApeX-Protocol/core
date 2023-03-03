// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IArbSys {
    function arbBlockNumber() external view returns (uint256);
}

library ChainAdapter {
    address constant arbSys = address(100);

    function blockNumber() internal view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        if (chainId == 421611 || chainId == 42161) { // Arbitrum Testnet || Arbitrum Mainnet
            return IArbSys(arbSys).arbBlockNumber();
        } else {
            return block.number;
        }
    }
}
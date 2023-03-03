pragma solidity ^0.8.0;

contract MockArbSys {
    function arbBlockNumber() external view returns (uint256) {
        return block.number;
    }

    function blockTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    function getBlock() external view returns (uint256 number, uint256 timestamp) {
        number = block.number;
        timestamp = block.timestamp;
    }
}

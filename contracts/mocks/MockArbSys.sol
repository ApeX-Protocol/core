pragma solidity ^0.8.0;

contract MockArbSys {
    function arbBlockNumber() external view returns (uint256) {
        return block.number;
    }
}

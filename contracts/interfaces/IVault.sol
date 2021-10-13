// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IVault {
	function transferToReceiver(address _receiver, uint256 _amount) external;
}

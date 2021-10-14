// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Vault {
    IERC20 public token;
    address public margin;
    address public vAmm;

    event TransferToReceiver(address indexed receiver, uint256 amount);

    constructor(address baseToken, address _vAmm) {
        token = IERC20(baseToken);
        vAmm = _vAmm;
    }

    function setMargin(address _margin) external {
        margin = _margin;
    }

    function transferToReceiver(address _receiver, uint256 _amount)
        external
        vAmmOrMargin
    {
        token.transfer(_receiver, _amount);
        emit TransferToReceiver(_receiver, _amount);
    }

    modifier vAmmOrMargin() {
        require(msg.sender == margin || msg.sender == vAmm, "vAmm or margin");
        _;
    }
}

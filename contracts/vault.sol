// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Vault {
    IERC20 public immutable token;
    address public immutable margin;
    address public immutable vAmm;

    event TransferToReceiver(address indexed receiver, uint256 amount);

    constructor(
        address baseToken,
        address _margin,
        address _vAmm
    ) {
        token = IERC20(baseToken);
        margin = _margin;
        vAmm = _vAmm;
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

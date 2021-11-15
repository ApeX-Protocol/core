// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IMintableERC20.sol";

abstract contract ApexAware {
    address public apex;
    bool internal entered;

    modifier nonReentrant() {
        require(entered == false, "Reentrant: reentrant call");
        entered = true;
        _;
        entered = false;
    }

    function transferToken(address _to, uint256 _value) internal nonReentrant {
        IMintableERC20(apex).transferFrom(address(this), _to, _value);
    }

    function mintApex(address _to, uint256 _value) internal nonReentrant {
        IMintableERC20(apex).mint(_to, _value);
    }
}

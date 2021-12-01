// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../core/interfaces/IMintableERC20.sol";
import "./Reentrant.sol";

abstract contract ApeXAware is Reentrant {
    address public apeX;

    function transferApeX(
        address _from,
        address _to,
        uint256 _value
    ) internal nonReentrant {
        IERC20(apeX).transferFrom(_from, _to, _value);
    }

    function transferTo(address _to, uint256 _value) internal nonReentrant {
        IERC20(apeX).transfer(_to, _value);
    }
}

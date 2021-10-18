pragma solidity ^0.8.0;

import "../interfaces/IAmm.sol";

library AmmLibrary {
    // calculates the CREATE2 address for a amm without making any external calls
    function ammFor(
        address factory,
        address baseToken,
        address quoteToken
    ) internal pure returns (address amm) {
        amm = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        factory,
                        keccak256(abi.encodePacked(baseToken, quoteToken)),
                        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                    )
                )
            )
        );
    }
}

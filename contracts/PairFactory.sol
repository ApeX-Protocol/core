pragma solidity ^0.8.0;

import "./interfaces/IPairFactory.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IMargin.sol";
import "./Amm.sol";
import "./Margin.sol";

contract PairFactory is IPairFactory {
    address public override config;

    mapping(address => mapping(address => address)) public override getAmm;
    mapping(address => mapping(address => address)) public override getMargin;

    constructor(address _config) {
        config = _config;
    }

    function createPair(address baseToken, address quoteToken) external override returns (address amm, address margin) {
        require(baseToken != quoteToken, "Factory: IDENTICAL_ADDRESSES");
        require(baseToken != address(0) && quoteToken != address(0), "Factory: ZERO_ADDRESS");
        require(getAmm[baseToken][quoteToken] == address(0), "Factory: PAIR_EXIST");
        bytes32 salt = keccak256(abi.encodePacked(baseToken, quoteToken));
        bytes memory ammBytecode = type(Amm).creationCode;
        bytes memory marginBytecode = type(Margin).creationCode;
        assembly {
            amm := create2(0, add(ammBytecode, 32), mload(ammBytecode), salt)
            margin := create2(0, add(marginBytecode, 32), mload(marginBytecode), salt)
        }
        IAmm(amm).initialize(baseToken, quoteToken, config, margin);
        IMargin(margin).initialize(baseToken, quoteToken, config, amm);
        getAmm[baseToken][quoteToken] = amm;
        getMargin[baseToken][quoteToken] = margin;
        emit NewPair(baseToken, quoteToken, amm, margin);
    }
}

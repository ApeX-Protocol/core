pragma solidity ^0.8.0;

import "./Amm.sol";
import "./interfaces/IAmmFactory.sol";

contract AmmFactory is IAmmFactory {
    address public immutable override upperFactory;
    address public immutable override config;
    address public override feeTo;
    address public override feeToSetter;

    mapping(address => mapping(address => address)) public override getAmm;

    modifier onlyUpper() {
        require(msg.sender == upperFactory, "AmmFactory: FORBIDDEN");
        _;
    }

    constructor(
        address upperFactory_,
        address config_,
        address feeToSetter_
    ) {
        require(config_ != address(0) && feeToSetter_ != address(0), "AmmFactory: ZERO_ADDRESS");
        upperFactory = upperFactory_;
        config = config_;
        feeToSetter = feeToSetter_;
    }

    function createAmm(address baseToken, address quoteToken) external override onlyUpper returns (address amm) {
        require(baseToken != quoteToken, "AmmFactory.createAmm: IDENTICAL_ADDRESSES");
        require(baseToken != address(0) && quoteToken != address(0), "AmmFactory.createAmm: ZERO_ADDRESS");
        require(getAmm[baseToken][quoteToken] == address(0), "AmmFactory.createAmm: AMM_EXIST");
        bytes32 salt = keccak256(abi.encodePacked(baseToken, quoteToken));
        bytes memory ammBytecode = type(Amm).creationCode;
        assembly {
            amm := create2(0, add(ammBytecode, 32), mload(ammBytecode), salt)
        }
        getAmm[baseToken][quoteToken] = amm;
        emit AmmCreated(baseToken, quoteToken, amm);
    }

    function initAmm(
        address baseToken,
        address quoteToken,
        address margin
    ) external override onlyUpper {
        address amm = getAmm[baseToken][quoteToken];
        //fixme IAmm?
        Amm(amm).initialize(baseToken, quoteToken, margin);
    }

    function setFeeTo(address feeTo_) external override {
        require(msg.sender == feeToSetter, "AmmFactory.setFeeTo: FORBIDDEN");
        feeTo = feeTo_;
    }

    function setFeeToSetter(address feeToSetter_) external override {
        require(msg.sender == feeToSetter, "AmmFactory.setFeeToSetter: FORBIDDEN");
        feeToSetter = feeToSetter_;
    }
}

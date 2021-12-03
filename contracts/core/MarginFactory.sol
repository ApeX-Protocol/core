pragma solidity ^0.8.0;

import "./Margin.sol";
import "./interfaces/IMarginFactory.sol";

contract MarginFactory is IMarginFactory {
    address public immutable override upperFactory; // PairFactory
    address public immutable override config;

    // baseToken => quoteToken => margin
    mapping(address => mapping(address => address)) public override getMargin;

    modifier onlyUpper() {
        require(msg.sender == upperFactory, "AmmFactory: FORBIDDEN");
        _;
    }

    constructor(address upperFactory_, address config_) {
        require(config_ != address(0), "MarginFactory: ZERO_ADDRESS");
        upperFactory = upperFactory_;
        config = config_;
    }

    function createMargin(address baseToken, address quoteToken) external override onlyUpper returns (address margin) {
        require(baseToken != quoteToken, "MarginFactory.createMargin: IDENTICAL_ADDRESSES");
        require(baseToken != address(0) && quoteToken != address(0), "MarginFactory.createMargin: ZERO_ADDRESS");
        require(getMargin[baseToken][quoteToken] == address(0), "MarginFactory.createMargin: MARGIN_EXIST");
        bytes32 salt = keccak256(abi.encodePacked(baseToken, quoteToken));
        bytes memory marginBytecode = type(Margin).creationCode;
        assembly {
            margin := create2(0, add(marginBytecode, 32), mload(marginBytecode), salt)
        }
        getMargin[baseToken][quoteToken] = margin;
        emit MarginCreated(baseToken, quoteToken, margin);
    }

    function initMargin(
        address baseToken,
        address quoteToken,
        address amm
    ) external override onlyUpper {
        require(amm != address(0), "MarginFactory.initMargin: ZERO_AMM");
        address margin = getMargin[baseToken][quoteToken];
        require(margin != address(0), "MarginFactory.initMargin: ZERO_MARGIN");
        Margin(margin).initialize(baseToken, quoteToken, amm);
    }
}

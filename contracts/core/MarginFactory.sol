// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./Margin.sol";
import "../interfaces/IMarginFactory.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

//factory of margin, called by pairFactory
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
        require(upperFactory_ != address(0), "MarginFactory: ZERO_UPPER");
        require(config_ != address(0), "MarginFactory: ZERO_CONFIG");
        upperFactory = upperFactory_;
        config = config_;
    }

    function createMargin(address baseToken, address quoteToken, bytes memory marginBytecode, address proxyAdmin) external override onlyUpper returns (address proxyContract) {
        require(baseToken != quoteToken, "MarginFactory.createMargin: IDENTICAL_ADDRESSES");
        require(baseToken != address(0) && quoteToken != address(0), "MarginFactory.createMargin: ZERO_ADDRESS");
        require(getMargin[baseToken][quoteToken] == address(0), "MarginFactory.createMargin: MARGIN_EXIST");
        bytes32 salt = keccak256(abi.encodePacked(baseToken, quoteToken));
        // bytes memory marginBytecode = type(Margin).creationCode;
        address margin;
        assembly {
            margin := create2(0, add(marginBytecode, 32), mload(marginBytecode), salt)
        }
        proxyContract = address(new TransparentUpgradeableProxy(margin, proxyAdmin, ""));
        getMargin[baseToken][quoteToken] = proxyContract;
        emit MarginCreated(baseToken, quoteToken, margin, proxyContract, marginBytecode);
    }

    function initMargin(
        address baseToken,
        address quoteToken,
        address amm
    ) external override onlyUpper {
        require(amm != address(0), "MarginFactory.initMargin: ZERO_AMM");
        address margin = getMargin[baseToken][quoteToken];
        require(margin != address(0), "MarginFactory.initMargin: ZERO_MARGIN");
        IMargin(margin).initialize(baseToken, quoteToken, amm);
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IPairFactory.sol";
import "./interfaces/IAmmFactory.sol";
import "./interfaces/IMarginFactory.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IMargin.sol";
import "../utils/Ownable.sol";

contract PairFactory is IPairFactory, Ownable {
    address public override ammFactory;
    address public override marginFactory;

    constructor() {
        owner = msg.sender;
    }

    function init(address ammFactory_, address marginFactory_) external onlyOwner {
        require(ammFactory == address(0) && marginFactory == address(0), "PairFactory: ALREADY_INITED");
        require(ammFactory_ != address(0) && marginFactory_ != address(0), "PairFactory: ZERO_ADDRESS");
        ammFactory = ammFactory_;
        marginFactory = marginFactory_;
    }

    function createPair(address baseToken, address quoteToken) external override returns (address amm, address margin) {
        amm = IAmmFactory(ammFactory).createAmm(baseToken, quoteToken);
        margin = IMarginFactory(marginFactory).createMargin(baseToken, quoteToken);
        IAmmFactory(ammFactory).initAmm(baseToken, quoteToken, margin);
        IMarginFactory(marginFactory).initMargin(baseToken, quoteToken, amm);
        emit NewPair(baseToken, quoteToken, amm, margin);
    }

    function getAmm(address baseToken, address quoteToken) external view override returns (address) {
        return IAmmFactory(ammFactory).getAmm(baseToken, quoteToken);
    }

    function getMargin(address baseToken, address quoteToken) external view override returns (address) {
        return IMarginFactory(marginFactory).getMargin(baseToken, quoteToken);
    }
}

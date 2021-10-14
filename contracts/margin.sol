// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IVAmm} from "./interfaces/IVAmm.sol";
import {Math} from "./libraries/math.sol";
import {Decimal} from "./libraries/decimal.sol";
import {SignedDecimal} from "./libraries/signedDecimal.sol";

import "hardhat/console.sol";

contract Margin {
    using Decimal for uint256;
    using SignedDecimal for int256;

    struct Position {
        int256 quoteSize;
        int256 baseSize;
        int256 tradeSize;
    }

    IVAmm public vAmm;
    IERC20 public baseToken;
    IVault public vault;
    mapping(address => Position) public traderPositionMap;
    uint256 public initMarginRatio; //if 10, means margin ratio > 10%
    uint256 public liquidateThreshold; //if 100, means debt ratio < 100%
    uint256 public liquidateFeeRatio; //if 1, means liquidator bot get 1% as fee

    event AddMargin(address adder, address trader, uint256 depositAmount);
    event RemoveMargin(address trader, uint256 withdrawAmount);
    event OpenPosition(uint256 side, uint256 baseSize, uint256 marginAmount);

    constructor(
        address _baseToken,
        address _vAmm,
        address _vault,
        uint256 _initMarginRatio,
        uint256 _liquidateThreshold,
        uint256 _liquidateFeeRatio
    ) {
        vAmm = IVAmm(_vAmm);
        vault = IVault(_vault);
        initMarginRatio = _initMarginRatio;
        liquidateThreshold = _liquidateThreshold;
        liquidateFeeRatio = _liquidateFeeRatio;
        baseToken = IERC20(_baseToken);
    }

    // transferring token is in router.sol
    function addMargin(address _trader, uint256 _depositAmount) external {
        require(_depositAmount > 0, ">0");
        Position memory traderPosition = traderPositionMap[_trader];
        traderPosition.baseSize = traderPosition.baseSize.addU(_depositAmount);

        _setPosition(_trader, traderPosition);
        emit AddMargin(msg.sender, _trader, _depositAmount);
    }

    function removeMargin(uint256 _withdrawAmount) external {
        address _trader = msg.sender;
        Position memory traderPosition = traderPositionMap[_trader];

        if (traderPosition.quoteSize == 0) {
            require(
                traderPosition.baseSize > 0 &&
                    _withdrawAmount <= traderPosition.baseSize.abs(),
                "insufficient withdrawable"
            );
        }

        // check
        traderPosition.baseSize = traderPosition.baseSize.subU(_withdrawAmount);

        // important! check position health
        require(
            calMarginRatio(traderPosition.quoteSize, traderPosition.baseSize) >=
                initMarginRatio,
            "initMarginRatio"
        );
        _setPosition(_trader, traderPosition);

        vault.transferToReceiver(_trader, _withdrawAmount);

        emit RemoveMargin(_trader, _withdrawAmount);
    }

    function calMarginRatio(int256 quoteSize, int256 baseSize)
        public
        view
        returns (uint256)
    {
        if (quoteSize == 0) {
            return 100;
        } else if (baseSize == 0 && quoteSize < 0) {
            return 0;
        } else if (quoteSize > 0) {
            //calculate asset
            uint256 baseAmount = vAmm.getBaseWithMarkPrice(quoteSize.abs());
            return Math.minU(100, baseSize.divU(baseAmount).addU(100).abs());
        } else {
            //calculate debt
            uint256 baseAmount = vAmm.getBaseWithMarkPrice(quoteSize.abs());
            return uint256(100).sub(baseAmount.div(baseSize.abs()));
        }
    }

    function _setPosition(address _trader, Position memory _position) internal {
        traderPositionMap[_trader] = _position;
    }

    function setInitMarginRatio(uint256 _initMarginRatio) external {
        require(_initMarginRatio >= 10, "ratio >= 10");
        initMarginRatio = _initMarginRatio;
    }

    function setLiquidateThreshold(uint256 _liquidateThreshold) external {
        require(
            _liquidateThreshold > 90 && _liquidateThreshold <= 100,
            "90 < liquidateThreshold <= 100"
        );
        liquidateThreshold = _liquidateThreshold;
    }

    function setLiquidateFeeRatio(uint256 _liquidateFeeRatio) external {
        require(
            _liquidateFeeRatio > 0 && _liquidateFeeRatio <= 10,
            "0 < liquidateFeeRatio <= 10"
        );
        liquidateFeeRatio = _liquidateFeeRatio;
    }
}

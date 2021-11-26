// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IConfig.sol";
import "./utils/Initializable.sol";
import "./utils/Ownable.sol";

contract Config is IConfig, Ownable, Initializable {
    address public override priceOracle;

    uint256 public override rebasePriceGap;
    uint256 public override initMarginRatio; //if 1000, means margin ratio >= 10%
    uint256 public override liquidateThreshold; //if 10000, means debt ratio < 100%
    uint256 public override liquidateFeeRatio; //if 100, means liquidator bot get 1% as fee
    uint8 public override beta; // 50-200

    mapping(address => bool) public override routerMap;

    function initialize(address _admin, uint8 _beta) public initializer {
        admin = _admin;
        beta = _beta;
    }

    function setPriceOracle(address newOracle) external override onlyAdmin {
        require(newOracle != address(0), "Config: ZERO_ADDRESS");
        emit PriceOracleChanged(priceOracle, newOracle);
        priceOracle = newOracle;
    }

    function setRebasePriceGap(uint256 newGap) external override onlyAdmin {
        require(newGap > 0, "Config: ZERO_GAP");
        emit RebasePriceGapChanged(rebasePriceGap, newGap);
        rebasePriceGap = newGap;
    }

    function setInitMarginRatio(uint256 marginRatio) external override onlyAdmin {
        require(marginRatio >= 500, "ratio >= 500");
        initMarginRatio = marginRatio;
    }

    function setLiquidateThreshold(uint256 threshold) external override onlyAdmin {
        require(threshold > 9000 && threshold <= 10000, "9000 < liquidateThreshold <= 10000");
        liquidateThreshold = threshold;
    }

    function setLiquidateFeeRatio(uint256 feeRatio) external override onlyAdmin {
        require(feeRatio > 0 && feeRatio <= 2000, "0 < liquidateFeeRatio <= 2000");
        liquidateFeeRatio = feeRatio;
    }

   // todo
    function setBeta(uint8 newBeta) external override onlyAdmin {
        beta = newBeta;
    }

    function registerRouter(address router) external override onlyAdmin {
        require(router != address(0), "Config: ZERO_ADDRESS");
        routerMap[router] = true;
        emit RouterRegistered(router);
    }

    function unregisterRouter(address router) external override onlyAdmin {
        require(router != address(0), "Config: ZERO_ADDRESS");
        require(routerMap[router] == true, "Config: UNREGISTERED");
        delete routerMap[router];
        emit RouterUnregistered(router);
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

//config is upgradable proxy, contains configurations of core contracts
contract MockConfig {
    event PriceOracleChanged(address indexed oldOracle, address indexed newOracle);
    event RebasePriceGapChanged(uint256 oldGap, uint256 newGap);
    event TradingSlippageChanged(uint256 oldTradingSlippage, uint256 newTradingSlippage);
    event RouterRegistered(address indexed router);
    event RouterUnregistered(address indexed router);
    event SetLiquidateFeeRatio(uint256 oldLiquidateFeeRatio, uint256 liquidateFeeRatio);
    event SetLiquidateThreshold(uint256 oldLiquidateThreshold, uint256 liquidateThreshold);
    event SetInitMarginRatio(uint256 oldInitMarginRatio, uint256 initMarginRatio);
    event SetBeta(uint256 oldBeta, uint256 beta);
    event SetFeeParameter(uint256 oldFeeParameter, uint256 feeParameter);
    event SetMaxCPFBoost(uint256 oldMaxCPFBoost, uint256 maxCPFBoost);
    event SetLpWithdrawThreshold(uint256 oldLpWithdrawThreshold, uint256 lpWithdrawThreshold);

    address public priceOracle;

    uint256 public beta = 50; // 50-200，50 means 0.5
    uint256 public maxCPFBoost = 10; // default 10
    uint256 public rebasePriceGap = 5; //0-100 , if 5 means 5%
    uint256 public tradingSlippage = 5; //0-100, if 5 means 5%
    uint256 public initMarginRatio = 800; //if 1000, means margin ratio >= 10%
    uint256 public liquidateThreshold = 10000; //if 10000, means debt ratio < 100%
    uint256 public liquidateFeeRatio = 100; //if 100, means liquidator bot get 1% as fee
    uint256 public feeParameter = 11; // 100 * (1/fee-1)
    uint256 public swapFeeParameter = 999; // 
    uint256 public lpWithdrawThresholdForNet = 10; // 1-100
    uint256 public lpWithdrawThresholdForTotal = 50; 
    mapping(address => bool) public routerMap;

    // constructor() {
    //     owner = msg.sender;
    // }


    function setMaxCPFBoost(uint256 newMaxCPFBoost) external {
        emit SetMaxCPFBoost(maxCPFBoost, newMaxCPFBoost);
        maxCPFBoost = newMaxCPFBoost;
    }

    function setPriceOracle(address newOracle) external {
        require(newOracle != address(0), "Config: ZERO_ADDRESS");
        emit PriceOracleChanged(priceOracle, newOracle);
        priceOracle = newOracle;
    }

    function setRebasePriceGap(uint256 newGap) external {
        require(newGap > 0 && newGap < 100, "Config: ZERO_GAP");
        emit RebasePriceGapChanged(rebasePriceGap, newGap);
        rebasePriceGap = newGap;
    }

    function setTradingSlippage(uint256 newTradingSlippage) external {
        require(newTradingSlippage > 0 && newTradingSlippage < 100, "Config: TRADING_SLIPPAGE_RANGE_ERROR");
        emit TradingSlippageChanged(tradingSlippage, newTradingSlippage);
        tradingSlippage = newTradingSlippage;
    }

    function setInitMarginRatio(uint256 marginRatio) external {
        require(marginRatio >= 100, "Config: INVALID_MARGIN_RATIO");
        emit SetInitMarginRatio(initMarginRatio, marginRatio);
        initMarginRatio = marginRatio;
    }

    function setLiquidateThreshold(uint256 threshold) external {
        require(threshold > 9000 && threshold <= 10000, "Config: INVALID_LIQUIDATE_THRESHOLD");
        emit SetLiquidateThreshold(liquidateThreshold, threshold);
        liquidateThreshold = threshold;
    }

    function setLiquidateFeeRatio(uint256 feeRatio) external {
        require(feeRatio > 0 && feeRatio <= 2000, "Config: INVALID_LIQUIDATE_FEE_RATIO");
        emit SetLiquidateFeeRatio(liquidateFeeRatio, feeRatio);
        liquidateFeeRatio = feeRatio;
    }

    function setFeeParameter(uint256 newFeeParameter) external {
        emit SetFeeParameter(feeParameter, newFeeParameter);
        feeParameter = newFeeParameter;
    }

    function setBeta(uint8 newBeta) external {
        require(newBeta >= 50 && newBeta <= 200, "Config: INVALID_BETA");
        emit SetBeta(beta, newBeta);
        beta = newBeta;
    }

    //must be careful, expose all traders's position
    function registerRouter(address router) external {
        require(router != address(0), "Config: ZERO_ADDRESS");
        require(!routerMap[router], "Config: REGISTERED");
        routerMap[router] = true;

        emit RouterRegistered(router);
    }

    function unregisterRouter(address router) external {
        require(router != address(0), "Config: ZERO_ADDRESS");
        require(routerMap[router], "Config: UNREGISTERED");
        delete routerMap[router];

        emit RouterUnregistered(router);
    }

    function setLpWithdrawThresholdForNet(uint256 newLpWithdrawThresholdForNet) external {
        require(newLpWithdrawThresholdForNet > 1 && newLpWithdrawThresholdForNet <= 100, "Config: INVALID_LIQUIDATE_THRESHOLD");
        emit SetLpWithdrawThreshold(lpWithdrawThresholdForNet, newLpWithdrawThresholdForNet);
        lpWithdrawThresholdForNet = newLpWithdrawThresholdForNet;
    }

     function setLpWithdrawThresholdForTotal(uint256 newLpWithdrawThresholdForTotal) external {
      //  require(newLpWithdrawThresholdForTotal > 1 && newLpWithdrawThresholdForTotal <= 100, "Config: INVALID_LIQUIDATE_THRESHOLD");
        emit SetLpWithdrawThreshold(lpWithdrawThresholdForTotal, newLpWithdrawThresholdForTotal);
        lpWithdrawThresholdForTotal = newLpWithdrawThresholdForTotal;
    }

      function getMaxCPFBoost(address margin) external view  returns (uint256) {
        
        return maxCPFBoost;
    }

    function getInitMarginRatio(address margin) external view  returns (uint256) {
       
        return initMarginRatio;
    }

    function getLiquidateThreshold(address margin) external view  returns (uint256) {
      
        return liquidateThreshold;
    }

    function getLiquidateFeeRatio(address margin) external view  returns (uint256) {
       
        return liquidateFeeRatio;
    }

    function getRebasePriceGap(address amm) external view  returns (uint256) {
       
        return rebasePriceGap;
    
    }

    function getTradingSlippage(address amm) external view  returns (uint256) {
     
        return tradingSlippage;
    }


    function getBeta(address margin) external view  returns (uint256) {
        
        return beta;
    }

   
}

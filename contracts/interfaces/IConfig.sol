// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IConfig {
    event PriceOracleChanged(address indexed oldOracle, address indexed newOracle);
    event RouterRegistered(address indexed router);
    event RouterUnregistered(address indexed router);
    event SetEmergency(address indexed router);

    event SetRebasePriceGapDefault(uint256 oldGap, uint256 newGap);
    event SetRebaseIntervalDefault(uint256 oldInterval, uint256 newInterval);
    event SetTradingSlippageDefault(uint256 oldTradingSlippage, uint256 newTradingSlippage);
    event SetLiquidateFeeRatioDefault(uint256 oldLiquidateFeeRatio, uint256 newLiquidateFeeRatio);
    event SetLiquidateThresholdDefault(uint256 oldLiquidateThreshold, uint256 newLiquidateThreshold);
    event SetLpWithdrawThresholdForNetDefault(uint256 oldLpWithdrawThresholdForNet, uint256 newLpWithdrawThresholdForNet);
    event SetLpWithdrawThresholdForTotalDefault(uint256 oldLpWithdrawThresholdForTotal, uint256 newLpWithdrawThresholdForTotal);
    event SetInitMarginRatioDefault(uint256 oldInitMarginRatio, uint256 newInitMarginRatio);
    event SetBetaDefault(uint256 oldBeta, uint256 newBeta);
    event SetFeeParameterDefault(uint256 oldFeeParameter, uint256 newFeeParameter);
    event SetMaxCPFBoostDefault(uint256 oldMaxCPFBoost, uint256 newMaxCPFBoost);

    event SetMaxCPFBoostByMargin(address indexed margin, uint256 oldMaxCPFBoost, uint256 newMaxCPFBoost);
    event SetBetaByMargin(address indexed margin, uint256 oldBeta, uint256 newBeta);
    event SetInitMarginRatioByMargin(address indexed margin, uint256 oldInitMarginRatio, uint256 newInitMarginRatio);
    event SetLiquidateFeeRatioByMargin(address indexed margin, uint256 oldLiquidateFeeRatio, uint256 newLiquidateFeeRatio);
    event SetLiquidateThresholdByMargin(address indexed margin, uint256 oldLiquidateThreshold, uint256 newLiquidateThreshold);

    event SetFeeParameterByAmm(address indexed amm, uint256 oldFeeParameter, uint256 newFeeParameter);
    event SetLpWithdrawThresholdForNetByAmm(address indexed amm, uint256 oldLpWithdrawThresholdForNet, uint256 newLpWithdrawThresholdForNet);
    event SetLpWithdrawThresholdForTotalByAmm(address indexed amm, uint256 oldLpWithdrawThresholdForTotal, uint256 newLpWithdrawThresholdForTotal);
    event SetRebasePriceGapByAmm(address indexed amm, uint256 oldGap, uint256 newGap);
    event SetRebaseIntervalByAmm(address indexed amm, uint256 oldInterval, uint256 newInterval);
    event SetTradingSlippageByAmm(address indexed amm, uint256 oldTradingSlippage, uint256 newTradingSlippage);

    /// @notice get price oracle address.
    function priceOracle() external view returns (address);

    /// @notice get beta of amm.
    function beta() external view returns (uint8);

    /// @notice get feeParameter of amm.
    function feeParameter() external view returns (uint256);

    /// @notice get init margin ratio of margin.
    function initMarginRatio() external view returns (uint256);

    /// @notice get liquidate threshold of margin.
    function liquidateThreshold() external view returns (uint256);

    /// @notice get liquidate fee ratio of margin.
    function liquidateFeeRatio() external view returns (uint256);

    /// @notice get trading slippage  of amm.
    function tradingSlippage() external view returns (uint256);

    /// @notice get rebase gap of amm.
    function rebasePriceGap() external view returns (uint256);

    /// @notice get lp withdraw threshold of amm.
    function lpWithdrawThresholdForNet() external view returns (uint256);
  
    /// @notice get lp withdraw threshold of amm.
    function lpWithdrawThresholdForTotal() external view returns (uint256);

    function rebaseInterval() external view returns (uint256);

    function routerMap(address) external view returns (bool);

    function maxCPFBoost() external view returns (uint256);

    function inEmergency(address router) external view returns (bool);

    function betaByMargin(address margin) external view returns (uint256);
    function maxCPFBoostByMargin(address margin) external view returns (uint256);
    function initMarginRatioByMargin(address margin) external view returns (uint256);
    function liquidateThresholdByMargin(address margin) external view returns (uint256);
    function liquidateFeeRatioByMargin(address margin) external view returns (uint256);

    function rebasePriceGapByAmm(address amm) external view returns (uint256);
    function rebaseIntervalByAmm(address amm) external view returns (uint256);
    function tradingSlippageByAmm(address amm) external view returns (uint256);
    function lpWithdrawThresholdForNetByAmm(address amm) external view returns (uint256);
    function lpWithdrawThresholdForTotalByAmm(address amm) external view returns (uint256);
    function feeParameterByAmm(address amm) external view returns (uint256);

    function registerRouter(address router) external;
    function unregisterRouter(address router) external;

    /// @notice Set a new oracle
    /// @param newOracle new oracle address.
    function setPriceOracle(address newOracle) external;

    /// @notice Set a new beta of amm
    /// @param newBeta new beta.
    function setBeta(uint8 newBeta) external;

    /// @notice Set a new rebase gap of amm
    /// @param newGap new gap.
    function setRebasePriceGap(uint256 newGap) external;

    function setRebaseInterval(uint256 interval) external;

    /// @notice Set a new trading slippage of amm
    /// @param newTradingSlippage .
    function setTradingSlippage(uint256 newTradingSlippage) external;

    /// @notice Set a new init margin ratio of margin
    /// @param marginRatio new init margin ratio.
    function setInitMarginRatio(uint256 marginRatio) external;

    /// @notice Set a new liquidate threshold of margin
    /// @param threshold new liquidate threshold of margin.
    function setLiquidateThreshold(uint256 threshold) external;
  
     /// @notice Set a new lp withdraw threshold of amm net position
    /// @param newLpWithdrawThresholdForNet new lp withdraw threshold of amm.
    function setLpWithdrawThresholdForNet(uint256 newLpWithdrawThresholdForNet) external;
    
    /// @notice Set a new lp withdraw threshold of amm total position
    /// @param newLpWithdrawThresholdForTotal new lp withdraw threshold of amm.
    function setLpWithdrawThresholdForTotal(uint256 newLpWithdrawThresholdForTotal) external;

    /// @notice Set a new liquidate fee of margin
    /// @param feeRatio new liquidate fee of margin.
    function setLiquidateFeeRatio(uint256 feeRatio) external;

    /// @notice Set a new feeParameter.
    /// @param newFeeParameter New feeParameter get from AMM swap fee.
    /// @dev feeParameter = (1/fee -1 ) *100 where fee set by owner.
    function setFeeParameter(uint256 newFeeParameter) external;

    function setMaxCPFBoost(uint256 newMaxCPFBoost) external;

    function setEmergency(address router) external;

    function setMaxCPFBoostByMargin(address margin, uint256 newMaxCPFBoost) external;

    function setBetaByMargin(address margin, uint256 newBeta) external;

    function setInitMarginRatioByMargin(address margin, uint256 newInitMarginRatio) external;

    function setLiquidateFeeRatioByMargin(address margin, uint256 newLiquidateFeeRatio) external;

    function setLiquidateThresholdByMargin(address margin, uint256 newLiquidateThreshold) external;

    function setFeeParameterByAmm(address amm, uint256 newFeeParameter) external;

    function setLpWithdrawThresholdForNetByAmm(address amm, uint256 newLpWithdrawThresholdForNet) external;

    function setLpWithdrawThresholdForTotalByAmm(address amm, uint256 newLpWithdrawThresholdForTotal) external;

    function setRebasePriceGapByAmm(address amm, uint256 newGap) external;

    function setRebaseIntervalByAmm(address amm, uint256 newInterval) external;

    function setTradingSlippageByAmm(address amm, uint256 newTradingSlippage) external;
}

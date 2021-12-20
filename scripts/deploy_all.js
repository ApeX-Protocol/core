const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

// for PriceOracle
const v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; // UniswapV3Factory address
const v2FactoryAddress = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4"; // SushiV2Factory address
const wethAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44"; // mock WETH

// for Config
const beta = 100;
const initMarginRatio = 800;
const liquidateThreshold = 10000;
const liquidateFeeRatio = 100;
const rebasePriceGap = 5;
const feeParameter = 150;
const maxCPFBoost = 10;
const tradingSlippage = 5;
// transfer to pcvTreasury
const apeXAmountForBonding = 1000000000;
// for BondPoolFactory
const maxPayout = 100000000;
const discount = 500;
const vestingTerm = 129600;
// for StakingPoolFactory
const apeXPerBlock = 100;
const blocksPerUpdate = 2;
const initBlock = 6690016;
const endBlock = 7090016;

let signer;
let apeXToken;
let priceOracle;
let config;
let pairFactory;
let ammFactory;
let marginFactory;
let pcvTreasury;
let router;
let bondPoolFactory;
let stakingPoolFactory;

/// below variables only for testnet
let mockWETH;
let mockWBTC;
let mockUSDC;
let mockSHIB;
let ammAddress;
let marginAddress;
let bondPool;
let slpTokenAddress; // ApeX-XXX slp token from SushiSwap

const main = async () => {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  // await createApeXToken();
  await createPriceOracle();
  await createConfig();
  await createPairFactory();
  await createPCVTreasury();
  await createRouter();
  await createBondPoolFactory();
  // await createStakingPoolFactory();
  //// below only deploy for testnet
  // await createMockTokens();
  // await createMockPair();
  // await createMockBondPool();
  // await createMockStakingPool();
};

async function createApeXToken() {
  const ApeXToken = await ethers.getContractFactory("ApeXToken");
  apeXToken = await ApeXToken.deploy();
  console.log("ApeXToken:", apeXToken.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, apeXToken.address);
}

async function createPriceOracle() {
  const PriceOracle = await ethers.getContractFactory("PriceOracle");
  priceOracle = await PriceOracle.deploy(v3FactoryAddress, v2FactoryAddress, wethAddress);
  console.log("PriceOracle:", priceOracle.address);
  console.log(
    verifyStr,
    process.env.HARDHAT_NETWORK,
    priceOracle.address,
    v3FactoryAddress,
    v2FactoryAddress,
    wethAddress
  );
}

async function createConfig() {
  const Config = await ethers.getContractFactory("Config");
  config = await upgrades.deployProxy(Config, [signer]);
  console.log("Config:", config.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, config.address);

  // if (priceOracle == null) {
  //   let priceOracleAddress = "0x6fbe1c378Df494b5F66dd03491aA504d963eaD14";
  //   const PriceOracle = await ethers.getContractFactory("PriceOracle");
  //   priceOracle = await PriceOracle.attach(priceOracleAddress);
  // }
  await config.setPriceOracle(priceOracle.address);
  await config.setBeta(beta);
  await config.setInitMarginRatio(initMarginRatio);
  await config.setLiquidateThreshold(liquidateThreshold);
  await config.setLiquidateFeeRatio(liquidateFeeRatio);
  await config.setRebasePriceGap(rebasePriceGap);
  await config.setFeeParameter(feeParameter);
  await config.setMaxCPFBoost(maxCPFBoost);
  await config.setTradingSlippage(tradingSlippage);
}

async function createPairFactory() {
  if (config == null) {
    let configAddress = "0x7c51aB9Fa824857B688286eB75C86259E9b26eD0";
    const Config = await ethers.getContractFactory("Config");
    config = await Config.attach(configAddress);
  }

  const PairFactory = await ethers.getContractFactory("PairFactory");
  const AmmFactory = await ethers.getContractFactory("AmmFactory");
  const MarginFactory = await ethers.getContractFactory("MarginFactory");
  pairFactory = await PairFactory.deploy();
  ammFactory = await AmmFactory.deploy(pairFactory.address, config.address, signer);
  marginFactory = await MarginFactory.deploy(pairFactory.address, config.address);
  await pairFactory.init(ammFactory.address, marginFactory.address);
  console.log("PairFactory:", pairFactory.address);
  console.log("AmmFactory:", ammFactory.address);
  console.log("MarginFactory:", marginFactory.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, pairFactory.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, ammFactory.address, pairFactory.address, config.address, signer);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, marginFactory.address, pairFactory.address, config.address);
}

async function createPCVTreasury() {
  if (apeXToken == null) {
    let apeXTokenAddress = "0x4eB450a1f458cb60fc42B915151E825734d06dd8";
    const ApeXToken = await ethers.getContractFactory("ApeXToken");
    apeXToken = await ApeXToken.attach(apeXTokenAddress);
  }

  const PCVTreasury = await ethers.getContractFactory("PCVTreasury");
  pcvTreasury = await PCVTreasury.deploy(apeXToken.address);
  console.log("PCVTreasury:", pcvTreasury.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, pcvTreasury.address, apeXToken.address);

  // transfer apeX to pcvTreasury for bonding
  await apeXToken.transfer(pcvTreasury.address, apeXAmountForBonding);
}

async function createRouter() {
  if (pcvTreasury == null) {
    let pcvTreasuryAddress = "0xcb186F6bbB2Df145ff450ee0A4Ec6aF4baadEec7";
    const PCVTreasury = await ethers.getContractFactory("PCVTreasury");
    pcvTreasury = await PCVTreasury.attach(pcvTreasuryAddress);
  }

  const Router = await ethers.getContractFactory("Router");
  router = await Router.deploy(pairFactory.address, pcvTreasury.address, wethAddress);
  console.log("Router:", router.address);
  console.log(
    verifyStr,
    process.env.HARDHAT_NETWORK,
    router.address,
    pairFactory.address,
    pcvTreasury.address,
    wethAddress
  );

  // need to regiter router in config
  await config.registerRouter(router.address);
}

async function createBondPoolFactory() {
  const BondPoolFactory = await ethers.getContractFactory("BondPoolFactory");
  bondPoolFactory = await BondPoolFactory.deploy(
    apeXToken.address,
    pcvTreasury.address,
    priceOracle.address,
    maxPayout,
    discount,
    vestingTerm
  );
  console.log("BondPoolFactory:", bondPoolFactory.address);
  console.log(
    verifyStr,
    process.env.HARDHAT_NETWORK,
    bondPoolFactory.address,
    apeXToken.address,
    pcvTreasury.address,
    priceOracle.address,
    maxPayout,
    discount,
    vestingTerm
  );
}

async function createStakingPoolFactory() {
  const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
  stakingPoolFactory = await upgrades.deployProxy(StakingPoolFactory, [
    apeXToken.address,
    apeXPerBlock,
    blocksPerUpdate,
    initBlock,
    endBlock,
  ]);

  console.log("StakingPoolFactory:", stakingPoolFactory.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, stakingPoolFactory.address);
}

async function createMockTokens() {
  const MockWETH = await ethers.getContractFactory("MockWETH");
  mockWETH = await MockWETH.deploy();

  const MyToken = await ethers.getContractFactory("MyToken");
  mockWBTC = await MyToken.deploy("Mock WBTC", "mWBTC", 8, 21000000);
  mockUSDC = await MyToken.deploy("Mock USDC", "mUSDC", 6, 10000000000);
  mockSHIB = await MyToken.deploy("Mock SHIB", "mSHIB", 18, 999992012570472);
  console.log("mockWETH:", mockWETH.address);
  console.log("mockWBTC:", mockWBTC.address);
  console.log("mockUSDC:", mockUSDC.address);
  console.log("mockSHIB:", mockSHIB.address);
}

async function createMockPair() {
  let baseTokenAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44";
  let quoteTokenAddress = "0x3F12C33BDe6dE5B66F88D7a5d3CE8dE3C98b5FA7";

  if (pairFactory == null) {
    let pairFactoryAddress = "0x0b1D5459fa5B4EDBDd58c919e911149aCa56034E";

    const PairFactory = await ethers.getContractFactory("PairFactory");
    pairFactory = await PairFactory.attach(pairFactoryAddress);
  }

  await pairFactory.createPair(baseTokenAddress, quoteTokenAddress);
  ammAddress = await pairFactory.getAmm(baseTokenAddress, quoteTokenAddress);
  marginAddress = await pairFactory.getMargin(baseTokenAddress, quoteTokenAddress);

  console.log("Amm:", ammAddress);
  console.log("Margin:", marginAddress);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, ammAddress);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, marginAddress);
}

async function createMockBondPool() {
  ammAddress = "0xBbc6a04cBdDC8675b9F63c7DE47D225656Efa5F4";
  if (bondPoolFactory == null) {
    let bondPoolFactoryAddress = "0x03C295ff7f1Fe1085e9ceA827d5d7b7f8cA7c684";

    const BondPoolFactory = await ethers.getContractFactory("BondPoolFactory");
    bondPoolFactory = await BondPoolFactory.attach(bondPoolFactoryAddress);
  }
  await bondPoolFactory.createPool(ammAddress);
  let poolsLength = await bondPoolFactory.allPoolsLength();
  bondPool = await bondPoolFactory.allPools(poolsLength.toNumber() - 1);
  console.log("BondPool:", bondPool);
  // console.log(
  //   verifyStr,
  //   process.env.HARDHAT_NETWORK,
  //   bondPool.address,
  //   apeXToken.address,
  //   pcvTreasury.address,
  //   priceOracle.address,
  //   ammAddress,
  //   maxPayout,
  //   discount,
  //   vestingTerm
  // );
}

async function createMockStakingPool() {
  await stakingPoolFactory.createPool(apeXToken.address, 6690016, 21);
  await stakingPoolFactory.createPool(slpTokenAddress, 6690016, 79);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

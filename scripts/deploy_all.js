const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

// for PriceOracle
const v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; // UniswapV3Factory address
// const v2FactoryAddress = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4"; // SushiV2Factory address
const v2FactoryAddress = "0x0000000000000000000000000000000000000000";
const wethAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44"; // mock WETH

// transfer to pcvTreasury
const apeXAmountForBonding = BigNumber.from("1000000000000000000000000");
// for BondPoolFactory
const maxPayout = BigNumber.from("1000000000000000000000000");
const discount = 500;
const vestingTerm = 129600;
// for StakingPoolFactory
const apeXPerSec = BigNumber.from("100000000000000000000");
const secSpanPerUpdate = 30;
const initTimestamp = 1641781192;
const endTimestamp = 1673288342;
const lockTime = 15552000;
// transfer for staking
const apeXAmountForStaking = BigNumber.from("1000000000000000000000000");

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
let multicall2;

/// below variables only for testnet
let mockWETH;
let mockWBTC;
let mockUSDC;
let mockSHIB;
let ammAddress;
let marginAddress;
let bondPool;

const main = async () => {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  // await createApeXToken();
  // await createPriceOracle();
  // await createConfig();
  // await createPairFactory();
  // await createPCVTreasury();
  // await createRouter();
  // await createBondPoolFactory();
  await createStakingPoolFactory();
  // await createMulticall2();
  //// below only deploy for testnet
  // await createMockTokens();
  // await createMockPair();
  // await createMockBondPool();
  // await bond();
  await createMockStakingPool();
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
  config = await Config.deploy();
  console.log("Config:", config.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, config.address);

  if (priceOracle == null) {
    let priceOracleAddress = "0x15C20c6c673c3B2244b465FC7736eAA0E8bd6DF6";
    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    priceOracle = await PriceOracle.attach(priceOracleAddress);
  }
  await config.setPriceOracle(priceOracle.address);
}

async function createPairFactory() {
  if (config == null) {
    let configAddress = "0x1e4298C82061FAdd05096Ff04487A28E41820a94";
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
  if (pairFactory == null) {
    let pairFactoryAddress = "0x61Ef918F64665a499dFe9FDA667F96bE2B2E504B";
    const PairFactory = await ethers.getContractFactory("PairFactory");
    pairFactory = await PairFactory.attach(pairFactoryAddress);
  }
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
  if (config == null) {
    let configAddress = "0x7565D4B79f2e43Fb02770A075a749cad6a91C213";
    const Config = await ethers.getContractFactory("Config");
    config = await Config.attach(configAddress);
  }
  await config.registerRouter(router.address);
}

async function createBondPoolFactory() {
  let apeXAddress = "0x4eB450a1f458cb60fc42B915151E825734d06dd8";
  let pcvTreasuryAddress = "0xcb186F6bbB2Df145ff450ee0A4Ec6aF4baadEec7";
  if (priceOracle == null) {
    let priceOracleAddress = "0x15C20c6c673c3B2244b465FC7736eAA0E8bd6DF6";
    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    priceOracle = await PriceOracle.attach(priceOracleAddress);
  }
  const BondPoolFactory = await ethers.getContractFactory("BondPoolFactory");
  bondPoolFactory = await BondPoolFactory.deploy(
    apeXAddress,
    pcvTreasuryAddress,
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
    apeXAddress,
    pcvTreasuryAddress,
    priceOracle.address,
    maxPayout.toString(),
    discount,
    vestingTerm
  );
}

async function createStakingPoolFactory() {
  if (apeXToken == null) {
    let apeXTokenAddress = "0x4eB450a1f458cb60fc42B915151E825734d06dd8";
    const ApeXToken = await ethers.getContractFactory("ApeXToken");
    apeXToken = await ApeXToken.attach(apeXTokenAddress);
  }
  const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
  stakingPoolFactory = await StakingPoolFactory.deploy();
  await stakingPoolFactory.initialize(
    apeXToken.address,
    apeXPerSec,
    secSpanPerUpdate,
    initTimestamp,
    endTimestamp,
    lockTime
  );
  // stakingPoolFactory = await upgrades.deployProxy(StakingPoolFactory, [
  //   apeXToken.address,
  //   apeXPerBlock,
  //   secSpanPerUpdate,
  //   initTimestamp,
  //   endTimestamp,
  // ]);
  await apeXToken.transfer(stakingPoolFactory.address, apeXAmountForStaking);
  console.log("StakingPoolFactory:", stakingPoolFactory.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, stakingPoolFactory.address);
}

async function createMulticall2() {
  const Multicall2 = await ethers.getContractFactory("Multicall2");
  multicall2 = await Multicall2.deploy();
  console.log("Multicall2:", multicall2.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, multicall2.address);
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
  let quoteTokenAddress = "0x79dCF515aA18399CF8fAda58720FAfBB1043c526";

  if (pairFactory == null) {
    let pairFactoryAddress = "0x61Ef918F64665a499dFe9FDA667F96bE2B2E504B";

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
  ammAddress = "0xB6612a0355E99B359e91834B908f5616068633c1";
  if (bondPoolFactory == null) {
    let bondPoolFactoryAddress = "0x1efda03600f616e14251cf40eA157e4Ad66FE497";
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

async function bond() {
  if (bondPool == null) {
    let bondPoolAddress = "0x16BA8df5cF5B926BFBb5e1c9Aa9b688bE705616F";
    const BondPool = await ethers.getContractFactory("BondPool");
    bondPool = await BondPool.attach(bondPoolAddress);
  }
  if (pcvTreasury == null) {
    let pcvTreasuryAddress = "0xcb186F6bbB2Df145ff450ee0A4Ec6aF4baadEec7";
    let PCVTreasury = await ethers.getContractFactory("PCVTreasury");
    pcvTreasury = await PCVTreasury.attach(pcvTreasuryAddress);
  }
  let ammAddress = "0xB6612a0355E99B359e91834B908f5616068633c1";
  await pcvTreasury.addLiquidityToken(ammAddress);
  await pcvTreasury.addBondPool(bondPool.address);

  const MockWETH = await ethers.getContractFactory("MockWETH");
  const weth = await MockWETH.attach("0x655e2b2244934Aea3457E3C56a7438C271778D44");
  await weth.approve(bondPool.address, BigNumber.from("10000000000000000000000000000000").toString());
  await bondPool.deposit(signer, BigNumber.from("1000000000000000").toString(), 1);
  let bondInfo = await bondPool.bondInfoFor(signer);
  console.log("payout:", bondInfo.payout.toString());
}

async function createMockStakingPool() {
  if (stakingPoolFactory == null) {
    let stakingPoolFactoryAddress = "0x5B0Fafe5FbE2F51dD0EaC053630CF896B2Ef4943";
    const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
    stakingPoolFactory = await StakingPoolFactory.attach(stakingPoolFactoryAddress);
  }
  let apeXTokenAddress = "0x4eB450a1f458cb60fc42B915151E825734d06dd8";
  let slpTokenAddress = "0x2deeEa765219E3452143Dfb53c270fCa4486bc45"; // ApeX-XXX slp token from SushiSwap
  await stakingPoolFactory.createPool(apeXTokenAddress, initTimestamp, 21);
  await stakingPoolFactory.createPool(slpTokenAddress, initTimestamp, 79);
  let apeXPool = await stakingPoolFactory.getPoolAddress(apeXTokenAddress);
  let slpPool = await stakingPoolFactory.getPoolAddress(slpTokenAddress);
  console.log("apeXPool:", apeXPool);
  console.log("slpPool:", slpPool);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

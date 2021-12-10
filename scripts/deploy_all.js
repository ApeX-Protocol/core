const { ethers, upgrades } = require("hardhat");
const verifyStr = "npx hardhat verify --network";

// for PriceOracle
const v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; // UniswapV3Factory address
const v2FactoryAddress = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4"; // SushiV2Factory address
const wethAddress = "0xc778417E063141139Fce010982780140Aa0cD5Ab";
// for Config
const beta = 100;
const initMarginRatio = 800;
const liquidateThreshold = 10000;
const liquidateFeeRatio = 100;
const rebasePriceGap = 1;
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
let mockWBTC;
let mockUSDC;
let ammAddress;
let marginAddress;
let bondPool;
let slpTokenAddress; // ApeX-XXX slp token from SushiSwap

const main = async () => {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  await createApeXToken();
  await createPriceOracle();
  await createConfig();
  await createPairFactory();
  await createPCVTreasury();
  await createRouter();
  await createBondPoolFactory();
  await createStakingPoolFactory();
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
  config = await upgrades.deployProxy(Config, [signer]); // Sometimes would get timed out for deployProxy
  console.log("Config:", config.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, config.address);

  await config.setPriceOracle(priceOracle.address);
  await config.setBeta(beta);
  await config.setInitMarginRatio(initMarginRatio);
  await config.setLiquidateThreshold(liquidateThreshold);
  await config.setLiquidateFeeRatio(liquidateFeeRatio);
  await config.setRebasePriceGap(rebasePriceGap);
}

async function createPairFactory() {
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
  const PCVTreasury = await ethers.getContractFactory("PCVTreasury");
  pcvTreasury = await PCVTreasury.deploy(apeXToken.address);
  console.log("PCVTreasury:", pcvTreasury.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, pcvTreasury.address, apeXToken.address);

  // transfer apeX to pcvTreasury for bonding
  await apeXToken.transfer(pcvTreasury.address, apeXAmountForBonding);
}

async function createRouter() {
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
  const MyToken = await ethers.getContractFactory("MyToken");
  mockWBTC = await MyToken.deploy("Mock WBTC", "mWBTC", 8, 100000000);
  mockUSDC = await MyToken.deploy("Mock USDC", "mUSDC", 6, 100000000);
  console.log("mockWBTC:", mockWBTC.address);
  console.log("mockUSDC:", mockUSDC.address);
}

async function createMockPair() {
  let mWBTCAddress = "0x7aBF19CE8696A1D8945F9125758EbCe2F6F0Fd91";
  let mUSDCAddress = "0x1b3631A99A69275bC7E3b539FeD4DaAFaDDfe1B0";

  if (pairFactory == null) {
    let pairFactoryAddress = "0x68a8eA940ce9609D814D5A600AEd615E86F7484D";
    const PairFactory = await ethers.getContractFactory("PairFactory");
    pairFactory = await PairFactory.attach(pairFactoryAddress);
  }

  // await pairFactory.createPair(mWBTCAddress, mUSDCAddress);
  ammAddress = await pairFactory.getAmm(mWBTCAddress, mUSDCAddress);
  marginAddress = await pairFactory.getMargin(mWBTCAddress, mUSDCAddress);
  console.log("Amm:", ammAddress);
  console.log("Margin:", marginAddress);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, ammAddress);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, marginAddress);
}

async function createMockBondPool() {
  ammAddress = "0x0f983CDD6E009431785e9d1c713012097efEc55B";
  if (bondPoolFactory == null) {
    let bondPoolFactoryAddress = "0x328D33Eda5bd664B3345e7e1D235e78B5FF44354";
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

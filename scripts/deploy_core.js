const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

//// prod
// const apeXTokenAddress = "0x61A1ff55C5216b636a294A07D77C6F4Df10d3B56"; // Layer2 ApeX Token
// const v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; // UniswapV3Factory address
// const wethAddress = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1"; // WETH address in ArbitrumOne

// test
const apeXTokenAddress = "0x3f355c9803285248084879521AE81FF4D3185cDD"; // testnet apex token
const v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; // testnet uniV3factory
const wethAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44"; // mockWETH

let signer;
let apeXToken;
let priceOracle;
let config;
let pairFactory;
let ammFactory;
let marginFactory;
let pcvTreasury;
let router;
let multicall2;

/// below variables only for testnet
let mockWETH;
let mockWBTC;
let mockUSDC;
let mockSHIB;
let ammAddress;
let marginAddress;

const main = async () => {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  await attachApeXToken();
  await createPriceOracle();
  await createConfig();
  await createPairFactory();
  // await createPCVTreasury();
  await createRouter();
  // await createMulticall2();
  //// below only deploy for testnet
  // await createMockTokens();
  await createPair();
};

async function attachApeXToken() {
  const ApeXToken = await ethers.getContractFactory("ApeXToken");
  apeXToken = await ApeXToken.attach(apeXTokenAddress);
  console.log("ApeXToken:", apeXToken.address);
}

async function createPriceOracle() {
  const PriceOracle = await ethers.getContractFactory("PriceOracle");
  priceOracle = await PriceOracle.deploy();
  await priceOracle.initialize(wethAddress, v3FactoryAddress);
  console.log("PriceOracle:", priceOracle.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, priceOracle.address);

  // priceOracle = await upgrades.deployProxy(PriceOracle, [wethAddress, v3FactoryAddress]);
  // console.log("PriceOracle:", priceOracle.address);

  // if (config == null) {
  //   const Config = await ethers.getContractFactory("Config");
  //   config = await Config.attach("0xBfE1B5d8F2719Ce143b88B7727ACE0af893B7f26");
  //   config.setPriceOracle(priceOracle.address);
  // }
}

async function createConfig() {
  const Config = await ethers.getContractFactory("Config");
  config = await Config.deploy();
  console.log("Config:", config.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, config.address);

  // if (priceOracle == null) {
  //   let priceOracleAddress = "0x901F48Cf42406D4b4201435217E27C40d364D44B";
  //   const PriceOracle = await ethers.getContractFactory("PriceOracle");
  //   priceOracle = await PriceOracle.attach(priceOracleAddress);
  // }
  await config.setPriceOracle(priceOracle.address);
}

async function createPairFactory() {
  // if (config == null) {
  //   let configAddress = "0xF1D5FC94A3cA88644E0D05195fbb2db1E60B9e75";
  //   const Config = await ethers.getContractFactory("Config");
  //   config = await Config.attach(configAddress);
  // }

  const PairFactory = await ethers.getContractFactory("PairFactory");
  const AmmFactory = await ethers.getContractFactory("AmmFactory");
  const MarginFactory = await ethers.getContractFactory("MarginFactory");
  pairFactory = await PairFactory.deploy();
  ammFactory = await AmmFactory.deploy(pairFactory.address, config.address, signer);
  marginFactory = await MarginFactory.deploy(pairFactory.address, config.address);
  await pairFactory.init(ammFactory.address, marginFactory.address);
  console.log("PairFactory:", pairFactory.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, pairFactory.address);
  console.log("AmmFactory:", ammFactory.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, ammFactory.address, pairFactory.address, config.address, signer);
  console.log("MarginFactory:", marginFactory.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, marginFactory.address, pairFactory.address, config.address);
}

async function createPCVTreasury() {
  const PCVTreasury = await ethers.getContractFactory("PCVTreasury");
  pcvTreasury = await PCVTreasury.deploy(apeXToken.address);
  console.log("PCVTreasury:", pcvTreasury.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, pcvTreasury.address, apeXToken.address);

  // transfer apeX to pcvTreasury for bonding
  // await apeXToken.transfer(pcvTreasury.address, apeXAmountForBonding);
}

async function createRouter() {
  // if (config == null) {
  //   let configAddress = "0xC69d007331957808B215e7f42d645FF439f16b47";
  //   const Config = await ethers.getContractFactory("Config");
  //   config = await Config.attach(configAddress);
  // }
  // if (pairFactory == null) {
  //   let pairFactoryAddress = "0xA2A21Cb14EF952334e993F79c8017Eb09031dF51";
  //   const PairFactory = await ethers.getContractFactory("PairFactory");
  //   pairFactory = await PairFactory.attach(pairFactoryAddress);
  // }
  if (pcvTreasury == null) {
    let pcvTreasuryAddress = "0x42C0E0fdA16CE20C3c15bBF666Ee79EaB5998F20";
    const PCVTreasury = await ethers.getContractFactory("PCVTreasury");
    pcvTreasury = await PCVTreasury.attach(pcvTreasuryAddress);
  }

  const Router = await ethers.getContractFactory("Router");
  router = await Router.deploy();
  await router.initialize(config.address, pairFactory.address, pcvTreasury.address, wethAddress);
  console.log("Router:", router.address);
  console.log(
    verifyStr,
    process.env.HARDHAT_NETWORK,
    router.address,
    config.address,
    pairFactory.address,
    pcvTreasury.address,
    wethAddress
  );

  router = await upgrades.deployProxy(Router, [config.address, pairFactory.address, pcvTreasury.address, wethAddress]);
  await config.registerRouter(router.address);
  console.log("Router:", router.address);
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

async function createPair() {
  // let baseTokenAddress = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1"; // WETH in ArbitrumOne
  // let quoteTokenAddress = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"; // USDC in ArbitrumOne
  let baseTokenAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44"; // mockWETH in testnet
  let quoteTokenAddress = "0x79dCF515aA18399CF8fAda58720FAfBB1043c526"; // mockUSDC in testnet

  if (pairFactory == null) {
    let pairFactoryAddress = "0x125A70fDa17D69b364cD67200E0df3417dBb7869";
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

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

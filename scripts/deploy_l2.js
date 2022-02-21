const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

const apeXTokenAddress = "0x3f355c9803285248084879521AE81FF4D3185cDD"; // Layer2 ApeX Token
// for PriceOracle
const v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; // UniswapV3Factory address
// const v2FactoryAddress = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4"; // SushiV2Factory address
const v2FactoryAddress = "0x9ef193943E14D83BcdAD9e3d782DBafA93bd25A1"; // Self deploy UniswapV2Factory address
const wethAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44"; // mock WETH
const usdcAddress = "0x79dCF515aA18399CF8fAda58720FAfBB1043c526"; // mock USDC

// transfer to pcvTreasury
const apeXAmountForBonding = BigNumber.from("1000000000000000000000000");
// for BondPoolFactory
const maxPayout = BigNumber.from("1000000000000000000000000");
const discount = 500;
const vestingTerm = 129600;
// for StakingPoolFactory
const apeXPerSec = BigNumber.from("100000000000000000");
const secSpanPerUpdate = 30;
const initTimestamp = 1641781192;
const endTimestamp = 1673288342;
// const lockTime = 15552000;
const lockTime = 120;
// transfer for staking
const apeXAmountForStaking = BigNumber.from("10000000000000000000000");
const apeXAmountForReward = BigNumber.from("10000000000000000000000");

let signer;
let apeXToken;
let priceOracle;
let config;
let pairFactory;
let ammFactory;
let marginFactory;
let pcvTreasury;
let router;
let bondPriceOracle;
let bondPoolFactory;
let stakingPoolFactory;
let invitation;
let reward;
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
  await attachApeXToken();
  // await createPriceOracle();
  // await createConfig();
  // await createPairFactory();
  // await createPCVTreasury();
  // await createRouter();
  // await createBondPriceOracle();
  // await createBondPoolFactory();
  // await createStakingPoolFactory();
  // await createInvitation();
  // await createReward();
  // await createMulticall2();
  //// below only deploy for testnet
  // await createMockTokens();
  // await createPairForVerify();
  // await createMockPair();
  // await createMockBondPool();
  await bond();
  // await createMockStakingPool();
};

async function attachApeXToken() {
  const ApeXToken = await ethers.getContractFactory("ApeXToken");
  apeXToken = await ApeXToken.attach(apeXTokenAddress);
  console.log("ApeXToken:", apeXToken.address);
}

async function createPriceOracle() {
  const PriceOracle = await ethers.getContractFactory("PriceOracle");
  priceOracle = await PriceOracle.deploy();
  await priceOracle.initialize(v3FactoryAddress);
  console.log("PriceOracle:", priceOracle.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, priceOracle.address);
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

async function createBondPriceOracle() {
  const BondPriceOracle = await ethers.getContractFactory("BondPriceOracle");
  bondPriceOracle = await BondPriceOracle.deploy();
  await bondPriceOracle.initialize(apeXToken.address, wethAddress, v3FactoryAddress, v2FactoryAddress);
  await bondPriceOracle.setupTwap(usdcAddress);
  console.log("BondPriceOracle:", bondPriceOracle.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, bondPriceOracle.address);
}

async function createBondPoolFactory() {
  let pcvTreasuryAddress = "0x42C0E0fdA16CE20C3c15bBF666Ee79EaB5998F20";
  if (pcvTreasury != null) {
    pcvTreasuryAddress = pcvTreasury.address;
  }
  if (bondPriceOracle == null) {
    let priceOracleAddress = "0x076A33AAc2fC3664dceF2AD33f414d485E4Ae898";
    const BondPriceOracle = await ethers.getContractFactory("BondPriceOracle");
    bondPriceOracle = await BondPriceOracle.attach(priceOracleAddress);
  }
  const BondPoolFactory = await ethers.getContractFactory("BondPoolFactory");
  bondPoolFactory = await BondPoolFactory.deploy(
    wethAddress,
    apeXToken.address,
    pcvTreasuryAddress,
    bondPriceOracle.address,
    maxPayout,
    discount,
    vestingTerm
  );
  console.log("BondPoolFactory:", bondPoolFactory.address);
  console.log(
    verifyStr,
    process.env.HARDHAT_NETWORK,
    wethAddress,
    bondPoolFactory.address,
    apeXToken.address,
    pcvTreasuryAddress,
    bondPriceOracle.address,
    maxPayout.toString(),
    discount,
    vestingTerm
  );
}

async function createStakingPoolFactory() {
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

async function createInvitation() {
  const Invitation = await ethers.getContractFactory("Invitation");
  invitation = await Invitation.deploy();
  console.log("Invitation:", invitation.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, invitation.address);
}

async function createReward() {
  const Reward = await ethers.getContractFactory("Reward");
  reward = await Reward.deploy(apeXToken.address);
  console.log("Reward:", reward.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, reward.address, apeXToken.address);
  await apeXToken.transfer(reward.address, apeXAmountForReward);
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

async function createPairForVerify() {
  let Amm = await ethers.getContractFactory("Amm");
  let Margin = await ethers.getContractFactory("Margin");
  let amm = await Amm.deploy();
  let margin = await Margin.deploy();
  console.log("AmmForVerify:", amm.address);
  console.log("MarginForVerify:", margin.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, amm.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, margin.address);
}

async function createMockPair() {
  let baseTokenAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44";
  let quoteTokenAddress = "0x79dCF515aA18399CF8fAda58720FAfBB1043c526";

  if (pairFactory == null) {
    let pairFactoryAddress = "0xFb32d5327f17Bb5b10f76D453768b39a2C020D3a";
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
  ammAddress = "0xE5140fE7eEE8D522464a542767c6B14Cf1251051";
  if (bondPoolFactory == null) {
    let bondPoolFactoryAddress = "0x076A33AAc2fC3664dceF2AD33f414d485E4Ae898";
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
    let bondPoolAddress = "0x2F9De466963d4F26052F93D7B7665fD36C41AA97";
    const BondPool = await ethers.getContractFactory("BondPool");
    bondPool = await BondPool.attach(bondPoolAddress);
  }
  if (pcvTreasury == null) {
    let pcvTreasuryAddress = "0x42C0E0fdA16CE20C3c15bBF666Ee79EaB5998F20";
    let PCVTreasury = await ethers.getContractFactory("PCVTreasury");
    pcvTreasury = await PCVTreasury.attach(pcvTreasuryAddress);
  }
  let balance = await apeXToken.balanceOf(pcvTreasuryAddress);
  console.log("balance:", balance.toString());

  let ammAddress = "0xE5140fE7eEE8D522464a542767c6B14Cf1251051";
  await pcvTreasury.addLiquidityToken(ammAddress);
  await pcvTreasury.addBondPool(bondPool.address);
  let isLiquidityToken = await pcvTreasury.isLiquidityToken(ammAddress);
  let isBondPool = await pcvTreasury.isBondPool(bondPool.address);
  console.log("isLiquidityToken:", isLiquidityToken.toString());
  console.log("isBondPool:", isBondPool.toString());

  const MockWETH = await ethers.getContractFactory("MockWETH");
  const weth = await MockWETH.attach("0x655e2b2244934Aea3457E3C56a7438C271778D44");
  await weth.approve(bondPool.address, BigNumber.from("10000000000000000000000000000000").toString());
  await bondPool.deposit(signer, BigNumber.from("1000000000000000").toString(), 1);

  let overrides = {
    value: ethers.utils.parseEther("0.01"),
  };
  await bondPool.depositETH(signer, 1, overrides);

  let bondInfo = await bondPool.bondInfoFor(signer);
  console.log("payout:", bondInfo.payout.toString());
}

async function createMockStakingPool() {
  if (stakingPoolFactory == null) {
    let stakingPoolFactoryAddress = "0xe0930A9d13FD7F2dcbC554EB1cCD13ed53F389eF";
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

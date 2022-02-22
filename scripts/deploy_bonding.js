const { ethers } = require("hardhat");
const verifyStr = "npx hardhat verify --network";

// const v2FactoryAddress = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4"; // SushiV2Factory address
const v2FactoryAddress = "0x9ef193943E14D83BcdAD9e3d782DBafA93bd25A1"; // Self deploy UniswapV2Factory address
const usdcAddress = "0x79dCF515aA18399CF8fAda58720FAfBB1043c526"; // mock USDC

// transfer to pcvTreasury
const apeXAmountForBonding = BigNumber.from("1000000000000000000000000");
// for BondPoolFactory
const maxPayout = BigNumber.from("1000000000000000000000000");
const discount = 500;
const vestingTerm = 129600;

let bondPriceOracle;
let bondPoolFactory;
let bondPool;

let apeXAddress = "0x94aD21Bf72F0f4ab545E59ea3d5C1F863d74C629";
let priceOracleAddress = "0x3a62F3b224Dfe5E13dfa360D1E03aE32191bF091";
let apeXAddress = "0x94aD21Bf72F0f4ab545E59ea3d5C1F863d74C629";
let ammAddress = "";
let apeXAmountForBonding = 1000000000;
let maxPayout = 100000000;
let discount = 500;
let vestingTerm = 129600;
let pcvTreasury;
let bondPoolFactory;

const main = async () => {
  await createPCVTreasury();
  await createBondPoolFactory();
  await createBondPool();
};

async function createPCVTreasury() {
  const PCVTreasury = await ethers.getContractFactory("PCVTreasury");
  pcvTreasury = await PCVTreasury.deploy(apeXAddress);
  console.log("PCVTreasury:", pcvTreasury.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, pcvTreasury.address, apeXAddress);

  // transfer apeX to pcvTreasury for bonding
  const ApeXToken = await ethers.getContractFactory("ApeXToken");
  let apeXToken = await ApeXToken.attach(apeXAddress);
  await apeXToken.transfer(pcvTreasury.address, apeXAmountForBonding);
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

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

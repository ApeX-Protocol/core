const { ethers } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

//// ArbitrumOne
// const apeXAddress = "0x61A1ff55C5216b636a294A07D77C6F4Df10d3B56";
// const pcvTreasuryAddress = "0x73f5d8fb154d19a0C496E7411488cD455aB0373A";
// const routerAddress = "";
// const v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
// const wethAddress = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1";
// const usdcAddress = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
//// Testnet
const apeXAddress = "0x3f355c9803285248084879521AE81FF4D3185cDD";
const pcvTreasuryAddress = "0x2225F0bEef512e0302D6C4EcE4f71c85C2312c06";
const v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; // testnet uniV3factory
const wethAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44"; // mock WETH
const usdcAddress = "0x79dCF515aA18399CF8fAda58720FAfBB1043c526"; // mock USDC

const maxPayout = BigNumber.from("1000000000000000000000000");
const discount = 500;
const vestingTerm = 129600;

let bondPriceOracle;
let poolTemplate;
let bondPoolFactory;

const main = async () => {
  // await createBondPriceOracle();
  // await createPoolTemplate();
  // await createPoolFactory();
  await createPCVPolicyForMigrator();
};

async function createBondPriceOracle() {
  const BondPriceOracle = await ethers.getContractFactory("BondPriceOracle");
  bondPriceOracle = await BondPriceOracle.deploy();
  await bondPriceOracle.initialize(apeXAddress, wethAddress, v3FactoryAddress);
  await bondPriceOracle.setupTwap(usdcAddress);
  console.log("BondPriceOracle:", bondPriceOracle.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, bondPriceOracle.address);
}

async function createPoolTemplate() {
  const BondPool = await ethers.getContractFactory("BondPool");
  poolTemplate = await BondPool.deploy();
  console.log("poolTemplate:", poolTemplate.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, poolTemplate.address);
}

async function createPoolFactory() {
  const BondPoolFactory = await ethers.getContractFactory("BondPoolFactory");
  bondPoolFactory = await BondPoolFactory.deploy(
    wethAddress,
    apeXAddress,
    pcvTreasuryAddress,
    bondPriceOracle.address,
    poolTemplate.address,
    maxPayout,
    discount,
    vestingTerm
  );
  console.log("BondPoolFactory:", bondPoolFactory.address);
  console.log(
    verifyStr,
    process.env.HARDHAT_NETWORK,
    bondPoolFactory.address,
    wethAddress,
    apeXAddress,
    pcvTreasuryAddress,
    bondPriceOracle.address,
    poolTemplate.address,
    maxPayout.toString(),
    discount,
    vestingTerm
  );
}

async function createPCVPolicyForMigrator() {
  const treasury = "0x2225F0bEef512e0302D6C4EcE4f71c85C2312c06";
  const pairFactory = "0xf6DA867db55BCA6312132cCFC936160fB970fEF4";
  const PCVPolicyForMigrator = await ethers.getContractFactory("PCVPolicyForMigrator");
  let migrator = await PCVPolicyForMigrator.deploy(treasury, pairFactory);
  console.log("PCVPolicyForMigrator:", migrator.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, migrator.address, treasury, pairFactory);

  let configAddress = "0x43624493A79eF508BC9EDe792E67aABD44e3BfE8";
  const Config = await ethers.getContractFactory("Config");
  let config = await Config.attach(configAddress);
  await config.registerRouter(migrator.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

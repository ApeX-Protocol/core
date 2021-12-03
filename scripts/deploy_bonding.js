const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

let apeXAddress = "";
let priceOracleAddress = "";
let uniswapV3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; //this is ethereum mainnet
let maxPayout = 100000000;
let discount = 500;
let vestingTerm = 129600;
let pcvTreasury;
let bondPoolFactory;
let apexToken;
let priceOracle;

const main = async () => {
  await createContracts();
};

async function createContracts() {
  const MockToken = await ethers.getContractFactory("MockToken");
  const PCVTreasury = await ethers.getContractFactory("PCVTreasury");
  const BondPoolFactory = await ethers.getContractFactory("BondPoolFactory");
  const PriceOracle = await ethers.getContractFactory("PriceOracle");

  apexToken = await MockToken.deploy("apex token", "at");
  await apexToken.deployed();
  apeXAddress = apexToken.address;
  console.log("apeXToken:", apexToken.address);

  priceOracle = await PriceOracle.deploy(uniswapV3FactoryAddress);
  await priceOracle.deployed();
  priceOracleAddress = priceOracle.address;
  console.log(`priceOracle: ${priceOracle.address}`);

  pcvTreasury = await PCVTreasury.deploy(apeXAddress);
  console.log("PCVTreasury:", pcvTreasury.address);

  bondPoolFactory = await BondPoolFactory.deploy(
    apeXAddress,
    pcvTreasury.address,
    priceOracleAddress,
    maxPayout,
    discount,
    vestingTerm
  );
  console.log("BondPoolFactory:", bondPoolFactory.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

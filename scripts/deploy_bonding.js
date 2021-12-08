const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

let apeXAddress = "0x94aD21Bf72F0f4ab545E59ea3d5C1F863d74C629";
let priceOracleAddress = "0x3a62F3b224Dfe5E13dfa360D1E03aE32191bF091";
let ammAddress = "";
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
}

async function createBondPoolFactory() {
  const BondPoolFactory = await ethers.getContractFactory("BondPoolFactory");
  bondPoolFactory = await BondPoolFactory.deploy(
    apeXAddress,
    pcvTreasury.address,
    priceOracleAddress,
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
    pcvTreasury.address,
    priceOracleAddress,
    maxPayout,
    discount,
    vestingTerm
  );
}

async function createBondPool() {
  await bondPoolFactory.createPool(ammAddress);
  let poolsLength = await bondPoolFactory.allPoolsLength();
  let bondPool = await bondPoolFactory.allPools(poolsLength.toNumber() - 1);
  console.log("BondPool:", bondPool);
  console.log(
    verifyStr,
    process.env.HARDHAT_NETWORK,
    bondPool.address,
    apeXAddress,
    pcvTreasury.address,
    priceOracleAddress,
    ammAddress,
    maxPayout,
    discount,
    vestingTerm
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

let apeXAddress = "";
let priceOracleAddress = "";
let maxPayout = 100000000;
let discount = 500;
let vestingTerm = 129600;
let pcvTreasury;
let bondPoolFactory;

const main = async () => {
    await createContracts();
};

async function createContracts() {
    const PCVTreasury = await ethers.getContractFactory("PCVTreasury");
    const BondPoolFactory = await ethers.getContractFactory("BondPoolFactory");
    pcvTreasury = await PCVTreasury.deploy(apeXAddress);
    bondPoolFactory = await BondPoolFactory.deploy(apeXAddress, pcvTreasury.address, priceOracleAddress, maxPayout, discount, vestingTerm);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

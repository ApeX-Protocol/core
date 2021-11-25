const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

let apexToken;
let slpToken;
let stakingPoolFactory;
let tx;

const main = async () => {
  await createContracts();
};

async function createContracts() {
  const MockToken = await ethers.getContractFactory("MockToken");
  const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");

  apexToken = await MockToken.deploy("apex token", "at");
  await apexToken.deployed();

  slpToken = await MockToken.deploy("slp token", "slp");
  await slpToken.deployed();

  stakingPoolFactory = await upgrades.deployProxy(StakingPoolFactory, [apexToken.address, 100, 2, 6690016, 7090016]);
  await stakingPoolFactory.deployed();
  console.log(`stakingPoolFactory: ${stakingPoolFactory.address}`);

  tx = await stakingPoolFactory.createPool(apexToken.address, 6690016, 21);
  await tx.wait();

  tx = await stakingPoolFactory.createPool(slpToken.address, 6690016, 79);
  await tx.wait();

  console.log("✌️");
  console.log(verifyStr, process.env.HARDHAT_NETWORK, apexToken.address, "'apex token' 'at'");
  console.log(verifyStr, process.env.HARDHAT_NETWORK, slpToken.address, "'slp token' 'slp'");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

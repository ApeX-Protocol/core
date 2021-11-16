const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

let apexToken;
let slpToken;
let corePoolFactory;
let tx;

const main = async () => {
  await createContracts();
};

async function createContracts() {
  const MockToken = await ethers.getContractFactory("MockToken");
  const CorePoolFactory = await ethers.getContractFactory("CorePoolFactory");

  apexToken = await MockToken.deploy("apex token", "at");
  await apexToken.deployed();

  slpToken = await MockToken.deploy("slp token", "slp");
  await slpToken.deployed();

  corePoolFactory = await upgrades.deployProxy(CorePoolFactory, [apexToken.address, 100, 2, 6690016, 7090016]);
  await corePoolFactory.deployed();
  console.log(`corePoolFactory: ${corePoolFactory.address}`);

  tx = await corePoolFactory.createPool(apexToken.address, 6690016, 21);
  await tx.wait();

  tx = await corePoolFactory.createPool(slpToken.address, 6690016, 79);
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

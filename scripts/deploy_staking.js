const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");

let signer;
let apexToken;
let slpToken;
let stakingPoolFactory;
let apexPool;
let slpPool;
let stakingPoolFactoryAddress = "0xDDA0Da554f315CBB700d1bdB7eE2a12BD259825c";
let apexTokenAddress = "0x8d222C30b1d7Fa358C634116469254a7c47C2d86";
let slpTokenAddress = "0x8590F91eAD712311cc315F1A13115974e3423615";
let apexPoolAddress = "0xf38f57f43F8134ece3F007a05Eb733a68c5d04D8";
let slpPoolAddress = "0x8F655495545171D434922D91a0c05E6A49D888df";

const main = async () => {
  // await createContracts();
  await flow();
};

async function createContracts() {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  const MockToken = await ethers.getContractFactory("MockToken");
  const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
  const StakingPool = await ethers.getContractFactory("StakingPool");

  apexToken = await MockToken.deploy("apex token", "at");
  await apexToken.deployed();

  slpToken = await MockToken.deploy("slp token", "slp");
  await slpToken.deployed();

  stakingPoolFactory = await upgrades.deployProxy(StakingPoolFactory, [apexToken.address, 100, 2, 6690016, 10090016]);
  await stakingPoolFactory.deployed();

  await stakingPoolFactory.createPool(apexToken.address, 6690016, 21);
  await stakingPoolFactory.createPool(slpToken.address, 6690016, 79);

  let result = await stakingPoolFactory.pools(apexToken.address);
  apexPool = await StakingPool.attach(result.pool);
  result = await stakingPoolFactory.pools(slpToken.address);
  slpPool = await StakingPool.attach(result.pool);

  await stakingPoolFactory.setYieldLockTime(15552000);
  await apexToken.mint(signer, 1000000000000);
  await apexToken.approve(apexPool.address, 1000000000000);

  console.log(`let stakingPoolFactoryAddress = "${stakingPoolFactory.address}"`);
  console.log(`let apexTokenAddress = "${apexToken.address}"`);
  console.log(`let slpTokenAddress = "${slpToken.address}"`);
  console.log(`let apexPoolAddress = "${apexPool.address}"`);
  console.log(`let slpPoolAddress = "${slpPool.address}"`);
}

async function flow() {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  const MockToken = await ethers.getContractFactory("MockToken");
  const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
  const StakingPool = await ethers.getContractFactory("StakingPool");
  stakingPoolFactory = await StakingPoolFactory.attach(stakingPoolFactoryAddress);
  apexPool = await StakingPool.attach(apexPoolAddress);
  slpPool = await StakingPool.attach(slpPoolAddress);

  apexToken = await MockToken.attach(apexTokenAddress);

  // await stakingPoolFactory.changePoolWeight(apexPool.address, 22);
  // await apexPool.stake(10000, 0);
  await apexPool.processRewards();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");

let signer;
let apexToken;
let slpToken;
let stakingPoolFactory;
let apexPool;
let slpPool;
let stakingPoolFactoryAddress = "0xd0741e5d5545810900EdE1226870b06DC3eB19b5";
let apexTokenAddress = "0xa591d5Bd798424a982543B18b84EA1591d51D6bA";
let slpTokenAddress = "0xF2707e5286f2204484f6151D3D13bEBEc09D846c";
let apexPoolAddress = "0xC2873E9Aa78dC479Ba2d1f33dc99f159Facd4134";
let slpPoolAddress = "0x26561489fc18f25C71fc25611B18F79c6E3E16b8";

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
  slpToken = await MockToken.attach(slpTokenAddress);

  await slpToken.mint(signer, 1000000000000);
  await slpToken.approve(slpPool.address, 1000000000000);
  await slpPool.stake(10000, 0);
  await slpPool.processRewards();
  await stakingPoolFactory.changePoolWeight(apexPool.address, 22);
  await apexPool.stake(10000, 0);
  await apexPool.processRewards();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

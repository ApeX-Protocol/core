const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");

// for StakingPoolFactory
const apeXPerSec = BigNumber.from("100000000000000000");
const secSpanPerUpdate = 30;
const initTimestamp = 1641781192;
const endTimestamp = 1673288342;
// const lockTime = 15552000;
const lockTime = 120;
// transfer for staking
const apeXAmountForStaking = BigNumber.from("10000000000000000000000");

let stakingPoolFactory;

let signer;
let apexToken;
let slpToken;
let esApeX;
let veApeX;
let stakingPoolFactory;
let apexPool;
let slpPool;
let stakingPoolFactoryAddress = "0x3f765b5fE77f54C3B3728bCe166fa94FF3af8fD7";
let apexTokenAddress = "0xea07968739C15C0784c55124B0608AC5F2a8Cf71";
let slpTokenAddress = "0xCB5F97D234442E5256812bA264Adc96e61b54258";
let apexPoolAddress = "0x0e6F6ab8707c2fbf523E203852702DA918075b93";
let slpPoolAddress = "0xF28086ACB509586275837866BcaE960A7595eFe1";
let esApeXAddress = "0x3b02cA952FCE231B3EE4312E8299cb1432B9F0De";
let veApeXAddress = "0xDF71aF11D46A0571faE679b7154b12ce83482361";

let treasury = "0xba5129359491007F82C79C4e1f322B6341C28D8F";
let apeXPerSec = BigNumber.from("100000000000000000");
let secSpanPerUpdate = 30;
let initTimestamp = 1641781192;
let endTimestamp = 1673288342;
let lockTime = 120;

const main = async () => {
  // await createContracts();
  await flow();
};

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

async function createContracts() {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  const MockToken = await ethers.getContractFactory("MockToken");
  const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
  const StakingPool = await ethers.getContractFactory("StakingPool");
  const EsAPEX = await ethers.getContractFactory("EsAPEX");
  const VeAPEX = await ethers.getContractFactory("VeAPEX");

  apexToken = await MockToken.deploy("apex token", "at");
  await apexToken.deployed();
  slpToken = await MockToken.deploy("slp token", "slp");
  await slpToken.deployed();
  stakingPoolFactory = await upgrades.deployProxy(StakingPoolFactory, [
    apexToken.address,
    treasury,
    apeXPerSec,
    secSpanPerUpdate,
    initTimestamp,
    endTimestamp,
    lockTime,
  ]);
  await stakingPoolFactory.deployed();
  esApeX = await EsAPEX.deploy(stakingPoolFactory.address);
  veApeX = await VeAPEX.deploy(stakingPoolFactory.address);

  await stakingPoolFactory.createPool(apexToken.address, 6690016, 21);
  await stakingPoolFactory.createPool(slpToken.address, 6690016, 79);
  let result = await stakingPoolFactory.pools(apexToken.address);
  apexPool = await StakingPool.attach(result.pool);
  result = await stakingPoolFactory.pools(slpToken.address);
  slpPool = await StakingPool.attach(result.pool);

  await stakingPoolFactory.setRemainForOtherVest(50);
  await stakingPoolFactory.setEsApeX(esApeX.address);
  await stakingPoolFactory.setVeApeX(veApeX.address);
  await stakingPoolFactory.setLockTime(15552000);
  await apexToken.mint(signer, 1000000000000);
  await apexToken.approve(apexPool.address, 1000000000000);

  console.log(`let stakingPoolFactoryAddress = "${stakingPoolFactory.address}"`);
  console.log(`let apexTokenAddress = "${apexToken.address}"`);
  console.log(`let slpTokenAddress = "${slpToken.address}"`);
  console.log(`let apexPoolAddress = "${apexPool.address}"`);
  console.log(`let slpPoolAddress = "${slpPool.address}"`);
  console.log(`let esApeXAddress = "${esApeX.address}"`);
  console.log(`let veApeXAddress = "${veApeX.address}"`);
}

async function flow() {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  const MockToken = await ethers.getContractFactory("MockToken");
  const EsAPEX = await ethers.getContractFactory("EsAPEX");
  const VeAPEX = await ethers.getContractFactory("VeAPEX");
  const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
  const StakingPool = await ethers.getContractFactory("StakingPool");
  stakingPoolFactory = await StakingPoolFactory.attach(stakingPoolFactoryAddress);
  apexPool = await StakingPool.attach(apexPoolAddress);
  slpPool = await StakingPool.attach(slpPoolAddress);

  apexToken = await MockToken.attach(apexTokenAddress);
  slpToken = await MockToken.attach(slpTokenAddress);

  esApeX = await EsAPEX.attach(esApeXAddress);
  veApeX = await VeAPEX.attach(veApeXAddress);

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

const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

//// ArbitrumOne
const wethAddress = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1";
// const apeXAddress = "0x3f355c9803285248084879521AE81FF4D3185cDD";
// const treasuryAddress = ""; // PCVTreasury address
// const slpTokenAddress = ""; // APEX-WETH slp
//// Testnet
// const wethAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44";
// const apeXAddress = "0x3f355c9803285248084879521AE81FF4D3185cDD";
// const treasuryAddress = "0x2225F0bEef512e0302D6C4EcE4f71c85C2312c06"; // PCVTreasury address
// const slpTokenAddress = "0x473BfBD8bda825f7E39e4Fa826D9a8B5129cE4E7"; // APEX-WETH slp

const apeXPerSec = BigNumber.from("82028346620490110");
const secSpanPerUpdate = 14 * 24 * 3600; //two weeks
const initTimestamp = Math.round(new Date().getTime() / 1000);
const endTimestamp = initTimestamp + 365 * 24 * 3600; //one year after init time
const sixMonth = 180 * 24 * 3600;
const apeXPoolWeight = 21;
const slpPoolWeight = 79;
const remainForOtherVest = 50;
const minRemainRatioAfterBurn = 6000;

let esApeX;
let veApeX;
let apeXPool;
let slpPool;
let stakingPoolTemplate;
let stakingPoolFactory;
let rewardForStaking;

const main = async () => {
  // await createPools();
  await createReward();
};

async function createPools() {
  const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
  const StakingPool = await ethers.getContractFactory("StakingPool");
  const ApeXPool = await ethers.getContractFactory("ApeXPool");
  const EsAPEX = await ethers.getContractFactory("EsAPEX");
  const VeAPEX = await ethers.getContractFactory("VeAPEX");

  stakingPoolTemplate = await StakingPool.deploy();
  console.log("stakingPoolTemplate:", stakingPoolTemplate.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, stakingPoolTemplate.address);

  stakingPoolFactory = await StakingPoolFactory.deploy();
  await stakingPoolFactory.initialize(
    apeXAddress,
    treasuryAddress,
    apeXPerSec,
    secSpanPerUpdate,
    initTimestamp,
    endTimestamp,
    sixMonth
  );
  console.log("StakingPoolFactory:", stakingPoolFactory.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, stakingPoolFactory.address);

  stakingPoolFactory = await upgrades.deployProxy(StakingPoolFactory, [
    apeXAddress,
    treasuryAddress,
    apeXPerSec,
    secSpanPerUpdate,
    initTimestamp,
    endTimestamp,
    sixMonth,
  ]);
  console.log("StakingPoolFactory:", stakingPoolFactory.address);

  apeXPool = await ApeXPool.deploy(stakingPoolFactory.address, apeXAddress);
  console.log("ApeXPool:", apeXPool.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, apeXPool.address, stakingPoolFactory.address, apeXAddress);

  esApeX = await EsAPEX.deploy(stakingPoolFactory.address);
  console.log("EsAPEX:", esApeX.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, esApeX.address, stakingPoolFactory.address);

  veApeX = await VeAPEX.deploy(stakingPoolFactory.address);
  console.log("VeAPEX:", veApeX.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, veApeX.address, stakingPoolFactory.address);

  await stakingPoolFactory.setRemainForOtherVest(remainForOtherVest);
  await stakingPoolFactory.setMinRemainRatioAfterBurn(minRemainRatioAfterBurn);
  await stakingPoolFactory.setEsApeX(esApeX.address);
  await stakingPoolFactory.setVeApeX(veApeX.address);
  await stakingPoolFactory.setStakingPoolTemplate(stakingPoolTemplate.address);

  await stakingPoolFactory.registerApeXPool(apeXPool.address, apeXPoolWeight);

  await stakingPoolFactory.createPool(slpTokenAddress, slpPoolWeight);
  slpPool = StakingPool.attach(await stakingPoolFactory.tokenPoolMap(slpTokenAddress));
  console.log("slpPool:", slpPool.address);
}

async function createReward() {
  const RewardForStaking = await ethers.getContractFactory("RewardForStaking");
  rewardForStaking = await RewardForStaking.deploy(wethAddress);
  console.log("RewardForStaking:", rewardForStaking.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, rewardForStaking.address, wethAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

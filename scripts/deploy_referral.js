const { ethers } = require("hardhat");
const verifyStr = "npx hardhat verify --network";

const wethAddress = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1"; // WETH address in ArbitrumOne
// const wethAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44"; // mockWETH

let invitation;
let rewardForCashback;

const main = async () => {
  // await createInvitation();
  await createRewardForCashback();
};

async function createInvitation() {
  const Invitation = await ethers.getContractFactory("Invitation");
  invitation = await Invitation.deploy();
  console.log("Invitation:", invitation.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, invitation.address);
}

async function createRewardForCashback() {
  const RewardForCashback = await ethers.getContractFactory("RewardForCashback");
  rewardForCashback = await RewardForCashback.deploy(wethAddress);
  console.log("RewardForCashback:", rewardForCashback.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, rewardForCashback.address, wethAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

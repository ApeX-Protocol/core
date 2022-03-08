const { ethers } = require("hardhat");
const verifyStr = "npx hardhat verify --network";

let invitation;
let rewardForCashback;

const main = async () => {
  await createInvitation();
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
  rewardForCashback = await RewardForCashback.deploy();
  console.log("RewardForCashback:", rewardForCashback.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, rewardForCashback.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

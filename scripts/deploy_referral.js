const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

const apeXAmountForReward = BigNumber.from("10000000000000000000000");

let invitation;
let reward;

let invitation;
let merkleDistributor;
let apexToken;
let multicall;

const main = async () => {
  await createContracts();
};

async function createInvitation() {
  const Invitation = await ethers.getContractFactory("Invitation");
  invitation = await Invitation.deploy();
  console.log("Invitation:", invitation.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, invitation.address);
}

async function createReward() {
  const Reward = await ethers.getContractFactory("Reward");
  reward = await Reward.deploy(apeXToken.address);
  console.log("Reward:", reward.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, reward.address, apeXToken.address);
  await apeXToken.transfer(reward.address, apeXAmountForReward);
}

async function createContracts() {
  const MockToken = await ethers.getContractFactory("MockToken");
  const InvitationPoolFactory = await ethers.getContractFactory("Invitation");
  const Multicall = await ethers.getContractFactory("Multicall2");
  [owner] = await ethers.getSigners();
  console.log("deployer:", owner.address);

  apexToken = await MockToken.deploy("apex token", "at");
  await apexToken.deployed();
  console.log("apeXToken:", apexToken.address);

  invitation = await InvitationPoolFactory.deploy();
  await invitation.deployed();
  console.log("invitation✌️:", invitation.address);

  multicall = await Multicall.deploy();
  await multicall.deployed();
  console.log("multicall:", multicall.address);

  let blockNumber = await multicall.getBlockNumber();
  console.log("blockNumber: ", blockNumber);

  const MerkleDistributorPoolFactory = await ethers.getContractFactory("MerkleDistributor");

  merkleDistributor = await MerkleDistributorPoolFactory.deploy(
    apexToken.address,
    "0xa178ba2590c5523af85c7529f032c66c6d86d6fbe1faf8b99fa5ee97a4e614be"
  );
  await merkleDistributor.deployed();

  console.log("merkleDistributor:", merkleDistributor.address);

  console.log(verifyStr, process.env.HARDHAT_NETWORK, apexToken.address, "'apex token' 'at'");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

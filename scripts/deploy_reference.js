const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

let invitation;
let merkleDistributor;
let apexToken;

const main = async () => {
  await createContracts();
};

async function createContracts() {
  const MockToken = await ethers.getContractFactory("MockToken");
  const InvitationPoolFactory = await ethers.getContractFactory("Invitation");
  [owner] = await ethers.getSigners();
  console.log("deployer:", owner.address);

  apexToken = await MockToken.deploy("apex token", "at");
  await apexToken.deployed();
  console.log("apxToken:", apexToken.address);

  invitation = await InvitationPoolFactory.deploy();
  await invitation.deployed();
  console.log("invitation✌️:", invitation.address);

  const MerkleDistributorPoolFactory = await ethers.getContractFactory("MerkleDistributor");

  merkleDistributor = await MerkleDistributorPoolFactory.deploy(apexToken.address, '0xa178ba2590c5523af85c7529f032c66c6d86d6fbe1faf8b99fa5ee97a4e614be');
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


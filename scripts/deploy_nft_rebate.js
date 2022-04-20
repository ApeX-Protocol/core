const { ethers } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

let eachNFT = BigNumber.from("200000000000000000");
let maxCount = 4560;
let nftRebate;

const main = async () => {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  await createNFTRebate();
};

async function createNFTRebate() {
  const NFTRebate = await ethers.getContractFactory("NFTRebate");
  nftRebate = await NFTRebate.deploy(eachNFT, maxCount);
  console.log("NFTRebate:", nftRebate.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, nftRebate.address, eachNFT.toString(), maxCount);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

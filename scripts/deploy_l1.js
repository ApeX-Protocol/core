const { ethers } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

let signer;
let apeXToken;
let vipNft;
let squidNft;

let vipNftName = "ApeX-VIP-NFT-PRE";
let vipNftSymbol = "APEX-VIP-NFT-PRE";
let vipNftBaseURI = "https://gateway.pinata.cloud/ipfs/QmPdTKdcm9KNHpS6jYFX2P2SyGeF5xcrw7MAWZFeVM4YgC/";
let vipNftStartTime = Math.round(new Date().getTime() / 1000) + 60;
let vipNftCliff = 0;
let vipNftDuration = 36000;

let squidNftName = "ApeX-Squid-NFT-PRE";
let squidNftSymbol = "APEX-SQU-NFT-PRE";
let squidNftBaseURI = "https://testapex.mypinata.cloud/ipfs/Qmb7MB92bUNvroCEnU1G972sbyaB1dYYdZtBWqmg1BiLES/";
let squidNftStartTime = Math.round(new Date().getTime() / 1000) + 3600;
let squidNftEndTime = squidNftStartTime + 36000;
let squidStartTime = squidNftEndTime + 36000;

const main = async () => {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  await createApeXToken();
  await createVipNft();
  await createNftSquid();
  await createMulticall2();
};

async function createApeXToken() {
  const ApeXToken = await ethers.getContractFactory("ApeXToken");
  apeXToken = await ApeXToken.deploy();
  console.log("ApeXToken:", apeXToken.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, apeXToken.address);
}

async function createVipNft() {
  if (apeXToken == null) {
    let apeXTokenAddress = "0xf5233793F07cC3a229F498744De6eEA7c52B2dAe";
    const ApeXToken = await ethers.getContractFactory("ApeXToken");
    apeXToken = await ApeXToken.attach(apeXTokenAddress);
  }
  const ApeXVIPNFT = await ethers.getContractFactory("ApeXVIPNFT");
  vipNft = await ApeXVIPNFT.deploy(
    vipNftName,
    vipNftSymbol,
    vipNftBaseURI,
    apeXToken.address,
    vipNftStartTime,
    vipNftCliff,
    vipNftDuration
  );
  console.log("ApeXVIPNFT:", vipNft.address);
  console.log(
    verifyStr,
    process.env.HARDHAT_NETWORK,
    vipNft.address,
    vipNftName,
    vipNftSymbol,
    vipNftBaseURI,
    apeXToken.address,
    vipNftStartTime,
    vipNftCliff,
    vipNftDuration
  );
}

async function createNftSquid() {
  if (apeXToken == null) {
    let apeXTokenAddress = "0xf5233793F07cC3a229F498744De6eEA7c52B2dAe";
    const ApeXToken = await ethers.getContractFactory("ApeXToken");
    apeXToken = await ApeXToken.attach(apeXTokenAddress);
  }
  const NftSquid = await ethers.getContractFactory("NftSquid");
  squidNft = await NftSquid.deploy(
    squidNftName,
    squidNftSymbol,
    squidNftBaseURI,
    apeXToken.address,
    squidNftStartTime,
    squidNftEndTime
  );
  await squidNft.setSquidStartTime(squidStartTime);
  console.log("NftSquid:", squidNft.address);
  console.log(
    verifyStr,
    process.env.HARDHAT_NETWORK,
    squidNft.address,
    squidNftName,
    squidNftSymbol,
    squidNftBaseURI,
    apeXToken.address,
    squidNftStartTime,
    squidNftEndTime
  );
}

async function createMulticall2() {
  const Multicall2 = await ethers.getContractFactory("Multicall2");
  multicall2 = await Multicall2.deploy();
  console.log("Multicall2:", multicall2.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, multicall2.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

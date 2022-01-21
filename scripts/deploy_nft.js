const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");

let signer;
let apeXToken;
let nftSquid;
let apeXVIPNFT;
let nftSquidAddress = "0x66502f41406b6a03741FDbb7d3c417A20bDa23f5";
let apeXVIPNFTAddress = "0xC7565125b08127812D04F9096e0b5A6eBE241Ff9";
let apeXTokenAddress = "0xAbc3DeE57B87F06240FA91d7D4C8B0C4e041A26E";

let startTime = Math.round(new Date().getTime() / 1000) + 60;
let cliff = 0;
let duration = 3600;

const main = async () => {
  // await createContracts();
  await flow();
};

async function createContracts() {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  const MockToken = await ethers.getContractFactory("MockToken");
  const NftSquid = await ethers.getContractFactory("NftSquid");
  const ApeXVIPNFT = await ethers.getContractFactory("ApeXVIPNFT");

  apeXToken = await MockToken.deploy("apeX token", "at");
  await apeXToken.deployed();

  nftSquid = await NftSquid.deploy("APEX NFT", "APEXNFT", "https://apexNFT/", apeXToken.address);
  apeXVIPNFT = await ApeXVIPNFT.deploy(
    "APEX NFT",
    "APEXNFT",
    "https://apexNFT/",
    apeXToken.address,
    startTime,
    cliff,
    duration
  );

  console.log(`let nftSquidAddress = "${nftSquid.address}"`);
  console.log(`let apeXVIPNFTAddress = "${apeXVIPNFT.address}"`);
  console.log(`let apeXTokenAddress = "${apeXToken.address}"`);

  await apeXToken.mint(signer, 1000000000000);
  await apeXToken.mint(apeXVIPNFT.address, "20000000000000000000000");
  await apeXToken.mint(nftSquid.address, "20000000000000000000000");

  await apeXVIPNFT.setTotalAmount(1000000);
  await apeXVIPNFT.addManyToWhitelist([signer]);
  await nftSquid.setStartTime(startTime);

  //must match with nftSquid price
  await apeXVIPNFT.claimApeXVIPNFT({ value: ethers.utils.parseEther("0.0001") });
  //must match with apeXVIPNFT price
  await nftSquid.claimApeXNFT({ value: ethers.utils.parseEther("0.0001") });
}

async function flow() {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  const MockToken = await ethers.getContractFactory("MockToken");
  const ApeXVIPNFT = await ethers.getContractFactory("ApeXVIPNFT");
  const NftSquid = await ethers.getContractFactory("NftSquid");

  apeXVIPNFT = await ApeXVIPNFT.attach(apeXVIPNFTAddress);
  nftSquid = await NftSquid.attach(nftSquidAddress);
  apeXToken = await MockToken.attach(apeXTokenAddress);

  let result = (await apeXVIPNFT.claimableAmount(signer)).toNumber();
  if (result > 0) {
    result = await nftSquid.calWithdrawAmountAndBonus();
    await apeXVIPNFT.claimAPEX();
    await nftSquid.burnAndEarn(0);
  } else {
    console.log("claimableAmount is 0");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

const hre = require("hardhat");
const ethers = require("ethers");

const walletPrivateKey = process.env.DEVNET_PRIVKEY;

const l2Provider = new ethers.providers.JsonRpcProvider(process.env.L2RPC);
const signer = new ethers.Wallet(walletPrivateKey);
const l2Signer = signer.connect(l2Provider);

const baseAddress = "0x0A07D10f55fA9dab9A57169EAF4a6fBe3FA7ff67";
const quoteAddress = "0xA53b211A2c90e840b29a153C65Af8D0ff4DdF447";
const priceOracleTestAddress = "0x2d75146A31f2Be1A44865371026BdC5bd0e2AF44";
const ammAddress = "0x8E93BB2158b20FF04BF425E1339ab9Fa2B332C93";

let priceOracleForTest;
let l2Amm;
let tx;

const main = async () => {
  await setPriceDirectly();
};

async function setPriceDirectly() {
  const PriceOracleForTest = await (await hre.ethers.getContractFactory("PriceOracleForTest")).connect(l2Signer);
  const L2Amm = await (await hre.ethers.getContractFactory("Amm")).connect(l2Signer);
  priceOracleForTest = await PriceOracleForTest.attach(priceOracleTestAddress); //exist priceOracleTest address
  l2Amm = await L2Amm.attach(ammAddress); //exist amm address
  console.log("set price...");
  tx = await priceOracleForTest.setReserve(baseAddress, quoteAddress, 1, 1000);
  await tx.wait();
  console.log("rebase...");
  tx = await l2Amm.rebase();
  await tx.wait();
}

async function simulatePriceFluctuation() {
  const PriceOracleForTest = await (await hre.ethers.getContractFactory("PriceOracleForTest")).connect(l2Signer);
  const L2Amm = await (await hre.ethers.getContractFactory("Amm")).connect(l2Signer);

  priceOracleForTest = await PriceOracleForTest.attach(priceOracleTestAddress); //exist priceOracleTest address
  l2Amm = await L2Amm.attach(ammAddress); //exist amm address

  let minute;
  while (true) {
    currentMinute = new Date().getMinutes();
    if (currentMinute != minute) {
      minute = currentMinute;
      console.log("set price...");
      tx = await priceOracleForTest.setReserve(baseAddress, quoteAddress, 1, minute * 100 + 100);
      await tx.wait();
      console.log("rebase...");
      tx = await l2Amm.rebase();
      await tx.wait();
    }
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

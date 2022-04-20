const { ethers } = require("hardhat");
const verifyStr = "npx hardhat verify --network";

const main = async () => {
  //// ArbitrumOne
  const v3Router = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";
  const usdc = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
  const operator = "0x1956b2c4C511FDDd9443f50b36C4597D10cD9985";
  const nextSettleTime = 1649051940;
  //// Testnet
  // const v3Router = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";
  // const usdc = "0x79dCF515aA18399CF8fAda58720FAfBB1043c526"; // mockUSDC in testnet
  // const operator = "0x1956b2c4C511FDDd9443f50b36C4597D10cD9985";
  // const nextSettleTime = Math.round(new Date().getTime() / 1000) + 60 * 10;

  const FeeTreasury = await ethers.getContractFactory("FeeTreasury");
  let feeTreasury = await FeeTreasury.deploy(v3Router, usdc, operator, nextSettleTime);
  console.log("FeeTreasury:", feeTreasury.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, feeTreasury.address, v3Router, usdc, operator, nextSettleTime);

  let Config = await ethers.getContractFactory("Config");
  let config = await Config.attach("0x38a71796bC0291Bc09f4D890B45A9A93d49eDf70");
  await config.registerRouter(feeTreasury.address);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

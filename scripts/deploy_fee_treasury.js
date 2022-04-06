const { ethers } = require("hardhat");
const verifyStr = "npx hardhat verify --network";

const main = async () => {
  //// ArbitrumOne
  // const router = "";
  // const v3Router = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";
  // const usdc = "0x79dCF515aA18399CF8fAda58720FAfBB1043c526";
  // const operator = "0x1956b2c4C511FDDd9443f50b36C4597D10cD9985";
  // const nextSettleTime = Math.round(new Date().getTime() / 1000) + 24 * 3600;
  //// Testnet
  const router = "0x425398182fF6E52c104c7817c8bC3291Ce5f0157";
  const v3Router = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";
  const usdc = "0x79dCF515aA18399CF8fAda58720FAfBB1043c526"; // mockUSDC in testnet
  const operator = "0x1956b2c4C511FDDd9443f50b36C4597D10cD9985";
  const nextSettleTime = Math.round(new Date().getTime() / 1000) + 60 * 10;

  const FeeTreasury = await ethers.getContractFactory("FeeTreasury");
  let feeTreasury = await FeeTreasury.deploy(router, v3Router, usdc, operator, nextSettleTime);
  console.log("feeTreasury:", feeTreasury.address);
  console.log(
    verifyStr,
    process.env.HARDHAT_NETWORK,
    feeTreasury.address,
    router,
    v3Router,
    usdc,
    operator,
    nextSettleTime
  );
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

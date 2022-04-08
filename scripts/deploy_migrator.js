const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const verifyStr = "npx hardhat verify --network";

const main = async () => {
  //// ArbitrumOne

  //// Testnet
  const oldRouter = "0xcbccda0Df16Ba36AfEde7bc6d676E261098f3a9E";
  const newRouter = "0x363fE608166b204ea70017F095949295374fd371";
  const oldConfigAddress = "0xF74F984F78CEBC8734A98F6C8aFf4c13F274EA6B";
  const newConfigAddress = "0x37a74ECe864f40b156eA7e0b2b8EAB8097cb2512";

  const Migrator = await ethers.getContractFactory("Migrator");
  let migrator = await Migrator.deploy(oldRouter, newRouter);
  console.log("Migrator:", migrator.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, migrator.address, oldRouter, newRouter);

  const Config = await await ethers.getContractFactory("Config");
  let oldConfig = await Config.attach(oldConfigAddress);
  await oldConfig.registerRouter(migrator.address);
  let newConfig = await Config.attach(newConfigAddress);
  await newConfig.registerRouter(migrator.address);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

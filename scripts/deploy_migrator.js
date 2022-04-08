const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const verifyStr = "npx hardhat verify --network";

const main = async () => {
  //// ArbitrumOne
  const oldRouter = "0x18f434a074d1e0e4e01de38cf7dcf925db10a0c0";
  const newRouter = "0x102e70dfB3E399D7b9f34D8C407C1B7d17eD70aD";
  const oldConfigAddress = "0xC69d007331957808B215e7f42d645FF439f16b47";
  const newConfigAddress = "0x38a71796bC0291Bc09f4D890B45A9A93d49eDf70";
  //// Testnet
  // const oldRouter = "0xcbccda0Df16Ba36AfEde7bc6d676E261098f3a9E";
  // const newRouter = "0x363fE608166b204ea70017F095949295374fd371";
  // const oldConfigAddress = "0xF74F984F78CEBC8734A98F6C8aFf4c13F274EA6B";
  // const newConfigAddress = "0x37a74ECe864f40b156eA7e0b2b8EAB8097cb2512";

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

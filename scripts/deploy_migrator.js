const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const verifyStr = "npx hardhat verify --network";

const main = async () => {
  //// ArbitrumOne

  //// Testnet
  const oldRouter = "0x6DB28E52F23Af499008Ab3bDa41b723273d45fD7";
  const newRouter = "0x0cb8E61d0b531d107432E9f04D3a77B4E37f3213";
  const oldConfigAddress = "0xBfE1B5d8F2719Ce143b88B7727ACE0af893B7f26";
  const newConfigAddress = "0xBfE1B5d8F2719Ce143b88B7727ACE0af893B7f26";

  const Migrator = await ethers.getContractFactory("Migrator");
  let migrator = await Migrator.deploy(oldRouter, newRouter);
  console.log("Migrator:", migrator.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, migrator.address, oldRouter, newRouter);

  const Config = await await ethers.getContractFactory("Config");
  let oldConfig = await Config.attach(oldConfigAddress);
  oldConfig.registerRouter(migrator.address);
  let newConfig = await Config.attach(newConfigAddress);
  newConfig.registerRouter(migrator.address);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

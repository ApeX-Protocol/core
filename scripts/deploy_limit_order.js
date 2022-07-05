const { upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

// prod
// const pairFactoryAddr = "0xCE09a98C734ffB8e209b907FB0657193796FE3fD";
// const wethAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44";
// const botAddr = "0xbc6e4e0bc15293b5b9f0173c1c4a56525768d36c";
// const usdcAddress = ""; // mockUSDC
// const configAddress = "";
//test
const pairFactoryAddr = "0xCE09a98C734ffB8e209b907FB0657193796FE3fD"; // dev
const wethAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44"; // mockWETH
const botAddr = "0xbc6e4e0bc15293b5b9f0173c1c4a56525768d36c";
const usdcAddress = "0x79dCF515aA18399CF8fAda58720FAfBB1043c526"; // mockUSDC
const configAddress = "0x43624493A79eF508BC9EDe792E67aABD44e3BfE8";

let signer;
let routerForKeeper;
let orderBook;

const main = async () => {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  await createOrderBook();
};

async function createOrderBook() {
  const RouterForKeeper = await ethers.getContractFactory("RouterForKeeper");
  routerForKeeper = await RouterForKeeper.deploy(configAddress, pairFactoryAddr, wethAddress, usdcAddress);
  console.log("RouterForKeeper:", routerForKeeper.address);

  const OrderBook = await ethers.getContractFactory("OrderBook");
  orderBook = await OrderBook.deploy(routerForKeeper.address, botAddr);
  console.log("OrderBook:", orderBook.address);
  await routerForKeeper.setOrderBook(orderBook.address);
  await routerForKeeper.setKeeper(botAddr);

  console.log(verifyStr, process.env.HARDHAT_NETWORK, routerForKeeper.address, pairFactoryAddr, wethAddress);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, orderBook.address, routerForKeeper.address, botAddr);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

const { upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

// prod
const pairFactoryAddr = "0xA7B799832B46B51b2b6a156FDCE58525dE24Ac0f";
const wethAddress = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1";
const botAddr = "0xa41e805010d338Cf909138DFE4dbB7Ee356d20A5";
//test
// const pairFactoryAddr = "0xCE09a98C734ffB8e209b907FB0657193796FE3fD"; // dev
// const wethAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44"; // mockWETH
// const botAddr = "0xbc6e4e0bc15293b5b9f0173c1c4a56525768d36c";

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
  routerForKeeper = await RouterForKeeper.deploy(pairFactoryAddr, wethAddress);
  console.log("RouterForKeeper:", routerForKeeper.address);

  const OrderBook = await ethers.getContractFactory("OrderBook");
  orderBook = await OrderBook.deploy(routerForKeeper.address, botAddr);
  console.log("OrderBook:", orderBook.address);
  await routerForKeeper.setOrderBook(orderBook.address);

  console.log(verifyStr, process.env.HARDHAT_NETWORK, routerForKeeper.address, pairFactoryAddr, wethAddress);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, orderBook.address, routerForKeeper.address, botAddr);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

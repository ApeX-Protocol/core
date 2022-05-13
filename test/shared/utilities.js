const BN = require("bn.js");
const { ethers } = require("hardhat");

const maxUint256 = ethers.constants.MaxUint256;

function newWallet() {
  return ethers.Wallet.createRandom();
}

function bigNumberify(n) {
  return ethers.BigNumber.from(n);
}

function expandDecimals(n, decimals) {
  return bigNumberify(n).mul(bigNumberify(10).pow(decimals));
}

async function send(provider, method, params = []) {
  await provider.send(method, params);
}

async function mineBlock(provider) {
  await send(provider, "evm_mine");
}

async function increaseTime(provider, seconds) {
  await send(provider, "evm_increaseTime", [seconds]);
}

async function gasUsed(provider, tx) {
  return (await provider.getTransactionReceipt(tx.hash)).gasUsed;
}

async function getNetworkFee(provider, tx) {
  const gas = await gasUsed(provider, tx);
  return gas.mul(tx.gasPrice);
}

async function reportGasUsed(provider, tx, label) {
  const { gasUsed } = await provider.getTransactionReceipt(tx.hash);
  console.info(label, gasUsed.toString());
}

async function getBlockTime(provider) {
  const blockNumber = await provider.getBlockNumber();
  const block = await provider.getBlock(blockNumber);
  return block.timestamp;
}

async function getTxnBalances(provider, user, txn, callback) {
  const balance0 = await provider.getBalance(user.address);
  const tx = await txn();
  const fee = await getNetworkFee(provider, tx);
  const balance1 = await provider.getBalance(user.address);
  callback(balance0, balance1, fee);
}

function print(label, value, decimals) {
  if (decimals === 0) {
    console.log(label, value.toString());
    return;
  }
  const valueStr = ethers.utils.formatUnits(value, decimals);
  console.log(label, valueStr);
}

function getPriceBitArray(prices) {
  let priceBitArray = [];
  let shouldExit = false;

  for (let i = 0; i < parseInt((prices.length - 1) / 8) + 1; i++) {
    let priceBits = new BN("0");
    for (let j = 0; j < 8; j++) {
      let index = i * 8 + j;
      if (index >= prices.length) {
        shouldExit = true;
        break;
      }

      const price = new BN(prices[index]);
      if (price.gt(new BN("2147483648"))) { // 2^31
        throw new Error(`price exceeds bit limit ${price.toString()}`);
      }
      priceBits = priceBits.or(price.shln(j * 32));
    }

    priceBitArray.push(priceBits.toString());

    if (shouldExit) {
      break;
    }
  }

  return priceBitArray;
}

function getPriceBits(prices) {
  if (prices.length > 8) {
    throw new Error("max prices.length exceeded");
  }

  let priceBits = new BN("0");

  for (let j = 0; j < 8; j++) {
    let index = j;
    if (index >= prices.length) {
      break;
    }

    const price = new BN(prices[index]);
    if (price.gt(new BN("2147483648"))) { // 2^31
      throw new Error(`price exceeds bit limit ${price.toString()}`);
    }

    priceBits = priceBits.or(price.shln(j * 32));
  }

  return priceBits.toString();
}

async function deployContract(name, args) {
  const contractFactory = await ethers.getContractFactory(name);
  return await contractFactory.deploy(...args);
}

async function deploy(owner) {
  let weth = await deployContract("MockWETH", []);
  let usdc = await deployContract("MockToken", ["mock usdc", "musdc"]);
  let priceOracle = await deployContract("PriceOracleForTest", []);
  let config = await deployContract("Config", []);
  let pairFactory = await deployContract("PairFactory", []);
  let marginFactory = await deployContract("MarginFactory", [pairFactory.address, config.address]);
  let ammFactory = await deployContract("AmmFactory", [pairFactory.address, config.address, owner.address]);
  let router = await deployContract("Router", []);
  let routerForKeeper = await deployContract("RouterForKeeper", [pairFactory.address, weth.address]);
  let orderBook = await deployContract("OrderBook", [routerForKeeper.address]);

  return {
    weth,
    usdc,
    priceOracle,
    config,
    pairFactory,
    marginFactory,
    ammFactory,
    router,
    routerForKeeper,
    orderBook
  };
}

async function init(owner, treasury, weth, usdc, priceOracle, config, pairFactory, marginFactory, ammFactory, router, routerForKeeper) {
  await router.initialize(config.address, pairFactory.address, treasury.address, weth.address);
  await config.registerRouter(router.address);
  await config.registerRouter(routerForKeeper.address);
  await config.registerRouter(owner.address);
  await config.setPriceOracle(priceOracle.address);
  await pairFactory.init(ammFactory.address, marginFactory.address);

  await pairFactory.createPair(weth.address, usdc.address);
  await priceOracle.setReserve(weth.address, usdc.address, 10000, 20000);
}

module.exports = {
  newWallet,
  maxUint256,
  bigNumberify,
  expandDecimals,
  mineBlock,
  increaseTime,
  gasUsed,
  getNetworkFee,
  reportGasUsed,
  getBlockTime,
  getTxnBalances,
  print,
  getPriceBitArray,
  getPriceBits,
  deployContract,
  deploy,
  init
};

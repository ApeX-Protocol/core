const hre = require("hardhat");
const ethers = require("ethers");
const { Bridge } = require("arb-ts");
const { hexDataLength } = require("@ethersproject/bytes");
const { BigNumber } = require("@ethersproject/bignumber");

const walletPrivateKey = process.env.DEVNET_PRIVKEY;
const signer = new ethers.Wallet(walletPrivateKey);
const verifyStr = "npx hardhat verify --network ";
let l1Provider;
let l2Provider;
let signer1;
let signer2;
switch (process.env.network) {
  case "l1rinkeby":
    l1Provider = new ethers.providers.JsonRpcProvider("https://rinkeby.infura.io/v3/" + process.env.INFURA_KEY);
    signer2 = signer.connect(l1Provider);
    console.log("Deploying L1 Contract 👋👋");
    break;
  case "l2rinkeby":
    l1Provider = new ethers.providers.JsonRpcProvider(process.env.L1RPC);
    l2Provider = new ethers.providers.JsonRpcProvider(process.env.L2RPC);
    signer1 = signer.connect(l1Provider);
    signer2 = signer.connect(l2Provider);
    console.log("Deploying L2 Contract 👋👋");
    break;
}

const configAddress = "";
const factoryAddress = "";
const stakingFactoryAddress = "";
const baseAddress = "";
const quoteAddress = "";
const routerAddress = "";
const priceOracleTestAddress = "";
let ammAddress = "";
let marginAddress = "";
const deadline = 1953397680;
const long = 0;
const short = 1;

let l2Config;
let l2BaseToken;
let l2QuoteToken;
let l2Weth;
let l2Factory;
let l2StakingFactory;
let l2Router;
let priceOracleForTest;
let l2Amm;
let l2Margin;

let tx;
let positionItem;

const main = async () => {
  await createContracts();
};

async function createContracts() {
  const L2Config = await (await hre.ethers.getContractFactory("Config")).connect(signer2);
  const MockToken = await (await hre.ethers.getContractFactory("MockToken")).connect(signer2);
  const L2Factory = await (await hre.ethers.getContractFactory("PairFactory")).connect(signer2);
  const L2StakingFactory = await (await hre.ethers.getContractFactory("StakingFactory")).connect(signer2);
  const L2Router = await (await hre.ethers.getContractFactory("Router")).connect(signer2);
  const L2PriceOracle = await (await hre.ethers.getContractFactory("PriceOracle")).connect(signer2);
  const PriceOracleForTest = await (await hre.ethers.getContractFactory("PriceOracleForTest")).connect(signer2);
  const L2Amm = await (await hre.ethers.getContractFactory("Amm")).connect(signer2);
  const L2Margin = await (await hre.ethers.getContractFactory("Margin")).connect(signer2);

  //new config
  l2Config = await L2Config.deploy();
  await l2Config.deployed();
  console.log(`l2Config: ${l2Config.address}`);
  //new mockToken base and quote
  l2BaseToken = await MockToken.deploy("base token", "bt");
  await l2BaseToken.deployed();
  console.log(`l2BaseToken: ${l2BaseToken.address}`);
  l2QuoteToken = await MockToken.deploy("quote token", "qt");
  await l2QuoteToken.deployed();
  console.log(`l2QuoteToken: ${l2QuoteToken.address}`);
  l2Weth = await MockToken.deploy("weth token", "wt");
  await l2Weth.deployed();
  console.log(`l2Weth: ${l2Weth.address}`);
  //new factory
  l2Factory = await L2Factory.deploy(l2Config.address);
  await l2Factory.deployed();
  console.log(`l2Factory: ${l2Factory.address}`);
  //new staking factory
  l2StakingFactory = await L2StakingFactory.deploy(l2Config.address, l2Factory.address);
  await l2StakingFactory.deployed();
  console.log(`l2StakingFactory: ${l2StakingFactory.address}`);
  //new router
  l2Router = await L2Router.deploy(l2Factory.address, l2StakingFactory.address, l2Weth.address);
  await l2Router.deployed();
  console.log(`l2Router: ${l2Router.address}`);
  //new PriceOracleForTest
  priceOracleForTest = await PriceOracleForTest.deploy();
  await priceOracleForTest.deployed();
  console.log(`priceOracleForTest: ${priceOracleForTest.address}`);

  //init set
  tx = await l2Config.setPriceOracle(priceOracleForTest.address);
  await tx.wait();
  tx = await l2Config.setInitMarginRatio(800);
  await tx.wait();
  tx = await l2Config.setLiquidateThreshold(10000);
  await tx.wait();
  tx = await l2Config.setLiquidateFeeRatio(100);
  await tx.wait();
  tx = await l2Config.setRebasePriceGap(1);
  await tx.wait();
  tx = await priceOracleForTest.setReserve(l2BaseToken.address, l2QuoteToken.address, 1, 2000);
  await tx.wait();
  tx = await l2BaseToken.mint(signer2.address, ethers.utils.parseEther("10000000000000.0"));
  await tx.wait();
  tx = await l2QuoteToken.mint(signer2.address, ethers.utils.parseEther("20000000000000.0"));
  await tx.wait();
  tx = await l2BaseToken.approve(l2Router.address, ethers.constants.MaxUint256);
  await tx.wait();
  tx = await l2Router.addLiquidity(
    l2BaseToken.address,
    l2QuoteToken.address,
    ethers.utils.parseEther("100000000.0"),
    0,
    deadline,
    false
  );
  await tx.wait();

  ammAddress = await l2Factory.getAmm(l2BaseToken.address, l2QuoteToken.address);
  marginAddress = await l2Factory.getMargin(l2BaseToken.address, l2QuoteToken.address);

  l2Amm = await L2Amm.attach(ammAddress); //exist amm address
  l2Margin = await L2Margin.attach(marginAddress); //exist margin address

  console.log("ammAddress: ", ammAddress);
  console.log("marginAddress: ", marginAddress);
  console.log("✌️");
  console.log(verifyStr + process.env.network + " " + l2Config.address);
  console.log(verifyStr + process.env.network + " " + l2Factory.address + " " + l2Config.address);
  console.log(
    verifyStr + process.env.network + " " + l2StakingFactory.address + " " + l2Config.address + " " + l2Factory.address
  );
  console.log(
    verifyStr + process.env.network + " " + l2Router.address + " " + l2Factory.address + " " + l2Weth.address
  );
  console.log(verifyStr + process.env.network + " " + l2BaseToken.address + " 'base token' 'bt'");
  console.log(verifyStr + process.env.network + " " + l2QuoteToken.address + " 'quote token' 'qt'");
  console.log(verifyStr + process.env.network + " " + l2Weth.address + " 'weth token' 'wt'");
  console.log(verifyStr + process.env.network + " " + priceOracleForTest.address);

  await flowVerify(false);
}

async function flowVerify(needAttach) {
  //attach
  if (needAttach) {
    const L2Config = await (await hre.ethers.getContractFactory("Config")).connect(signer2);
    const MockToken = await (await hre.ethers.getContractFactory("MockToken")).connect(signer2);
    const L2Factory = await (await hre.ethers.getContractFactory("PairFactory")).connect(signer2);
    const L2StakingFactory = await (await hre.ethers.getContractFactory("StakingFactory")).connect(signer2);
    const L2Router = await (await hre.ethers.getContractFactory("Router")).connect(signer2);
    const L2PriceOracle = await (await hre.ethers.getContractFactory("PriceOracle")).connect(signer2);
    const PriceOracleForTest = await (await hre.ethers.getContractFactory("PriceOracleForTest")).connect(signer2);
    const L2Amm = await (await hre.ethers.getContractFactory("Amm")).connect(signer2);
    const L2Margin = await (await hre.ethers.getContractFactory("Margin")).connect(signer2);

    l2Config = await L2Config.attach(configAddress); //exist config address
    l2Factory = await L2Factory.attach(factoryAddress); //exist factory address
    l2StakingFactory = await L2StakingFactory.attach(stakingFactoryAddress);
    l2Router = await L2Router.attach(routerAddress); //exist router address
    l2BaseToken = await MockToken.attach(baseAddress); //exist base address
    l2QuoteToken = await MockToken.attach(quoteAddress); //exist quote address
    priceOracleForTest = await PriceOracleForTest.attach(priceOracleTestAddress); //exist priceOracleTest address
    l2Amm = await L2Amm.attach(ammAddress); //exist amm address
    l2Margin = await L2Margin.attach(marginAddress); //exist margin address
  }

  console.log("add liquidity...");
  tx = await l2Router.addLiquidity(
    l2BaseToken.address,
    l2QuoteToken.address,
    ethers.utils.parseEther("100000.0"),
    0,
    deadline,
    false
  );
  await tx.wait();
  tx = await l2Router.addLiquidity(
    l2BaseToken.address,
    l2QuoteToken.address,
    ethers.utils.parseEther("200000.0"),
    0,
    deadline,
    true
  );
  await tx.wait();

  //flow 1: open position with margin
  console.log("deposit...");
  tx = await l2Router.deposit(
    l2BaseToken.address,
    l2QuoteToken.address,
    signer2.address,
    ethers.utils.parseEther("1.0")
  );
  await tx.wait();

  console.log("open position with margin...");
  tx = await l2Router.openPositionWithMargin(
    l2BaseToken.address,
    l2QuoteToken.address,
    long,
    ethers.utils.parseEther("20000.0"),
    0,
    deadline
  );
  await tx.wait();
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer2.address);
  printPosition(positionItem);
  console.log("close position...");
  tx = await l2Router.closePosition(
    l2BaseToken.address,
    l2QuoteToken.address,
    BigNumber.from(positionItem[1]).abs(),
    deadline,
    false
  );
  await tx.wait();
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer2.address);
  printPosition(positionItem);

  console.log("withdraw...");
  tx = await l2Router.withdraw(l2BaseToken.address, l2QuoteToken.address, BigNumber.from(positionItem[0]).abs());
  await tx.wait();

  //flow 2: open position with wallet
  console.log("open position with wallet...");
  tx = await l2Router.openPositionWithWallet(
    l2BaseToken.address,
    l2QuoteToken.address,
    long,
    ethers.utils.parseEther("1.0"),
    ethers.utils.parseEther("20000.0"),
    0,
    deadline
  );
  await tx.wait();
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer2.address);
  printPosition(positionItem);

  console.log("close position...");
  tx = await l2Router.closePosition(
    l2BaseToken.address,
    l2QuoteToken.address,
    BigNumber.from(positionItem[1]).abs(),
    deadline,
    false
  );
  await tx.wait();
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer2.address);
  printPosition(positionItem);

  console.log("open short position with wallet...");
  tx = await l2Router.openPositionWithWallet(
    l2BaseToken.address,
    l2QuoteToken.address,
    short,
    ethers.utils.parseEther("1.0"),
    ethers.utils.parseEther("20000.0"),
    "999999999999999999999999999999",
    deadline
  );
  await tx.wait();
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer2.address);
  printPosition(positionItem);

  console.log("close position...");
  tx = await l2Router.closePosition(
    l2BaseToken.address,
    l2QuoteToken.address,
    BigNumber.from(positionItem[1]).abs(),
    deadline,
    true
  );
  await tx.wait();
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer2.address);
  printPosition(positionItem);

  //flow 3: liquidate
  console.log("open position with wallet...");
  tx = await l2Router.openPositionWithWallet(
    l2BaseToken.address,
    l2QuoteToken.address,
    long,
    ethers.utils.parseEther("1.0"),
    ethers.utils.parseEther("20000.0"),
    0,
    deadline
  );
  await tx.wait();
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer2.address);
  printPosition(positionItem);

  let withdrawable = await l2Margin.getWithdrawable(signer2.address);
  tx = await l2Router.withdraw(l2BaseToken.address, l2QuoteToken.address, BigNumber.from(withdrawable).abs());
  await tx.wait();

  console.log("set price...");
  tx = await priceOracleForTest.setReserve(l2BaseToken.address, l2QuoteToken.address, 1, 400);
  await tx.wait();
  console.log("rebase...");
  tx = await l2Amm.rebase();
  await tx.wait();

  console.log("liquidate position...");
  tx = await l2Margin.liquidate(signer2.address);
  await tx.wait();
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer2.address);
  printPosition(positionItem);

  //flow 4: close liquidatable position
  console.log("set price...");
  tx = await priceOracleForTest.setReserve(l2BaseToken.address, l2QuoteToken.address, 1, 400);
  await tx.wait();
  console.log("rebase...");
  tx = await l2Amm.rebase();
  await tx.wait();

  console.log("open short position with wallet...");
  tx = await l2Router.openPositionWithWallet(
    l2BaseToken.address,
    l2QuoteToken.address,
    short,
    ethers.utils.parseEther("1.0"),
    ethers.utils.parseEther("4000.0"),
    "999999999999999999999999999999",
    deadline
  );
  await tx.wait();
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer2.address);
  printPosition(positionItem);

  withdrawable = await l2Margin.getWithdrawable(signer2.address);
  tx = await l2Router.withdraw(l2BaseToken.address, l2QuoteToken.address, BigNumber.from(withdrawable).abs());
  await tx.wait();

  console.log("set price...");
  tx = await priceOracleForTest.setReserve(l2BaseToken.address, l2QuoteToken.address, 1, 2000);
  await tx.wait();
  console.log("rebase...");
  tx = await l2Amm.rebase();
  await tx.wait();

  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer2.address);
  printPosition(positionItem);
  console.log("close liquidatable position...");
  tx = await l2Router.closePosition(
    l2BaseToken.address,
    l2QuoteToken.address,
    BigNumber.from(positionItem[1]).abs(),
    deadline,
    false
  );
  await tx.wait();
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer2.address);
  printPosition(positionItem);
}

function printPosition(positionItem) {
  console.log(
    "after open, current baseSize and quoteSize and tradeSize abs: ",
    BigNumber.from(positionItem[0]).toString(),
    BigNumber.from(positionItem[1]).toString(),
    BigNumber.from(positionItem[2]).toString()
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

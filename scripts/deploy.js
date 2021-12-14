const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";
const deadline = 1953397680;
const long = 0;
const short = 1;
const v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; // UniswapV3Factory
const v2FactoryAddress = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4"; // SushiV2Factory

const configAddress = "0xa1dF9DFC60EC115B79469b53D4C5391B60e9cf83";
const baseAddress = "0x6fB0705354106878D6256F7496431Bf896C21165";
const quoteAddress = "0xef6B05791E766BA8DACe982f4cCC97ADD8F3dd91";
const factoryAddress = "0x7fFEd382322b1bA438088938347eB600f1d71e3E";
const pcvTreasuryAddress = "0xC541bbE9Be3Da46FECA0658D9842Af3a1dCA59fF";
const routerAddress = "0xd46d02552bdb5dFa9a18F02324E30965238788Ea";
const priceOracleForTestAddress = "0xB4A11c25e3120cA3709b54B863797fCBCB161875";
const ammFactoryAddress = "0xCdD16961b5B66dF1D7034EdE9393372168CE5CcD";
const marginFactoryAddress = "0x2064f03b5eDb30AEFef8e08206667e9cE8446810";

let signer;
let l2Config;
let l2BaseToken;
let l2QuoteToken;
let l2Weth;
let l2Factory;
let l2PcvTreasury;
let l2Router;
let priceOracleForTest;
let l2Amm;
let l2Margin;
let l2AmmFactory;
let l2MarginFactory;
let apexToken;
let positionItem;

const main = async () => {
  await createContracts();
  // await flowVerify(true);
};

async function createContracts() {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  const Config = await ethers.getContractFactory("Config");
  const MockToken = await ethers.getContractFactory("MockToken");
  const L2Factory = await ethers.getContractFactory("PairFactory");
  const L2PcvTreasury = await ethers.getContractFactory("PCVTreasury");
  const L2Router = await ethers.getContractFactory("Router");
  const PriceOracleForTest = await ethers.getContractFactory("PriceOracleForTest");
  // const PriceOracle = await ethers.getContractFactory("PriceOracle");
  const L2Amm = await ethers.getContractFactory("Amm");
  const L2Margin = await ethers.getContractFactory("Margin");
  const L2AmmFactory = await ethers.getContractFactory("AmmFactory");
  const L2MarginFactory = await ethers.getContractFactory("MarginFactory");
  const ApeXToken = await ethers.getContractFactory("ApeXToken");

  l2Config = await upgrades.deployProxy(Config, [signer]);
  await l2Config.deployed();
  console.log(`const configAddress = "${l2Config.address}"`);

  l2BaseToken = await MockToken.deploy("base token", "btc");
  await l2BaseToken.deployed();
  console.log(`const baseAddress = "${l2BaseToken.address}"`);

  l2QuoteToken = await MockToken.deploy("quote token", "usd");
  await l2QuoteToken.deployed();
  console.log(`const quoteAddress = "${l2QuoteToken.address}"`);

  l2Weth = await MockToken.deploy("weth token", "wt");
  await l2Weth.deployed();

  l2Factory = await L2Factory.deploy();
  await l2Factory.deployed();
  console.log(`const factoryAddress = "${l2Factory.address}"`);

  apexToken = await ApeXToken.deploy();
  await apexToken.deployed();

  l2PcvTreasury = await L2PcvTreasury.deploy(apexToken.address);
  await l2PcvTreasury.deployed();
  console.log(`const pcvTreasuryAddress = "${l2PcvTreasury.address}"`);

  l2Router = await L2Router.deploy(l2Factory.address, l2PcvTreasury.address, l2Weth.address);
  await l2Router.deployed();
  console.log(`const routerAddress = "${l2Router.address}"`);

  priceOracleForTest = await PriceOracleForTest.deploy();
  await priceOracleForTest.deployed();
  console.log(`const priceOracleForTestAddress = "${priceOracleForTest.address}"`);

  // priceOracle = await PriceOracle.deploy();
  // await priceOracle.deployed();
  // console.log(`const priceOracleAddress = "${priceOracle.address}"`);

  l2AmmFactory = await L2AmmFactory.deploy(l2Factory.address, l2Config.address, l2PcvTreasury.address);
  await l2AmmFactory.deployed();
  console.log(`const ammFactoryAddress = "${l2AmmFactory.address}"`);

  l2MarginFactory = await L2MarginFactory.deploy(l2Factory.address, l2Config.address);
  await l2MarginFactory.deployed();
  console.log(`const marginFactoryAddress = "${l2MarginFactory.address}"`);

  //init set
  await l2Factory.init(l2AmmFactory.address, l2MarginFactory.address);
  await l2Factory.createPair(l2BaseToken.address, l2QuoteToken.address);
  await l2Config.setBeta(100);
  await l2Config.setPriceOracle(priceOracleForTest.address);
  await l2Config.setInitMarginRatio(800);
  await l2Config.setLiquidateThreshold(10000);
  await l2Config.setLiquidateFeeRatio(100);
  await l2Config.setRebasePriceGap(1);
  await l2Config.setFeeParameter(150);
  await l2Config.setMaxCPFBoost(10);
  await priceOracleForTest.setReserve(l2BaseToken.address, l2QuoteToken.address, 1, 2000);
  await l2BaseToken.mint(signer, ethers.utils.parseEther("10000000000000.0"));
  await l2QuoteToken.mint(signer, ethers.utils.parseEther("20000000000000.0"));
  await l2BaseToken.approve(l2Router.address, ethers.constants.MaxUint256);
  await l2Router.addLiquidity(
    l2BaseToken.address,
    l2QuoteToken.address,
    ethers.utils.parseEther("100000000.0"),
    0,
    deadline,
    false
  );
  await l2Config.registerRouter(l2Router.address);

  let ammAddress = await l2Factory.getAmm(l2BaseToken.address, l2QuoteToken.address);
  let marginAddress = await l2Factory.getMargin(l2BaseToken.address, l2QuoteToken.address);

  l2Amm = await L2Amm.attach(ammAddress); //exist amm address
  l2Margin = await L2Margin.attach(marginAddress); //exist margin address

  console.log("ammAddress: ", ammAddress);
  console.log("marginAddress: ", marginAddress);
  console.log("✌️");
  console.log(verifyStr, process.env.HARDHAT_NETWORK, l2Config.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, l2Factory.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, l2PcvTreasury.address, l2Config.address, l2Factory.address);
  console.log(
    verifyStr,
    process.env.HARDHAT_NETWORK,
    l2Router.address,
    l2Factory.address,
    l2PcvTreasury.address,
    l2Weth.address
  );
  console.log(verifyStr, process.env.HARDHAT_NETWORK, l2BaseToken.address, "'base token' 'btc'");
  console.log(verifyStr, process.env.HARDHAT_NETWORK, l2QuoteToken.address, "'quote token' 'usd'");
  console.log(verifyStr, process.env.HARDHAT_NETWORK, l2Weth.address, "'weth token' 'wt'");
  console.log(verifyStr, process.env.HARDHAT_NETWORK, priceOracleForTest.address);

  await flowVerify(false);
}

async function flowVerify(needAttach) {
  //attach
  if (needAttach) {
    const accounts = await hre.ethers.getSigners();
    signer = accounts[0].address;
    const L2Config = await ethers.getContractFactory("Config");
    const MockToken = await ethers.getContractFactory("MockToken");
    const L2Factory = await ethers.getContractFactory("PairFactory");
    const L2PcvTreasury = await ethers.getContractFactory("PCVTreasury");
    const L2Router = await ethers.getContractFactory("Router");
    const PriceOracleForTest = await ethers.getContractFactory("PriceOracleForTest");
    const L2Amm = await ethers.getContractFactory("Amm");
    const L2Margin = await ethers.getContractFactory("Margin");
    const L2AmmFactory = await ethers.getContractFactory("AmmFactory");
    const L2MarginFactory = await ethers.getContractFactory("MarginFactory");

    l2Config = await L2Config.attach(configAddress); //exist config address
    l2Factory = await L2Factory.attach(factoryAddress); //exist factory address
    l2PcvTreasury = await L2PcvTreasury.attach(pcvTreasuryAddress);
    l2Router = await L2Router.attach(routerAddress); //exist router address
    l2BaseToken = await MockToken.attach(baseAddress); //exist base address
    l2QuoteToken = await MockToken.attach(quoteAddress); //exist quote address
    priceOracleForTest = await PriceOracleForTest.attach(priceOracleForTestAddress); //exist priceOracleForTest address
    l2AmmFactory = await L2AmmFactory.attach(ammFactoryAddress); //exist margin address
    l2MarginFactory = await L2MarginFactory.attach(marginFactoryAddress); //exist margin address

    let ammAddress = await l2Factory.getAmm(l2BaseToken.address, l2QuoteToken.address);
    let marginAddress = await l2Factory.getMargin(l2BaseToken.address, l2QuoteToken.address);
    l2Amm = await L2Amm.attach(ammAddress); //exist amm address
    l2Margin = await L2Margin.attach(marginAddress); //exist margin address
  }

  //flow 1: open position with margin
  console.log("deposit...");
  await l2Router.deposit(l2BaseToken.address, l2QuoteToken.address, signer, ethers.utils.parseEther("1.0"));
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  console.log("open position with margin...");
  await l2Router.openPositionWithMargin(
    l2BaseToken.address,
    l2QuoteToken.address,
    long,
    ethers.utils.parseEther("20000.0"),
    0,
    deadline
  );
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  console.log("close position...");
  await l2Router.closePosition(
    l2BaseToken.address,
    l2QuoteToken.address,
    BigNumber.from(positionItem[1]).abs(),
    deadline,
    false
  );
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  console.log("withdraw...");
  await l2Router.withdraw(l2BaseToken.address, l2QuoteToken.address, BigNumber.from(positionItem[0]).abs());
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  //flow 2: open position with wallet
  console.log("open position with wallet...");
  await l2Router.openPositionWithWallet(
    l2BaseToken.address,
    l2QuoteToken.address,
    long,
    ethers.utils.parseEther("1.0"),
    ethers.utils.parseEther("20000.0"),
    0,
    deadline
  );
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  console.log("close position...");
  await l2Router.closePosition(
    l2BaseToken.address,
    l2QuoteToken.address,
    BigNumber.from(positionItem[1]).abs(),
    deadline,
    false
  );
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  console.log("open short position with wallet...");
  await l2Router.openPositionWithWallet(
    l2BaseToken.address,
    l2QuoteToken.address,
    short,
    ethers.utils.parseEther("1.0"),
    ethers.utils.parseEther("20000.0"),
    "999999999999999999999999999999",
    deadline
  );
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  console.log("close position...");
  await l2Router.closePosition(
    l2BaseToken.address,
    l2QuoteToken.address,
    BigNumber.from(positionItem[1]).abs(),
    deadline,
    true
  );
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  //flow 3: liquidate
  console.log("open position with wallet...");
  await l2Router.openPositionWithWallet(
    l2BaseToken.address,
    l2QuoteToken.address,
    long,
    ethers.utils.parseEther("1.0"),
    ethers.utils.parseEther("20000.0"),
    0,
    deadline
  );
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  console.log("withdraw withdrawable...");
  let withdrawable = await l2Margin.getWithdrawable(signer);
  await l2Router.withdraw(l2BaseToken.address, l2QuoteToken.address, BigNumber.from(withdrawable).abs());
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  console.log("set price to 200...");
  await priceOracleForTest.setReserve(l2BaseToken.address, l2QuoteToken.address, 1, 200);
  console.log("rebase...");
  await l2Amm.rebase();
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  console.log("liquidate position...");
  await l2Margin.liquidate(signer);
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  //flow 4: close liquidatable position
  console.log("open short position with wallet...");
  await l2Router.openPositionWithWallet(
    l2BaseToken.address,
    l2QuoteToken.address,
    short,
    ethers.utils.parseEther("1.0"),
    ethers.utils.parseEther("2000.0"),
    "999999999999999999999999999999",
    deadline
  );
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  console.log("withdraw withdrawable...");
  withdrawable = await l2Margin.getWithdrawable(signer);
  console.log("withdrawable: ", withdrawable.toString());
  await l2Router.withdraw(l2BaseToken.address, l2QuoteToken.address, BigNumber.from(withdrawable).abs());
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  console.log("set price to 2000...");
  await priceOracleForTest.setReserve(l2BaseToken.address, l2QuoteToken.address, 1, 2000);
  console.log("rebase...");
  await l2Amm.rebase();
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);

  console.log("close liquidatable position...");
  await l2Router.closePosition(
    l2BaseToken.address,
    l2QuoteToken.address,
    BigNumber.from(positionItem[1]).abs(),
    deadline,
    false
  );
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, signer);
  await printPosition(positionItem);
}

async function printPosition(positionItem) {
  console.log(
    "after operate, current baseSize and quoteSize and tradeSize abs and realizedPnl: ",
    BigNumber.from(positionItem[0]).toString(),
    BigNumber.from(positionItem[1]).toString(),
    BigNumber.from(positionItem[2]).toString()
  );
  await sleep();
}

function sleep(ms = 10000) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

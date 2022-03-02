const { expect } = require("chai");
const { BigNumber } = require("@ethersproject/bignumber");

describe("Simulations", function () {
  let owner;
  let treasury;
  let weth;
  let router;
  let priceOracle;
  let apeXToken;
  let baseToken;
  let quoteToken;
  let v3factory;
  let pool1;
  let config;

  const tokenQuantity = "1000000000000";
  const infDeadline = "9999999999";

  beforeEach(async function () {
    [owner, treasury, alice, bob, carol, arbitrageur] = await ethers.getSigners();

    const MockWETH = await ethers.getContractFactory("MockWETH");
    weth = await MockWETH.deploy();

    const MockToken = await ethers.getContractFactory("MockToken");
    apeXToken = await MockToken.deploy("ApeX Token", "APEX");
    baseToken = await MockToken.deploy("Base Token", "BT");
    quoteToken = await MockToken.deploy("Quote Token", "QT");

    const Config = await ethers.getContractFactory("Config");
    config = await Config.deploy();

    const MockUniswapV3Factory = await ethers.getContractFactory("MockUniswapV3Factory");
    v3factory = await MockUniswapV3Factory.deploy();
    const MockUniswapV3Pool = await ethers.getContractFactory("MockUniswapV3Pool");
    pool1 = await MockUniswapV3Pool.deploy(baseToken.address, quoteToken.address, 500);
    await pool1.setLiquidity(1000000000);
    await v3factory.setPool(baseToken.address, quoteToken.address, 500, pool1.address);

    const PriceOracle = await ethers.getContractFactory("PriceOracleForTest");
    priceOracle = await PriceOracle.deploy();
    //await priceOracle.initialize(v3factory.address);
    await priceOracle.setReserve(baseToken.address, apeXToken.address, 10000000, 20000000);
    await priceOracle.setReserve(baseToken.address, quoteToken.address, 10000000, 20000000);
    await priceOracle.setReserve(weth.address, quoteToken.address, 10000000, 20000000);
    await config.setPriceOracle(priceOracle.address);

    const PairFactory = await ethers.getContractFactory("PairFactory");
    pairFactory = await PairFactory.deploy();

    const AmmFactory = await ethers.getContractFactory("AmmFactory");
    const MarginFactory = await ethers.getContractFactory("MarginFactory");
    let ammFactory = await AmmFactory.deploy(pairFactory.address, config.address, owner.address);
    let marginFactory = await MarginFactory.deploy(pairFactory.address, config.address);
    await pairFactory.init(ammFactory.address, marginFactory.address);
    await pairFactory.createPair(baseToken.address, quoteToken.address);

    const Router = await ethers.getContractFactory("Router");
    router = await Router.deploy(pairFactory.address, treasury.address, weth.address);
    await config.registerRouter(router.address);
  });

  describe("check pool pnl given beta", function () {
    it("liquidates a position properly", async function () {
      await config.setBeta(100);
      await baseToken.mint(alice.address, tokenQuantity);
      await baseToken.connect(alice).approve(router.address, tokenQuantity);
      await baseToken.mint(bob.address, tokenQuantity);
      await baseToken.connect(bob).approve(router.address, tokenQuantity);
      let ammAddress = pairFactory.getAmm(baseToken.address, quoteToken.address);
      await baseToken.mint(ammAddress, "100000000000000000000");
      //await router.connect(alice).openPositionWithWallet(baseToken.address, quoteToken.address, 0, 3300, 10000, 1, infDeadline);
      //await routerBob.openPositionWithWallet(baseToken.address, quoteToken.address, 1, 3300, 10000, 1, 9999999999);
      //await router.closePosition(baseToken.address, quoteToken.address, 10000, 9999999999, true);
    });
  });
  /*
  describe("simulation involving arbitrageur and random trades", function () {
    it("generates simulation data", async function () {
      await config.setBeta(100);
      await baseToken.mint(owner.address, 10000000000);
      await baseToken.approve(router.address, 10000000000);
      await router.addLiquidity(baseToken.address, quoteToken.address, 1000000, 1, 9999999999, false);
      await router.openPositionWithWallet(baseToken.address, quoteToken.address, 0, 3300, 10000, 1, 9999999999);
      await router.closePosition(baseToken.address, quoteToken.address, 10000, 9999999999, true);
    });
  });
  */
});

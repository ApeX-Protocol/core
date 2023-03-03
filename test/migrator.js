const { expect } = require("chai");
const { BigNumber } = require("@ethersproject/bignumber");
const { ethers } = require("hardhat");

describe("Migrator contract", function () {
  let owner;
  let treasury;
  let weth;
  let oldRouter;
  let newRouter;
  let oldPairFactory;
  let priceOracle;
  let apeXToken;
  let baseToken;
  let quoteToken;
  let migrator;

  beforeEach(async function () {
    [owner, treasury] = await ethers.getSigners();

    const MockWETH = await ethers.getContractFactory("MockWETH");
    weth = await MockWETH.deploy();

    const MockToken = await ethers.getContractFactory("MockToken");
    apeXToken = await MockToken.deploy("ApeX Token", "APEX");
    baseToken = await MockToken.deploy("Base Token", "BT");
    quoteToken = await MockToken.deploy("Quote Token", "QT");

    const Config = await ethers.getContractFactory("Config");
    let config = await Config.deploy();

    const PriceOracle = await ethers.getContractFactory("PriceOracleForTest");
    priceOracle = await PriceOracle.deploy();
    await priceOracle.setReserve(baseToken.address, apeXToken.address, 10000000, 20000000);
    await priceOracle.setReserve(baseToken.address, quoteToken.address, 10000000, 20000000);
    await priceOracle.setReserve(weth.address, quoteToken.address, 10000000, 20000000);
    await config.setPriceOracle(priceOracle.address);

    const PairFactory = await ethers.getContractFactory("PairFactory");
    const AmmFactory = await ethers.getContractFactory("AmmFactory");
    const MarginFactory = await ethers.getContractFactory("MarginFactory");
    oldPairFactory = await PairFactory.deploy();
    let oldAmmFactory = await AmmFactory.deploy(oldPairFactory.address, config.address, owner.address);
    let oldMarginFactory = await MarginFactory.deploy(oldPairFactory.address, config.address);
    await oldPairFactory.init(oldAmmFactory.address, oldMarginFactory.address);

    let newPairFactory = await PairFactory.deploy();
    let newAmmFactory = await AmmFactory.deploy(newPairFactory.address, config.address, owner.address);
    let newMarginFactory = await MarginFactory.deploy(newPairFactory.address, config.address);
    await newPairFactory.init(newAmmFactory.address, newMarginFactory.address);

    const Router = await ethers.getContractFactory("Router");
    oldRouter = await Router.deploy();
    await oldRouter.initialize(config.address, oldPairFactory.address, treasury.address, weth.address);
    await config.registerRouter(oldRouter.address);

    newRouter = await Router.deploy();
    await newRouter.initialize(config.address, newPairFactory.address, treasury.address, weth.address);
    await config.registerRouter(newRouter.address);

    const Migrator = await ethers.getContractFactory("Migrator");
    migrator = await Migrator.deploy(oldRouter.address, newRouter.address);
    await config.registerRouter(migrator.address);
  });

  describe("migrate", function () {
    it("migrate", async function () {
      await baseToken.mint(owner.address, 200000000);
      await baseToken.approve(oldRouter.address, 100000000);
      await baseToken.approve(newRouter.address, 100000000);
      await oldRouter.addLiquidity(baseToken.address, quoteToken.address, 100000000, 1, 9999999999, false);
      await newRouter.addLiquidity(baseToken.address, quoteToken.address, 100000000, 1, 9999999999, false);
      let ammAddress = await oldPairFactory.getAmm(baseToken.address, quoteToken.address);
      const Amm = await ethers.getContractFactory("Amm");
      let amm = await Amm.attach(ammAddress);
      await amm.approve(migrator.address, BigNumber.from("100000000000000000000000000000000000"));
      await migrator.migrate(baseToken.address, quoteToken.address);
    });
  });
});

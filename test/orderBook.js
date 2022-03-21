const { expect } = require("chai");

let owner;
let weth;
let config;
let pairFactory;
let marginFactory;
let ammFactory;
let routerForKeeper;
let orderBook;
let aLongPosition = {
  baseToken: "0x1067256b996A020Ced3013B92cfB3746204B898C",
  quoteToken: "0x1067256b996A020Ced3013B92cfB3746204B898C",
  marginAmount: 10000,
  baseAmountLimit: 10000,
  quoteAmount: 10000,
  executionFee: 10000,
  deadline: 10000,
  isLong: true,
};

describe("OrderBook Contract", function () {
  beforeEach(async function () {
    [owner] = await ethers.getSigners();

    const MockWETH = await ethers.getContractFactory("MockWETH");
    weth = await MockWETH.deploy();

    const Config = await ethers.getContractFactory("Config");
    config = await Config.deploy();

    const PairFactory = await ethers.getContractFactory("PairFactory");
    pairFactory = await PairFactory.deploy();

    const MarginFactory = await ethers.getContractFactory("MarginFactory");
    marginFactory = await MarginFactory.deploy(pairFactory.address, config.address);

    const AmmFactory = await ethers.getContractFactory("AmmFactory");
    ammFactory = await AmmFactory.deploy(pairFactory.address, config.address, owner.address);

    const RouterForKeeper = await ethers.getContractFactory("RouterForKeeper");
    routerForKeeper = await RouterForKeeper.deploy(pairFactory.address, weth.address);

    const OrderBook = await ethers.getContractFactory("OrderBook");
    orderBook = await OrderBook.deploy(routerForKeeper.address);

    await pairFactory.init(ammFactory.address, marginFactory.address);
  });

  describe("routerForKeeper", function () {
    it("routerForKeeper", async function () {
      expect(await orderBook.routerForKeeper()).to.be.equal(routerForKeeper.address);
    });
  });

  describe("executeOpenPositionOrder", function () {
    it("execute a new open position order", async function () {});
  });

  describe("executeClosePositionOrder", function () {
    it("execute a new close position order", async function () {});
  });
});

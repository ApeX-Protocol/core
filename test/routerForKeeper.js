const { expect } = require("chai");
const exp = require("constants");
const { ethers } = require("hardhat");

let owner;
let treasury;
let addr1;
let router;

let weth;
let usdc;
let priceOracle;
let config;
let pairFactory;
let marginFactory;
let ammFactory;
let routerForKeeper;
let order;

describe("RouterForKeeper Contract", function () {
  beforeEach(async function () {
    [owner, treasury, addr1] = await ethers.getSigners();

    const MockWETH = await ethers.getContractFactory("MockWETH");
    weth = await MockWETH.deploy();

    const MockToken = await ethers.getContractFactory("MockToken");
    usdc = await MockToken.deploy("mock usdc", "musdc");

    const PriceOracleForTest = await ethers.getContractFactory("PriceOracleForTest");
    priceOracle = await PriceOracleForTest.deploy();

    const Config = await ethers.getContractFactory("Config");
    config = await Config.deploy();

    const PairFactory = await ethers.getContractFactory("PairFactory");
    pairFactory = await PairFactory.deploy();

    const MarginFactory = await ethers.getContractFactory("MarginFactory");
    marginFactory = await MarginFactory.deploy(pairFactory.address, config.address);

    const AmmFactory = await ethers.getContractFactory("AmmFactory");
    ammFactory = await AmmFactory.deploy(pairFactory.address, config.address, owner.address);

    const Router = await ethers.getContractFactory("Router");
    router = await Router.deploy();
    await router.initialize(config.address, pairFactory.address, treasury.address, weth.address);

    const RouterForKeeper = await ethers.getContractFactory("RouterForKeeper");
    routerForKeeper = await RouterForKeeper.deploy(pairFactory.address, weth.address);

    await config.registerRouter(router.address);
    await config.registerRouter(routerForKeeper.address);
    await config.registerRouter(owner.address);
    await config.setPriceOracle(priceOracle.address);
    await pairFactory.init(ammFactory.address, marginFactory.address);

    await pairFactory.createPair(weth.address, usdc.address);
    await priceOracle.setReserve(weth.address, usdc.address, 10000, 20000);
    await weth.approve(router.address, 100000000000000);
    await router.addLiquidity(weth.address, usdc.address, 100000000000000, 0, 9999999999, false);

    await usdc.mint(owner.address, 10000000);
    await weth.approve(routerForKeeper.address, 10000000);

    // await routerForKeeper.deposit(weth.address, owner.address, 10000000);
    // expect(await routerForKeeper.balanceOf(weth.address, owner.address)).to.be.equal(10000000);
    order = {
      routerToExecute: routerForKeeper.address,
      trader: owner.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 0,
      baseAmount: 10000,
      quoteAmount: 30000,
      slippage: 500,
      limitPrice: "2100000000000000000", //2.1
      deadline: 999999999999,
      withWallet: true,
      nonce: ethers.utils.formatBytes32String("this is open long nonce"),
    };

    wrongOrder = {
      routerToExecute: routerForKeeper.address,
      trader: addr1.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 0,
      baseAmount: 0, //wrong amount
      quoteAmount: 30000,
      slippage: 500,
      limitPrice: "2100000000000000000",
      deadline: 999999999999,
      withWallet: true,
      nonce: ethers.utils.formatBytes32String("this is wrong open long nonce"),
    };

    orderShort = {
      routerToExecute: routerForKeeper.address,
      trader: owner.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 1,
      baseAmount: 10000,
      quoteAmount: 30000,
      slippage: 500,
      limitPrice: "1900000000000000000", //1.9
      deadline: 999999999999,
      withWallet: true,
      nonce: ethers.utils.formatBytes32String("this is open short nonce"),
    };

    closeOrder = {
      routerToExecute: routerForKeeper.address,
      trader: owner.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 0,
      quoteAmount: 30000,
      limitPrice: "1900000000000000000", //1.9
      deadline: 999999999999,
      autoWithdraw: false,
      nonce: ethers.utils.formatBytes32String("this is close long nonce"),
    };

    closeOrderShort = {
      routerToExecute: routerForKeeper.address,
      trader: owner.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 1,
      quoteAmount: 30000,
      limitPrice: "2100000000000000000", //2.1
      deadline: 999999999999,
      autoWithdraw: false,
      nonce: ethers.utils.formatBytes32String("this is close short nonce"),
    };
  });

  describe("deposit", function () {
    it("can deposit to routerForKeeper", async function () {
      await weth.approve(routerForKeeper.address, 10);
      await routerForKeeper.deposit(weth.address, addr1.address, 10);
      expect(await routerForKeeper.balanceOf(weth.address, addr1.address)).to.be.equal(10);
    });

    it("revert when no allowance", async function () {
      await expect(routerForKeeper.deposit(weth.address, addr1.address, 10000001)).to.be.revertedWith(
        "TransferHelper::transferFrom: transferFrom failed"
      );
    });
  });

  describe("depositETH", function () {
    it("can deposit eth to routerForKeeper", async function () {
      await routerForKeeper.depositETH(addr1.address, { value: 10 });
      expect(await routerForKeeper.balanceOf(weth.address, addr1.address)).to.be.equal(10);
      expect(await weth.balanceOf(routerForKeeper.address)).to.be.equal(10);
    });
  });

  describe("withdraw", function () {
    beforeEach(async function () {
      await weth.approve(routerForKeeper.address, 10);
      await routerForKeeper.deposit(weth.address, addr1.address, 10);
    });

    it("can withdraw weth", async function () {
      await routerForKeeper.connect(addr1).withdraw(weth.address, addr1.address, 5);
      expect(await routerForKeeper.balanceOf(weth.address, addr1.address)).to.be.equal(5);
      expect(await weth.balanceOf(addr1.address)).to.be.equal(5);
    });
  });

  describe("withdrawETH", function () {
    beforeEach(async function () {
      await routerForKeeper.depositETH(addr1.address, { value: 10 });
    });

    it("can withdraw eth", async function () {
      await routerForKeeper.connect(addr1).withdrawETH(addr1.address, 5);
      expect(await routerForKeeper.balanceOf(weth.address, addr1.address)).to.be.equal(5);
    });
  });

  describe("openPositionWithWallet", function () {
    beforeEach(async function () {
      await routerForKeeper.depositETH(owner.address, { value: 10 });
    });

    it("can open position with wallet", async function () {
      await routerForKeeper.depositETH(owner.address, { value: 1000000 });
      await routerForKeeper.openPositionWithWallet(order, 0);
    });

    it("revert when open position with wrong pair", async function () {
      order.baseToken = owner.address;
      await expect(routerForKeeper.openPositionWithWallet(order, 0)).to.be.revertedWith(
        "RouterForKeeper.openPositionWithWallet: NOT_FOUND_MARGIN"
      );
    });

    it("revert when open position with invalid side", async function () {
      order.side = 2;
      await expect(routerForKeeper.openPositionWithWallet(order, 0)).to.be.revertedWith(
        "RouterForKeeper.openPositionWithWallet: INVALID_SIDE"
      );
    });

    it("revert when open position exceed balance", async function () {
      await expect(routerForKeeper.openPositionWithWallet(order, 0)).to.be.revertedWith(
        "RouterForKeeper.openPositionWithWallet: NO_SUFFICIENT_MARGIN"
      );
    });

    it("revert when open long position exceed limit", async function () {
      await routerForKeeper.depositETH(owner.address, { value: 1000000 });
      await expect(routerForKeeper.openPositionWithWallet(order, "3002135611318739989")).to.be.revertedWith(
        "RouterForKeeper.openPositionWithWallet: INSUFFICIENT_QUOTE_AMOUNT"
      );
    });

    it("revert when open short position exceed limit", async function () {
      await routerForKeeper.depositETH(owner.address, { value: 1000000 });
      await expect(routerForKeeper.openPositionWithWallet(orderShort, 0)).to.be.revertedWith(
        "RouterForKeeper.openPositionWithWallet: INSUFFICIENT_QUOTE_AMOUNT"
      );
    });
  });

  describe("openPositionWithMargin", function () {
    beforeEach(async function () {
      await weth.approve(router.address, 100000000);
      await router.deposit(weth.address, usdc.address, owner.address, 10);
    });

    it("can open position with margin", async function () {
      await router.deposit(weth.address, usdc.address, owner.address, 1000000);
      await routerForKeeper.openPositionWithMargin(order, 0);
    });

    it("revert when open position with wrong pair", async function () {
      order.baseToken = owner.address;
      await expect(routerForKeeper.openPositionWithMargin(order, 0)).to.be.revertedWith(
        "RouterForKeeper.openPositionWithMargin: NOT_FOUND_MARGIN"
      );
    });

    it("revert when open position with invalid side", async function () {
      order.side = 2;
      await expect(routerForKeeper.openPositionWithMargin(order, 0)).to.be.revertedWith(
        "RouterForKeeper.openPositionWithMargin: INVALID_SIDE"
      );
    });

    it("revert when open long position exceed limit", async function () {
      await router.deposit(weth.address, usdc.address, owner.address, 1000000);
      await expect(routerForKeeper.openPositionWithMargin(order, "3002135611318739989")).to.be.revertedWith(
        "RouterForKeeper.openPositionWithMargin: INSUFFICIENT_QUOTE_AMOUNT"
      );
    });

    it("revert when open short position exceed limit", async function () {
      await router.deposit(weth.address, usdc.address, owner.address, 1000000);
      await expect(routerForKeeper.openPositionWithMargin(orderShort, 0)).to.be.revertedWith(
        "RouterForKeeper.openPositionWithMargin: INSUFFICIENT_QUOTE_AMOUNT"
      );
    });
  });

  describe("closePosition", function () {
    beforeEach(async function () {
      await weth.approve(router.address, 100000000);
      await router.deposit(weth.address, usdc.address, owner.address, 1000000);
      await routerForKeeper.openPositionWithMargin(order, 800);
    });

    it("can close position", async function () {
      await routerForKeeper.closePosition(closeOrder);
    });

    it("revert when open position with wrong pair", async function () {
      closeOrder.baseToken = owner.address;
      await expect(routerForKeeper.closePosition(closeOrder)).to.be.revertedWith(
        "RouterForKeeper.closePosition: NOT_FOUND_MARGIN"
      );
    });

    it("revert when close a long position with side=1", async function () {
      closeOrder.side = 1;
      await expect(routerForKeeper.closePosition(closeOrder)).to.be.revertedWith(
        "RouterForKeeper.closePosition: SIDE_NOT_MATCH"
      );
    });

    it("revert when close a short position with side=0", async function () {
      await weth.connect(addr1).deposit({ value: 100000000000000 });
      await weth.connect(addr1).approve(router.address, 100000000000000);
      await router.connect(addr1).deposit(weth.address, usdc.address, addr1.address, 1000000);
      orderShort.trader = addr1.address;
      await routerForKeeper.connect(addr1).openPositionWithMargin(orderShort, "3002135611318739989");

      closeOrderShort.side = 0;
      closeOrderShort.trader = addr1.address;
      await expect(routerForKeeper.connect(addr1).closePosition(closeOrderShort)).to.be.revertedWith(
        "RouterForKeeper.closePosition: SIDE_NOT_MATCH"
      );
    });
  });
});

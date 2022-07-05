const { expect, use } = require("chai");
const { utils } = require("ethers");
const { waffle } = require("hardhat");
const { solidity } = require("ethereum-waffle");
const { deploy, init } = require("../shared/utilities");
const { BigNumber } = require("@ethersproject/bignumber");

use(solidity);

describe("RouterForKeeper UT", function () {
  const provider = waffle.provider;
  let [owner, treasury, addr1] = provider.getWallets();

  let weth,
    usdc,
    priceOracle,
    config,
    pairFactory,
    marginFactory,
    ammFactory,
    router,
    routerForKeeper,
    order,
    orderBook;

  beforeEach(async function () {
    ({ weth, usdc, priceOracle, config, pairFactory, marginFactory, ammFactory, router, routerForKeeper, orderBook } =
      await deploy(owner));
    await init(
      owner,
      treasury,
      weth,
      usdc,
      priceOracle,
      config,
      pairFactory,
      marginFactory,
      ammFactory,
      router,
      routerForKeeper
    );

    await weth.approve(router.address, BigNumber.from("1000000000000000000000000000"));
    await router.addLiquidity(
      weth.address,
      usdc.address,
      BigNumber.from("1000000000000000000000000"),
      0,
      9999999999,
      false
    );

    await weth.approve(routerForKeeper.address, BigNumber.from("1000000000000000000000000000"));
    await routerForKeeper.setOrderBook(owner.address);
    await routerForKeeper.setKeeper(owner.address);

    order = {
      routerToExecute: routerForKeeper.address,
      trader: owner.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 0,
      baseAmount: BigNumber.from("100000000000000000000"),
      quoteAmount: 3000000,
      slippage: 500,
      limitPrice: "2100000000000000000", //2.1
      deadline: 999999999999,
      withWallet: true,
      nonce: utils.formatBytes32String("this is open long nonce"),
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
      nonce: utils.formatBytes32String("this is wrong open long nonce"),
    };

    orderShort = {
      routerToExecute: routerForKeeper.address,
      trader: owner.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 1,
      baseAmount: BigNumber.from("10000000000000000"),
      quoteAmount: 300000,
      slippage: 500,
      limitPrice: "1900000000000000000", //1.9
      deadline: 999999999999,
      withWallet: true,
      nonce: utils.formatBytes32String("this is open short nonce"),
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
      autoWithdraw: true,
      nonce: utils.formatBytes32String("this is close long nonce"),
    };

    closeOrderShort = {
      routerToExecute: routerForKeeper.address,
      trader: owner.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 1,
      quoteAmount: 300000,
      limitPrice: "2100000000000000000", //2.1
      deadline: 999999999999,
      autoWithdraw: false,
      nonce: utils.formatBytes32String("this is close short nonce"),
    };
  });

  describe("openPositionWithWallet", function () {
    it("can open position with wallet", async function () {
      const balanceBefore = await weth.balanceOf(owner.address);
      console.log("balanceBefore:", BigNumber.from(balanceBefore).toString());
      await routerForKeeper.openPositionWithWallet(order);
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(-3000000);
      const balanceAfter = await weth.balanceOf(owner.address);
      console.log("balanceAfter:", BigNumber.from(balanceAfter).toString());
    });

    it("revert when open position with wrong pair", async function () {
      order.baseToken = owner.address;
      await expect(routerForKeeper.openPositionWithWallet(order)).to.be.revertedWith("RFK.OPWW: NOT_FOUND_MARGIN");
    });

    it("revert when open position with invalid side", async function () {
      order.side = 2;
      await expect(routerForKeeper.openPositionWithWallet(order)).to.be.revertedWith("RFK.OPWW: INVALID_SIDE");
    });
  });

  describe("openPositionWithMargin", function () {
    beforeEach(async function () {
      await weth.approve(router.address, BigNumber.from("1000000000000000000000"));
      await router.deposit(weth.address, usdc.address, owner.address, 10);
    });

    it("can open position with margin", async function () {
      await router.deposit(weth.address, usdc.address, owner.address, BigNumber.from("100000000000000000000"));
      await routerForKeeper.openPositionWithMargin(order);
    });

    it("revert when open position with wrong pair", async function () {
      order.baseToken = owner.address;
      await expect(routerForKeeper.openPositionWithMargin(order)).to.be.revertedWith("RFK.OPWM: NOT_FOUND_MARGIN");
    });

    it("revert when open position with invalid side", async function () {
      order.side = 2;
      await expect(routerForKeeper.openPositionWithMargin(order)).to.be.revertedWith("RFK.OPWM: INVALID_SIDE");
    });
  });

  describe("closePosition", function () {
    beforeEach(async function () {
      await routerForKeeper.openPositionWithWallet(order);
      await router.getPosition(weth.address, usdc.address, owner.address);
    });

    it("can close position", async function () {
      await routerForKeeper.closePosition(closeOrder);
    });

    it("revert when open position with wrong pair", async function () {
      closeOrder.baseToken = owner.address;
      await expect(routerForKeeper.closePosition(closeOrder)).to.be.revertedWith("RFK.CP: NOT_FOUND_MARGIN");
    });

    it("revert when close a long position with side=1", async function () {
      closeOrder.side = 1;
      await expect(routerForKeeper.closePosition(closeOrder)).to.be.revertedWith("RFK.CP: SIDE_NOT_MATCH");
    });
  });
});

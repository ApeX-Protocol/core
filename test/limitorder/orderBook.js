const { expect, use } = require("chai");
const { ethers, waffle } = require("hardhat");
const { utils } = require("ethers");
const { solidity } = require("ethereum-waffle");
const { expandDecimals, deploy, init, reportGasUsed } = require("../shared/utilities");

use(solidity);

let weth, usdc, priceOracle, config, pairFactory, marginFactory, ammFactory, router, routerForKeeper, orderBook;

describe("OrderBook UT", function() {

  const provider = waffle.provider;
  let [owner, treasury, addr1] = provider.getWallets();

  let abiCoder;
  let orderStruct =
    "tuple(address routerToExecute, address trader, address baseToken, address quoteToken, uint8 side, uint256 baseAmount, uint256 quoteAmount, uint256 slippage, uint256 limitPrice, uint256 deadline, bool withWallet, bytes nonce)";
  let closeOrderStruct =
    "tuple(address routerToExecute, address trader, address baseToken, address quoteToken, uint8 side, uint256 quoteAmount, uint256 limitPrice, uint256 deadline, bool autoWithdraw, bytes nonce)";
  let order, order1, wrongOrder, orderShort, closeOrder, wrongCloseOrder, closeOrderShort;

  beforeEach(async function() {
    abiCoder = await ethers.utils.defaultAbiCoder;

    ({
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
    } = await deploy(owner));
    await init(owner, treasury, weth, usdc, priceOracle, config, pairFactory, marginFactory, ammFactory, router, routerForKeeper);

    await weth.approve(router.address, expandDecimals(1, 14));
    await router.addLiquidity(weth.address, usdc.address, expandDecimals(1, 14), 0, 9999999999, false);

    await usdc.mint(owner.address, 10000000);
    await weth.approve(routerForKeeper.address, 10000000);
    await routerForKeeper.setOrderBook(orderBook.address);

    order = {
      routerToExecute: routerForKeeper.address,
      trader: owner.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 0,
      baseAmount: 10000,
      quoteAmount: 30000,
      slippage: 500, //5%
      limitPrice: "2100000000000000000", //2.1
      deadline: 999999999999,
      withWallet: true,
      nonce: utils.formatBytes32String("this is open long nonce")
    };

    order1 = {
      routerToExecute: routerForKeeper.address,
      trader: owner.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 1,
      baseAmount: 10000,
      quoteAmount: 40000,
      slippage: 600,
      limitPrice: "1900000000000000000", //2.1
      deadline: 999999999999,
      withWallet: true,
      nonce: utils.formatBytes32String("this is open short nonce")
    };

    orderShort = {
      routerToExecute: routerForKeeper.address,
      trader: owner.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 1,
      baseAmount: 10000,
      quoteAmount: 30000,
      slippage: 600,
      limitPrice: "1900000000000000000", //1.9
      deadline: 999999999999,
      withWallet: true,
      nonce: utils.formatBytes32String("this is open short nonce")
    };

    wrongOrder = {
      routerToExecute: routerForKeeper.address,
      trader: addr1.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 0,
      baseAmount: 0, //wrong amount
      quoteAmount: 30000,
      slippage: 500, //5%
      limitPrice: "2100000000000000000",
      deadline: 999999999999,
      withWallet: true,
      nonce: utils.formatBytes32String("this is wrong open long nonce")
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
      nonce: utils.formatBytes32String("this is close long nonce")
    };

    wrongCloseOrder = {
      routerToExecute: routerForKeeper.address,
      trader: addr1.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 0,
      quoteAmount: 0,
      limitPrice: "1900000000000000000", //1.9
      deadline: 999999999999,
      autoWithdraw: false,
      nonce: utils.formatBytes32String("this is wrong close long nonce")
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
      nonce: utils.formatBytes32String("this is close short nonce")
    };
  });

  describe("batchExecuteOpen", function() {
    it("can batchExecuteOpen", async function() {
      const orderEncoded = abiCoder.encode([orderStruct], [order]);
      const orderSign = await owner.signMessage(utils.arrayify(utils.keccak256(orderEncoded)));
      const order1Encoded = abiCoder.encode([orderStruct], [order1]);
      const order1Sign = await owner.signMessage(utils.arrayify(utils.keccak256(order1Encoded)));
      const tx = await orderBook.batchExecuteOpen([order, order1], [orderSign, order1Sign], false);
      await reportGasUsed(provider, tx, "");
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(10000);
    });

    it("not revert all when batchExecuteOpen with requireSuccess false", async function() {
      const orderEncoded = abiCoder.encode([orderStruct], [order]);
      const orderSign = await owner.signMessage(utils.arrayify(utils.keccak256(orderEncoded)));
      const wOrderEncoded = abiCoder.encode([orderStruct], [wrongOrder]);
      const wOrderSign = await addr1.signMessage(utils.arrayify(utils.keccak256(wOrderEncoded)));

      await orderBook.batchExecuteOpen([order, wrongOrder], [orderSign, wOrderSign], false);
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(-30000);
      result = await router.getPosition(weth.address, usdc.address, addr1.address);
      expect(result.quoteSize.toNumber()).to.be.equal(0);
    });

    it("revert all when batchExecuteOpen with requireSuccess true", async function() {
      const orderEncoded = abiCoder.encode([orderStruct], [order]);
      const orderSign = await owner.signMessage(utils.arrayify(utils.keccak256(orderEncoded)));
      const wOrderEncoded = abiCoder.encode([orderStruct], [wrongOrder]);
      const wOrderSign = await addr1.signMessage(utils.arrayify(utils.keccak256(wOrderEncoded)));

      await expect(orderBook.batchExecuteOpen([order, wrongOrder], [orderSign, wOrderSign], true)).to.be.revertedWith(
        "OB.EO: call failed"
      );
    });
  });

  describe("batchExecuteClose", function() {
    beforeEach(async function() {
      const orderEncoded = abiCoder.encode([orderStruct], [order]);
      const orderSign = await owner.signMessage(utils.arrayify(utils.keccak256(orderEncoded)));
      await orderBook.batchExecuteOpen([order], [orderSign], false);
      const result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(-30000);
    });

    it("can batchExecuteClose", async function() {
      const cOrderEncoded = abiCoder.encode([closeOrderStruct], [closeOrder]);
      let cOrderSign = await owner.signMessage(utils.arrayify(utils.keccak256(cOrderEncoded)));

      await orderBook.batchExecuteClose([closeOrder], [cOrderSign], false);
      const result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(0);
    });

    it("not revert all when batchExecuteClose with requireSuccess false", async function() {
      const cOrderEncoded = abiCoder.encode([closeOrderStruct], [closeOrder]);
      const cOrderSign = await owner.signMessage(utils.arrayify(utils.keccak256(cOrderEncoded)));
      const wOrderEncoded = abiCoder.encode([closeOrderStruct], [wrongCloseOrder]);
      const wOrderSign = await addr1.signMessage(utils.arrayify(utils.keccak256(wOrderEncoded)));

      await orderBook.batchExecuteClose([closeOrder, wrongCloseOrder], [cOrderSign, wOrderSign], false);
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(0);
      result = await router.getPosition(weth.address, usdc.address, addr1.address);
      expect(result.quoteSize.toNumber()).to.be.equal(0);
    });

    it("revert all when batchExecuteClose with requireSuccess true", async function() {
      const cOrderEncoded = abiCoder.encode([closeOrderStruct], [closeOrder]);
      const cOrderSign = await owner.signMessage(utils.arrayify(utils.keccak256(cOrderEncoded)));
      const wcOrderEncoded = abiCoder.encode([closeOrderStruct], [wrongCloseOrder]);
      const wcOrderSign = await addr1.signMessage(utils.arrayify(utils.keccak256(wcOrderEncoded)));

      await expect(
        orderBook.batchExecuteClose([closeOrder, wrongCloseOrder], [cOrderSign, wcOrderSign], true)
      ).to.be.revertedWith("OB.EC: call failed");
    });
  });

  describe("executeOpen", function() {
    it("execute a new open long position order", async function() {
      const orderEncoded = abiCoder.encode([orderStruct], [order]);
      const orderSign = await owner.signMessage(utils.arrayify(utils.keccak256(orderEncoded)));
      await orderBook.executeOpen(order, orderSign);
      const result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(-30000);
    });

    it("execute a new open short position order", async function() {
      const orderEncoded = abiCoder.encode([orderStruct], [order1]);
      const orderSign = await owner.signMessage(utils.arrayify(utils.keccak256(orderEncoded)));

      await orderBook.executeOpen(order1, orderSign);
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(40000);
    });

    it("revert when execute a wrong order", async function() {
      const orderEncoded = abiCoder.encode([orderStruct], [order]);
      const orderSign = await owner.signMessage(utils.arrayify(utils.keccak256(orderEncoded)));

      order.side = 1 - order.side;
      await expect(orderBook.executeOpen(order, orderSign)).to.be.revertedWith("OB.VO: NOT_SIGNER");
    });

    it("revert when execute an used order", async function() {
      const orderEncoded = abiCoder.encode([orderStruct], [order]);
      const orderSign = await owner.signMessage(utils.arrayify(utils.keccak256(orderEncoded)));

      await orderBook.executeOpen(order, orderSign);
      await expect(orderBook.executeOpen(order, orderSign)).to.be.revertedWith("OB.VO: NONCE_USED");
    });

    it("revert when execute a expired order", async function() {
      order.deadline = 10000;
      const orderEncoded = abiCoder.encode([orderStruct], [order]);
      const orderSign = await owner.signMessage(utils.arrayify(utils.keccak256(orderEncoded)));

      await expect(orderBook.executeOpen(order, orderSign)).to.be.revertedWith("OB.VO: EXPIRED");
    });

    it("revert when execute to an invalid router", async function() {
      order.routerToExecute = addr1.address;
      const orderEncoded = abiCoder.encode([orderStruct], [order]);
      const orderSign = await owner.signMessage(utils.arrayify(utils.keccak256(orderEncoded)));

      await expect(orderBook.executeOpen(order, orderSign)).to.be.revertedWith("OB.EO: WRONG_ROUTER");
    });
  });

  describe("executeClose", function() {
    describe("open long first", async function() {
      beforeEach(async function() {
        const orderEncoded = abiCoder.encode([orderStruct], [order]);
        const orderSign = await owner.signMessage(utils.arrayify(utils.keccak256(orderEncoded)));
        await orderBook.executeOpen(order, orderSign);
      });

      it("execute a new close long position order", async function() {
        const cOrderEncoded = abiCoder.encode([closeOrderStruct], [closeOrder]);
        const cOrderSign = await owner.signMessage(utils.arrayify(utils.keccak256(cOrderEncoded)));

        await orderBook.executeClose(closeOrder, cOrderSign);
        let result = await router.getPosition(weth.address, usdc.address, owner.address);
        expect(result.quoteSize.toNumber()).to.be.equal(0);
      });
    });

    describe("open short first", async function() {
      beforeEach(async function() {
        const sOrderEncoded = abiCoder.encode([orderStruct], [orderShort]);
        const sOrderSign = await owner.signMessage(utils.arrayify(utils.keccak256(sOrderEncoded)));
        await orderBook.executeOpen(orderShort, sOrderSign);
      });

      it("execute a new close short position order", async function() {
        const csOrderEncoded = abiCoder.encode([closeOrderStruct], [closeOrderShort]);
        const csOrderSign = await owner.signMessage(utils.arrayify(utils.keccak256(csOrderEncoded)));

        await orderBook.executeClose(closeOrderShort, csOrderSign);
        const result = await router.getPosition(weth.address, usdc.address, owner.address);
        expect(result.quoteSize.toNumber()).to.be.equal(0);
      });

      it("revert when execute a wrong order", async function() {
        const csOrderEncoded = abiCoder.encode([closeOrderStruct], [closeOrderShort]);
        const csOrderSign = await owner.signMessage(utils.arrayify(utils.keccak256(csOrderEncoded)));

        closeOrderShort.side = 1 - closeOrderShort.side;
        await expect(orderBook.executeClose(closeOrderShort, csOrderSign)).to.be.revertedWith(
          "OB.VC: NOT_SIGNER"
        );
      });

      it("revert when execute an used order", async function() {
        const csOrderEncoded = abiCoder.encode([closeOrderStruct], [closeOrderShort]);
        const csOrderSign = await owner.signMessage(utils.arrayify(utils.keccak256(csOrderEncoded)));

        await orderBook.executeClose(closeOrderShort, csOrderSign);
        await expect(orderBook.executeClose(closeOrderShort, csOrderSign)).to.be.revertedWith(
          "OB.VC: NONCE_USED"
        );
      });

      it("revert when execute a expired order", async function() {
        closeOrderShort.deadline = 10000;
        const csOrderEncoded = abiCoder.encode([closeOrderStruct], [closeOrderShort]);
        const csOrderSign = await owner.signMessage(utils.arrayify(utils.keccak256(csOrderEncoded)));

        await expect(orderBook.executeClose(closeOrderShort, csOrderSign)).to.be.revertedWith(
          "OB.VC: EXPIRED"
        );
      });
    });
  });

  describe("setRouterForKeeper", function() {
    it("routerForKeeper", async function() {
      expect(await orderBook.routerForKeeper()).to.be.equal(routerForKeeper.address);
    });
  });
});

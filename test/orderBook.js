const { expect } = require("chai");
const exp = require("constants");

let owner;
let treasury;
let addr1;

let weth;
let usdc;
let priceOracle;
let config;
let pairFactory;
let marginFactory;
let ammFactory;
let routerForKeeper;
let orderBook;
let orderStruct =
  "tuple(address routerToExecute, address trader, address baseToken, address quoteToken, uint8 side, uint256 baseAmount, uint256 quoteAmount, uint256 slippage, uint256 limitPrice, uint256 deadline, bool withWallet, bytes nonce)";
let closeOrderStruct =
  "tuple(address routerToExecute, address trader, address baseToken, address quoteToken, uint8 side, uint256 quoteAmount, uint256 limitPrice, uint256 deadline, bool autoWithdraw, bytes nonce)";
let order;

describe("OrderBook Contract", function () {
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

    const OrderBook = await ethers.getContractFactory("OrderBook");
    orderBook = await OrderBook.deploy(routerForKeeper.address);

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

    await routerForKeeper.deposit(weth.address, owner.address, 10000000);
    expect(await routerForKeeper.balanceOf(weth.address, owner.address)).to.be.equal(10000000);
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
      slippage: 500, //5%
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
      slippage: 600, //6%
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
      nonce: ethers.utils.formatBytes32String("this is wrong close long nonce"),
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

  describe("batchExecuteOpen", function () {
    it("can batchExecuteOpen", async function () {
      let abiCoder = await ethers.utils.defaultAbiCoder;
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await orderBook.batchExecuteOpen([order], [signature], false);
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(-30000);
    });

    it("not revert all when batchExecuteOpen with false", async function () {
      let abiCoder = await ethers.utils.defaultAbiCoder;
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));
      let data1 = abiCoder.encode([orderStruct], [wrongOrder]);
      let signature1 = await addr1.signMessage(hexStringToByteArray(ethers.utils.keccak256(data1)));

      await orderBook.batchExecuteOpen([order, wrongOrder], [signature, signature1], false);
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(-30000);
      result = await router.getPosition(weth.address, usdc.address, addr1.address);
      expect(result.quoteSize.toNumber()).to.be.equal(0);
    });

    it("revert all when batchExecuteOpen with true", async function () {
      let abiCoder = await ethers.utils.defaultAbiCoder;
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));
      let data1 = abiCoder.encode([orderStruct], [wrongOrder]);
      let signature1 = await addr1.signMessage(hexStringToByteArray(ethers.utils.keccak256(data1)));

      await expect(orderBook.batchExecuteOpen([order, wrongOrder], [signature, signature1], true)).to.be.revertedWith(
        "_executeOpen: call failed"
      );
    });
  });

  describe("batchExecuteClose", function () {
    let abiCoder;
    beforeEach(async function () {
      abiCoder = await ethers.utils.defaultAbiCoder;
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));
      await orderBook.batchExecuteOpen([order], [signature], false);
    });

    it("can batchExecuteClose", async function () {
      data = abiCoder.encode([closeOrderStruct], [closeOrder]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await orderBook.batchExecuteClose([closeOrder], [signature], false);
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(0);
    });

    it("not revert all when batchExecuteClose with false", async function () {
      data = abiCoder.encode([closeOrderStruct], [closeOrder]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));
      let data1 = abiCoder.encode([closeOrderStruct], [wrongCloseOrder]);
      let signature1 = await addr1.signMessage(hexStringToByteArray(ethers.utils.keccak256(data1)));

      await orderBook.batchExecuteClose([closeOrder, wrongCloseOrder], [signature, signature1], false);
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(0);
      result = await router.getPosition(weth.address, usdc.address, addr1.address);
      expect(result.quoteSize.toNumber()).to.be.equal(0);
    });

    it("revert all when batchExecuteClose with true", async function () {
      data = abiCoder.encode([closeOrderStruct], [closeOrder]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));
      let data1 = abiCoder.encode([closeOrderStruct], [wrongCloseOrder]);
      let signature1 = await addr1.signMessage(hexStringToByteArray(ethers.utils.keccak256(data1)));

      await expect(
        orderBook.batchExecuteClose([closeOrder, wrongCloseOrder], [signature, signature1], true)
      ).to.be.revertedWith("_executeClose: call failed");
    });
  });

  describe("executeOpen", function () {
    let abiCoder;
    beforeEach(async function () {
      abiCoder = await ethers.utils.defaultAbiCoder;
    });
    it("execute a new open long position order", async function () {
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));
      await orderBook.executeOpen(order, signature);
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(-30000);
    });

    it("execute a new open short position order", async function () {
      data = abiCoder.encode([orderStruct], [orderShort]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await orderBook.executeOpen(orderShort, signature);
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(30000);
    });

    it("revert when execute a wrong order", async function () {
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      order.side = 1 - order.side;
      await expect(orderBook.executeOpen(order, signature)).to.be.revertedWith("OrderBook.verifyOpen: NOT_SIGNER");
    });

    it("revert when execute an used order", async function () {
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await orderBook.executeOpen(order, signature);
      await expect(orderBook.executeOpen(order, signature)).to.be.revertedWith("OrderBook.verifyOpen: NONCE_USED");
    });

    it("revert when execute a expired order", async function () {
      order.deadline = 10000;
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await expect(orderBook.executeOpen(order, signature)).to.be.revertedWith("OrderBook.verifyOpen: EXPIRED");
    });

    it("revert when execute to an invalid router", async function () {
      order.routerToExecute = addr1.address;
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await expect(orderBook.executeOpen(order, signature)).to.be.revertedWith("OrderBook.executeOpen: WRONG_ROUTER");
    });

    it("revert when execute long with an invalid slippage", async function () {
      order.slippage = 1;
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await expect(orderBook.executeOpen(order, signature)).to.be.revertedWith("_executeOpen: call failed");
    });

    it("revert when execute short with invalid slippage", async function () {
      orderShort.slippage = 1;
      data = abiCoder.encode([orderStruct], [orderShort]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await expect(orderBook.executeOpen(orderShort, signature)).to.be.revertedWith("_executeOpen: call failed");
    });
  });

  describe("executeClose", function () {
    describe("open long first", async function () {
      let abiCoder;
      beforeEach(async function () {
        abiCoder = await ethers.utils.defaultAbiCoder;
        data = abiCoder.encode([orderStruct], [order]);
        let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));
        await orderBook.executeOpen(order, signature);
      });

      it("execute a new close long position order", async function () {
        let data = abiCoder.encode([closeOrderStruct], [closeOrder]);
        let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

        await orderBook.executeClose(closeOrder, signature);
        let result = await router.getPosition(weth.address, usdc.address, owner.address);
        expect(result.quoteSize.toNumber()).to.be.equal(0);
      });
    });

    describe("open short first", async function () {
      let abiCoder;
      beforeEach(async function () {
        abiCoder = await ethers.utils.defaultAbiCoder;

        data = abiCoder.encode([orderStruct], [orderShort]);
        signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));
        await orderBook.executeOpen(orderShort, signature);
      });

      it("execute a new close short position order", async function () {
        data = abiCoder.encode([closeOrderStruct], [closeOrderShort]);
        let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

        await orderBook.executeClose(closeOrderShort, signature);
        let result = await router.getPosition(weth.address, usdc.address, owner.address);
        expect(result.quoteSize.toNumber()).to.be.equal(0);
      });

      it("revert when execute a wrong order", async function () {
        data = abiCoder.encode([closeOrderStruct], [closeOrderShort]);
        let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

        closeOrderShort.side = 1 - closeOrderShort.side;
        await expect(orderBook.executeClose(closeOrderShort, signature)).to.be.revertedWith(
          "OrderBook.verifyClose: NOT_SIGNER"
        );
      });

      it("revert when execute an used order", async function () {
        data = abiCoder.encode([closeOrderStruct], [closeOrderShort]);
        let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

        await orderBook.executeClose(closeOrderShort, signature);
        await expect(orderBook.executeClose(closeOrderShort, signature)).to.be.revertedWith(
          "OrderBook.verifyClose: NONCE_USED"
        );
      });

      it("revert when execute a expired order", async function () {
        closeOrderShort.deadline = 10000;
        data = abiCoder.encode([closeOrderStruct], [closeOrderShort]);
        let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

        await expect(orderBook.executeClose(closeOrderShort, signature)).to.be.revertedWith(
          "OrderBook.verifyClose: EXPIRED"
        );
      });
    });
  });

  describe("setRouterForKeeper", function () {
    it("routerForKeeper", async function () {
      expect(await orderBook.routerForKeeper()).to.be.equal(routerForKeeper.address);
    });
  });
});

function hexStringToByteArray(hexString) {
  if (hexString.length % 2 !== 0) {
    throw "Must have an even number of hex digits to convert to bytes";
  }
  var numBytes = hexString.length / 2;
  var byteArray = new Uint8Array(numBytes);
  for (var i = 0; i < numBytes; i++) {
    byteArray[i] = parseInt(hexString.substr(i * 2, 2), 16);
  }
  return byteArray.slice(1);
}

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
  "tuple(address trader, address baseToken, address quoteToken, uint8 side, uint256 baseAmount, uint256 quoteAmount, uint256 baseAmountLimit, uint256 limitPrice, uint256 deadline, bytes nonce)";
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
    router = await Router.deploy(pairFactory.address, treasury.address, weth.address);

    const RouterForKeeper = await ethers.getContractFactory("RouterForKeeper");
    routerForKeeper = await RouterForKeeper.deploy(pairFactory.address, weth.address);

    const OrderBook = await ethers.getContractFactory("OrderBook");
    orderBook = await OrderBook.deploy(routerForKeeper.address);

    await config.setPriceOracle(priceOracle.address);
    await pairFactory.init(ammFactory.address, marginFactory.address);

    await pairFactory.createPair(weth.address, usdc.address);
    await priceOracle.setReserve(weth.address, usdc.address, 10000, 20000);
    await weth.approve(router.address, 100000000000000);
    await router.addLiquidity(weth.address, usdc.address, 100000000000000, 0, 9999999999, false);

    await usdc.mint(owner.address, 10000000);
    await weth.approve(routerForKeeper.address, 10000000);
    await config.registerRouter(routerForKeeper.address);
    order = {
      trader: owner.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 0,
      baseAmount: 10000,
      quoteAmount: 30000,
      baseAmountLimit: 1000,
      limitPrice: "2100000000000000000", //2.1
      deadline: 999999999999,
      nonce: ethers.utils.formatBytes32String("this is nonce"),
    };

    orderShort = {
      trader: owner.address,
      baseToken: weth.address,
      quoteToken: usdc.address,
      side: 1,
      baseAmount: 10000,
      quoteAmount: 30000,
      baseAmountLimit: 100000,
      limitPrice: "1900000000000000000", //1.9
      deadline: 999999999999,
      nonce: ethers.utils.formatBytes32String("this is nonce"),
    };
  });

  describe("routerForKeeper", function () {
    it("routerForKeeper", async function () {
      expect(await orderBook.routerForKeeper()).to.be.equal(routerForKeeper.address);
    });
  });

  describe("executeOpenPositionOrder", function () {
    let abiCoder;
    beforeEach(async function () {
      abiCoder = await ethers.utils.defaultAbiCoder;
    });
    it("execute a new open long position order", async function () {
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await orderBook.executeOpenPositionOrder(order, signature);
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(-30000);
    });

    it("execute a new open short position order", async function () {
      data = abiCoder.encode([orderStruct], [orderShort]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await orderBook.executeOpenPositionOrder(orderShort, signature);
      let result = await router.getPosition(weth.address, usdc.address, owner.address);
      expect(result.quoteSize.toNumber()).to.be.equal(30000);
    });

    it("revert when execute a wrong order", async function () {
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      order.side = 1 - order.side;
      await expect(orderBook.executeOpenPositionOrder(order, signature)).to.be.revertedWith(
        "OrderBook.verify: NOT_SIGNER"
      );
    });

    it("revert when execute an used order", async function () {
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await orderBook.executeOpenPositionOrder(order, signature);
      await expect(orderBook.executeOpenPositionOrder(order, signature)).to.be.revertedWith(
        "OrderBook.verify: NONCE_USED"
      );
    });

    it("revert when execute a expired order", async function () {
      order.deadline = 10000;
      data = abiCoder.encode([orderStruct], [order]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await expect(orderBook.executeOpenPositionOrder(order, signature)).to.be.revertedWith(
        "OrderBook.verify: EXPIRED"
      );
    });
  });

  describe("executeClosePositionOrder", function () {
    it("execute a new close position order", async function () {});
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

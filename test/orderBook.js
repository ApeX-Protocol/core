const { expect } = require("chai");

let owner;
let addr1;
let weth;
let config;
let pairFactory;
let marginFactory;
let ammFactory;
let routerForKeeper;
let orderBook;

describe("OrderBook Contract", function () {
  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();

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

  describe.only("executeOpenPositionOrder", function () {
    it("execute a new open position order", async function () {
      // var serialize = require("serialize-javascript");
      let order = {
        trader: owner.address,
        baseToken: addr1.address,
        quoteToken: addr1.address,
        isLong: 1,
        baseAmount: 10000,
        quoteAmount: 30000,
        baseAmountLimit: 10000,
        limitPrice: 10000,
        deadline: 10000,
        nonce: ethers.utils.formatBytes32String("fasdfas"),
      };
      let abiCoder = await ethers.utils.defaultAbiCoder;
      data = abiCoder.encode(["uint256", "string", "uint256[]"], [1234, "hello", [6, 9]]);
      let signature = await owner.signMessage(hexStringToByteArray(ethers.utils.keccak256(data)));

      await orderBook.executeOpenPositionOrder(order, signature, [6, 9]);
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

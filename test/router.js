const { expect } = require("chai");
const { BigNumber } = require("@ethersproject/bignumber");

describe("Router contract", function () {
  let owner;
  let treasury;
  let weth;
  let router;
  let priceOracle;
  let apeXToken;
  let baseToken;
  let quoteToken;

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
    pairFactory = await PairFactory.deploy();

    const AmmFactory = await ethers.getContractFactory("AmmFactory");
    const MarginFactory = await ethers.getContractFactory("MarginFactory");
    let ammFactory = await AmmFactory.deploy(pairFactory.address, config.address, owner.address);
    let marginFactory = await MarginFactory.deploy(pairFactory.address, config.address);
    await pairFactory.init(ammFactory.address, marginFactory.address);

    const Router = await ethers.getContractFactory("Router");
    router = await Router.deploy(pairFactory.address, treasury.address, weth.address);
    await config.registerRouter(router.address);
  });

  describe("addLiquidity", function () {
    it("addLiquidity without pcv", async function () {
      await baseToken.mint(owner.address, 1000000);
      await baseToken.approve(router.address, 1000000);
      expect(await router.addLiquidity(baseToken.address, quoteToken.address, 1000, 1, 9999999999, false));
    });

    it("addLiquidity with pcv", async function () {
      await baseToken.mint(owner.address, 1000000);
      await baseToken.approve(router.address, 1000000);
      expect(await router.addLiquidity(baseToken.address, quoteToken.address, 1000, 1, 9999999999, true));
    });
  });

  describe("addLiquidityETH", function () {
    it("addLiquidityETH without pcv", async function () {
      let overrides = {
        value: ethers.utils.parseEther("1"),
      };
      expect(await router.addLiquidityETH(quoteToken.address, 1, 9999999999, false, overrides));
    });

    it("addLiquidity with pcv", async function () {
      let overrides = {
        value: ethers.utils.parseEther("1"),
      };
      expect(await router.addLiquidityETH(quoteToken.address, 1, 9999999999, true, overrides));
    });
  });

  describe("removeLiquidity", function () {
    it("removeLiquidity right", async function () {
      await baseToken.mint(owner.address, 1000000);
      await baseToken.approve(router.address, 1000000);
      await router.addLiquidity(baseToken.address, quoteToken.address, 1000, 1, 9999999999, false);

      let ammAddress = await pairFactory.getAmm(baseToken.address, quoteToken.address);
      const Amm = await ethers.getContractFactory("Amm");
      let amm = await Amm.attach(ammAddress);
      let liquidity = await amm.balanceOf(owner.address);
      await amm.approve(router.address, 1000000);
      await router.removeLiquidity(baseToken.address, quoteToken.address, liquidity.toNumber(), 1, 9999999999);
    });
  });

  describe("removeLiquidityETH", function () {
    it("removeLiquidityETH right", async function () {
      let overrides = {
        value: ethers.utils.parseEther("1"),
      };
      expect(await router.addLiquidityETH(quoteToken.address, 1, 9999999999, false, overrides));

      let ammAddress = await pairFactory.getAmm(weth.address, quoteToken.address);
      const Amm = await ethers.getContractFactory("Amm");
      let amm = await Amm.attach(ammAddress);
      let liquidity = await amm.balanceOf(owner.address);
      await amm.approve(router.address, BigNumber.from(liquidity));
      await router.removeLiquidityETH(quoteToken.address, BigNumber.from(liquidity), 1, 9999999999);
    });
  });

  describe("deposit", function () {
    it("deposit right", async function () {
      await baseToken.mint(owner.address, 1000000);
      await baseToken.approve(router.address, 1000000);
      await router.addLiquidity(baseToken.address, quoteToken.address, 1000, 1, 9999999999, false);
      await router.deposit(baseToken.address, quoteToken.address, owner.address, 1000);
    });
  });

  describe("depositETH", function () {
    it("depositETH right", async function () {
      let overrides = {
        value: ethers.utils.parseEther("1"),
      };
      expect(await router.addLiquidityETH(quoteToken.address, 1, 9999999999, false, overrides));
      await router.depositETH(quoteToken.address, owner.address, overrides);
    });
  });

  describe("withdraw", function () {
    it("withdraw right", async function () {
      await baseToken.mint(owner.address, 1000000);
      await baseToken.approve(router.address, 1000000);
      await router.addLiquidity(baseToken.address, quoteToken.address, 1000, 1, 9999999999, false);
      await router.deposit(baseToken.address, quoteToken.address, owner.address, 1000);
      await router.withdraw(baseToken.address, quoteToken.address, 1000);
    });
  });

  describe("openPositionWithMargin", function () {
    it("openPositionWithMargin open long", async function () {
      await baseToken.mint(owner.address, 1000000);
      await baseToken.approve(router.address, 1000000);
      await router.addLiquidity(baseToken.address, quoteToken.address, 1000, 1, 9999999999, false);
      await router.deposit(baseToken.address, quoteToken.address, owner.address, 1000);
      await router.openPositionWithMargin(baseToken.address, quoteToken.address, 0, 3300, 1, 9999999999);
    });

    it("openPositionWithMargin open short", async function () {
      await baseToken.mint(owner.address, 1000000);
      await baseToken.approve(router.address, 1000000);
      await router.addLiquidity(baseToken.address, quoteToken.address, 1000, 1, 9999999999, false);
      await router.deposit(baseToken.address, quoteToken.address, owner.address, 1000);
      await router.openPositionWithMargin(baseToken.address, quoteToken.address, 1, 3300, 10000000, 9999999999);
    });
  });

  describe("openPositionWithWallet", function () {
    it("openPositionWithWallet open long", async function () {
      await baseToken.mint(owner.address, 1000000);
      await baseToken.approve(router.address, 1000000);
      await router.addLiquidity(baseToken.address, quoteToken.address, 10000, 1, 9999999999, false);
      await router.openPositionWithWallet(baseToken.address, quoteToken.address, 0, 3300, 10000, 1, 9999999999);
    });

    it("openPositionWithWallet open short", async function () {
      await baseToken.mint(owner.address, 1000000);
      await baseToken.approve(router.address, 1000000);
      await router.addLiquidity(baseToken.address, quoteToken.address, 10000, 1, 9999999999, false);
      await router.openPositionWithWallet(baseToken.address, quoteToken.address, 1, 3300, 10000, 10000000, 9999999999);
    });
  });

  describe("openPositionETHWithWallet", function () {
    it("openPositionETHWithWallet open long", async function () {
      let overrides = {
        value: ethers.utils.parseEther("1"),
      };
      expect(await router.addLiquidityETH(quoteToken.address, 1, 9999999999, false, overrides));
      await router.openPositionETHWithWallet(quoteToken.address, 0, 10000, 1, 9999999999, overrides);
    });

    it("openPositionETHWithWallet open short", async function () {
      let overrides = {
        value: ethers.utils.parseEther("1"),
      };
      expect(await router.addLiquidityETH(quoteToken.address, 1, 9999999999, false, overrides));
      await router.openPositionETHWithWallet(quoteToken.address, 1, 10000, 10000000, 9999999999, overrides);
    });
  });

  describe("closePosition", function () {
    it("closePosition right", async function () {
      await baseToken.mint(owner.address, 1000000);
      await baseToken.approve(router.address, 1000000);
      await router.addLiquidity(baseToken.address, quoteToken.address, 10000, 1, 9999999999, false);
      await router.openPositionWithWallet(baseToken.address, quoteToken.address, 0, 3300, 10000, 1, 9999999999);
      await router.closePosition(baseToken.address, quoteToken.address, 10000, 9999999999, true);
    });
  });
});

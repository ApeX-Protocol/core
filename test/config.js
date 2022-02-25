const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");

describe("Config contract", function () {
  let config;
  beforeEach(async function () {
    [owner, addr1, liquidator, ...addrs] = await ethers.getSigners();

    const Config = await ethers.getContractFactory("Config");
    config = await Config.deploy();
    await config.setBeta(100);
    await config.setInitMarginRatio(909);
    await config.setLiquidateThreshold(10000);
    await config.setLiquidateFeeRatio(2000);
  });

  describe("set initMarginRatio", async function () {
    it("set correct ratio", async function () {
      await config.setInitMarginRatio(1000);
      expect(await config.initMarginRatio()).to.equal(1000);
    });

    it("revert when set wrong ratio", async function () {
      await expect(config.setInitMarginRatio(9)).to.be.revertedWith("Config: INVALID_MARGIN_RATIO");
    });

    it("reverted if addr1 set", async function () {
      await expect(config.connect(addr1).setInitMarginRatio(9)).to.be.revertedWith("Ownable: REQUIRE_OWNER");
    });
  });

  describe("set liquidateThreshold", async function () {
    it("set correct threshold", async function () {
      await config.setLiquidateThreshold(10000);
      expect(await config.liquidateThreshold()).to.equal(10000);
    });

    it("revert when set wrong threshold", async function () {
      await expect(config.setLiquidateThreshold(80)).to.be.revertedWith("Config: INVALID_LIQUIDATE_THRESHOLD");
    });
  });

  describe("set liquidateFeeRatio", async function () {
    it("set correct fee ratio", async function () {
      await config.setLiquidateFeeRatio(1000);
      expect(await config.liquidateFeeRatio()).to.equal(1000);
    });

    it("revert when set wrong fee ratio", async function () {
      await expect(config.setLiquidateFeeRatio(3000)).to.be.revertedWith("Config: INVALID_LIQUIDATE_FEE_RATIO");
    });
  });

  describe("registerRouter", async function () {
    it("revert when register a registered router", async function () {
      await config.registerRouter(addr1.address);
      await expect(config.registerRouter(addr1.address)).to.be.revertedWith("Config: REGISTERED");
    });
  });

  describe("unregisterRouter", async function () {
    it("revert when unregister an unregister router", async function () {
      await expect(config.unregisterRouter(addr1.address)).to.be.revertedWith("Config: UNREGISTERED");
    });

    it("unregister an registered router", async function () {
      await config.registerRouter(addr1.address);
      await config.unregisterRouter(addr1.address);
    });
  });
});

const { expect } = require("chai");

describe("Margin contract", function () {
  let margin;
  let owner;
  let addr1;
  let addr2;
  let addrs;
  let mockVAmm;
  let mockBaseToken;
  let vault;

  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    const MockBaseToken = await ethers.getContractFactory("MockBaseToken");
    mockBaseToken = await MockBaseToken.deploy("bit dao", "bit");

    const MockVAmm = await ethers.getContractFactory("MockVAmm");
    mockVAmm = await MockVAmm.deploy("amm shares", "as");

    const Vault = await ethers.getContractFactory("Vault");
    vault = await Vault.deploy(mockBaseToken.address, mockVAmm.address);

    const Margin = await ethers.getContractFactory("Margin");
    margin = await Margin.deploy(mockBaseToken.address, mockVAmm.address, vault.address, 10, 100, 1);

    await vault.setMargin(margin.address);
  });

  describe("add margin", function () {
    it("add correct margin", async function () {
      await margin.addMargin(addr1.address, 10);
      let position = await margin.traderPositionMap(addr1.address);
      expect(position[0]).to.equal(0);
      expect(position[1]).to.equal(10);
      expect(position[2]).to.equal(0);
    });

    it("add wrong margin", async function () {
      await expect(margin.addMargin(addr1.address, -10)).to.be.reverted;
      await expect(margin.addMargin(addr1.address, 0)).to.be.revertedWith(">0");
    });

    it("add an old position", async function () {
      //todo
    });
  });

  describe("remove margin", async function () {
    beforeEach(async function () {
      await mockBaseToken.mint(owner.address, 20000);
      await mockBaseToken.transfer(vault.address, 100);
      await margin.addMargin(owner.address, 100);
      expect(await mockBaseToken.balanceOf(vault.address)).to.equal(100);
    });

    it("remove correct margin", async function () {
      await margin.removeMargin(100);
      expect(await mockBaseToken.balanceOf(vault.address)).to.equal(0);
    });

    it("remove wrong margin", async function () {
      await expect(margin.removeMargin(101)).to.be.revertedWith("insufficient withdrawable");
    });
  });

  describe("set initMarginRatio", async function () {
    it("set correct ratio", async function () {
      await margin.setInitMarginRatio(10);
      expect(await margin.initMarginRatio()).to.equal(10);
    });

    it("set wrong ratio", async function () {
      await expect(margin.setInitMarginRatio(9)).to.be.revertedWith("ratio >= 10");
    });
  });

  describe("set liquidateThreshold", async function () {
    it("set correct threshold", async function () {
      await margin.setLiquidateThreshold(100);
      expect(await margin.liquidateThreshold()).to.equal(100);
    });

    it("set wrong threshold", async function () {
      await expect(margin.setLiquidateThreshold(80)).to.be.revertedWith("90 < liquidateThreshold <= 100");
    });
  });

  describe("set liquidateFeeRatio", async function () {
    it("set correct fee ratio", async function () {
      await margin.setLiquidateFeeRatio(10);
      expect(await margin.liquidateFeeRatio()).to.equal(10);
    });

    it("set wrong fee ratio", async function () {
      await expect(margin.setLiquidateFeeRatio(20)).to.be.revertedWith("0 < liquidateFeeRatio <= 10");
    });
  });
});

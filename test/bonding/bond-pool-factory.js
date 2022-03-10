const { expect } = require("chai");

describe("BondPoolFactory contract", function () {
  let owner;
  let other;
  let apeXToken;
  let weth;
  let treasury;
  let priceOracle;
  let maxPayout;
  let discount;
  let vestingTerm;
  let bondPoolTemplate;
  let bondPoolFactory;
  let amm;

  beforeEach(async function () {
    [owner, other] = await ethers.getSigners();
    const MockToken = await ethers.getContractFactory("MockToken");
    apeXToken = await MockToken.deploy("ApeX Token", "APEX");

    const MockWETH = await ethers.getContractFactory("MockWETH");
    weth = await MockWETH.deploy();

    const PCVTreasury = await ethers.getContractFactory("PCVTreasury");
    treasury = await PCVTreasury.deploy(apeXToken.address);

    const PriceOracle = await ethers.getContractFactory("MockPriceOracle");
    priceOracle = await PriceOracle.deploy();

    maxPayout = 100000;
    discount = 10;
    vestingTerm = 129600;

    const BondPoolTemplate = await ethers.getContractFactory("BondPool");
    bondPoolTemplate = await BondPoolTemplate.deploy();

    const BondPoolFactory = await ethers.getContractFactory("BondPoolFactory");
    bondPoolFactory = await BondPoolFactory.deploy(
      weth.address,
      apeXToken.address,
      treasury.address,
      priceOracle.address,
      bondPoolTemplate.address,
      maxPayout,
      discount,
      vestingTerm
    );

    const MockAmm = await ethers.getContractFactory("MockAmm");
    amm = await MockAmm.deploy("amm shares", "AS");
  });

  describe("updateParams", function () {
    it("updateParams right", async function () {
      await bondPoolFactory.updateParams(200000, 20, 200000);
      let newMaxPayout = await bondPoolFactory.maxPayout();
      let newDiscount = await bondPoolFactory.discount();
      let newVestingTerm = await bondPoolFactory.vestingTerm();
      expect(newMaxPayout.toNumber()).to.equal(200000);
      expect(newDiscount.toNumber()).to.equal(20);
      expect(newVestingTerm.toNumber()).to.equal(200000);
    });

    it("updateParams with wrong discount", async function () {
      await expect(bondPoolFactory.updateParams(200000, 10001, 200000)).to.be.revertedWith(
        "BondPoolFactory.updateParams: DISCOUNT_OVER_100%"
      );
    });

    it("updateParams with wrong vestingTerm", async function () {
      await expect(bondPoolFactory.updateParams(200000, 20, 129500)).to.be.revertedWith(
        "BondPoolFactory.updateParams: MUST_BE_LONGER_THAN_36_HOURS"
      );
    });

    it("updateParams with non-admin", async function () {
      let bondPoolFactoryAsOther = bondPoolFactory.connect(other);
      await expect(bondPoolFactoryAsOther.updateParams(200000, 20, 129600)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });
  });

  describe("createPool", function () {
    it("createPool right", async function () {
      let lengthBefore = await bondPoolFactory.allPoolsLength();
      await bondPoolFactory.createPool(amm.address);
      let lengthAfter = await bondPoolFactory.allPoolsLength();
      expect(lengthAfter.toNumber() - lengthBefore.toNumber()).to.equal(1);
    });

    it("createPool with non-admin", async function () {
      let bondPoolFactoryAsOther = bondPoolFactory.connect(other);
      await expect(bondPoolFactoryAsOther.createPool(amm.address)).to.be.revertedWith("Ownable: REQUIRE_OWNER");
    });
  });
});

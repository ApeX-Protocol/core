const { expect } = require("chai");
const { BigNumber } = require("ethers");

describe("BondPool contract", function () {
  let owner;
  let other;
  let apeXToken;
  let baseToken;
  let quoteToken;
  let weth;
  let treasury;
  let priceOracle;
  let maxPayout;
  let discount;
  let vestingTerm;
  let bondPoolTemplate;
  let bondPoolFactory;
  let amm;
  let pool;

  beforeEach(async function () {
    [owner, other] = await ethers.getSigners();
    const MockToken = await ethers.getContractFactory("MockToken");
    apeXToken = await MockToken.deploy("ApeX Token", "APEX");
    baseToken = await MockToken.deploy("Base Token", "BT");
    quoteToken = await MockToken.deploy("Quote Token", "QT");

    const MockWETH = await ethers.getContractFactory("MockWETH");
    weth = await MockWETH.deploy();

    const PCVTreasury = await ethers.getContractFactory("PCVTreasury");
    treasury = await PCVTreasury.deploy(apeXToken.address);

    const PriceOracle = await ethers.getContractFactory("MockBondPriceOracle");
    priceOracle = await PriceOracle.deploy();

    maxPayout = BigNumber.from("1000000000000000000000000");
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
    await amm.initialize(baseToken.address, quoteToken.address);

    await bondPoolFactory.createPool(amm.address);
    let length = await bondPoolFactory.allPoolsLength();
    let poolAddress = await bondPoolFactory.allPools(length.toNumber() - 1);
    const BondPool = await ethers.getContractFactory("BondPool");
    pool = await BondPool.attach(poolAddress);
    await treasury.addBondPool(pool.address);
    await treasury.addLiquidityToken(amm.address);
    await apeXToken.mint(treasury.address, 1000000);
  });

  describe("deposit", function () {
    it("deposit right", async function () {
      await baseToken.mint(owner.address, 100000);
      await baseToken.approve(pool.address, 1000000);
      await pool.deposit(owner.address, 1000, 100);
      let payout = await pool.payoutFor(1000);
      let balance = await apeXToken.balanceOf(pool.address);
      let userPayout = await pool.bondInfoFor(owner.address);
      expect(payout).to.equal(balance);
      expect(payout.toNumber()).to.equal(userPayout.payout.toNumber());
    });
  });

  describe("redeem", function () {
    it("redeem right", async function () {
      await baseToken.mint(owner.address, 100000);
      await baseToken.approve(pool.address, 1000000);
      await pool.deposit(owner.address, 1000, 100);
      let userPayout = await pool.bondInfoFor(owner.address);

      await mineBlocks(10000);
      let percent = await pool.percentVestedFor(owner.address);
      let payout = (userPayout.payout.toNumber() * percent.toNumber()) / 10000;
      payout = Math.floor(payout);
      await pool.redeem(owner.address);
      let userApeX = await apeXToken.balanceOf(owner.address);
      expect(userApeX.toNumber()).to.equal(payout);
    });
  });
});

async function mineBlocks(blockNumber) {
  while (blockNumber > 0) {
    blockNumber--;
    await hre.network.provider.request({
      method: "evm_mine",
    });
  }
}

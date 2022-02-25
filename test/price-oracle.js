const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");

describe("PriceOracle contract", function () {
  let baseToken;
  let quoteToken;
  let marginAddress = "0xb9cBC6759a4b71C127047c6aAcdDB569168A5046";
  let amm;
  let pool1;
  let pool2;
  let pool3;
  let v3factory;
  let oracle;

  beforeEach(async function () {
    const MyToken = await ethers.getContractFactory("MyToken");
    baseToken = await MyToken.deploy("Base Token", "BT", 18, BigNumber.from("100000000000000000000000000"));
    quoteToken = await MyToken.deploy("Quote Token", "QT", 6, BigNumber.from("1000000000000000"));
    // console.log("baseToken:", baseToken.address);
    // console.log("quoteToken:", quoteToken.address);

    const MyAmm = await ethers.getContractFactory("MyAmm");
    amm = await MyAmm.deploy();
    await amm.initialize(baseToken.address, quoteToken.address, marginAddress);
    // console.log("amm:", amm.address);

    const MockUniswapV3Factory = await ethers.getContractFactory("MockUniswapV3Factory");
    v3factory = await MockUniswapV3Factory.deploy();
    // console.log("v3factory:", v3factory.address);

    const MockUniswapV3Pool = await ethers.getContractFactory("MockUniswapV3Pool");
    pool1 = await MockUniswapV3Pool.deploy(baseToken.address, quoteToken.address, 500);
    await pool1.setLiquidity(1000000000);
    await v3factory.setPool(baseToken.address, quoteToken.address, 500, pool1.address);

    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    oracle = await PriceOracle.deploy();
    await oracle.initialize(v3factory.address);
    // console.log("oracle:", oracle.address);
  });

  describe("quoteFromAmmTwap", function () {
    beforeEach(async function () {
      await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
      await oracle.setupTwap(amm.address);
      await oracle.updateAmmTwap(amm.address);
      await mineBlocks(500);
      await oracle.updateAmmTwap(amm.address);
      await mineBlocks(500);
      await oracle.updateAmmTwap(amm.address);
      await mineBlocks(500);
      await oracle.updateAmmTwap(amm.address);
      await mineBlocks(500);
      await oracle.updateAmmTwap(amm.address);
    });

    it("quote from amm twap", async function () {
      let baseAmount = BigNumber.from("1000000000000000000");
      let quoteAmount = await oracle.quoteFromAmmTwap(amm.address, baseAmount);
      console.log("quoteAmount:", BigNumber.from(quoteAmount).toString());
      expect(BigNumber.from(quoteAmount)).to.be.gt(BigNumber.from("1000000000"));
      expect(BigNumber.from(quoteAmount)).to.be.lte(BigNumber.from("2000000000"));
    });
  });

  describe("quote", function () {
    beforeEach(async function () {
      pool1.initialize(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
      await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
      await oracle.setupTwap(amm.address);
      pool1.writeObservation();
      await mineBlocks(500);
      pool1.writeObservation();
      await mineBlocks(500);
      pool1.writeObservation();
      await mineBlocks(500);
      pool1.writeObservation();
      await mineBlocks(500);
      pool1.writeObservation();
    });

    it("quote big number", async function () {
      let result = await oracle.quote(baseToken.address, quoteToken.address, BigNumber.from("1000000000000000000"));
      console.log("quoteAmount:", BigNumber.from(result.quoteAmount).toString());
      expect(BigNumber.from(result.quoteAmount)).to.be.gt(BigNumber.from("1000000000"));
      expect(BigNumber.from(result.quoteAmount)).to.be.lte(BigNumber.from("2000000000"));
    });

    it("getIndexPrice: base < quote", async function () {
      let indexPrice = await oracle.getIndexPrice(amm.address);
      console.log("indexPrice:", BigNumber.from(indexPrice).toString());
      expect(BigNumber.from(indexPrice)).to.be.gt(BigNumber.from("1000000000000000000000"));
      expect(BigNumber.from(indexPrice)).to.be.lte(BigNumber.from("2000000000000000000000"));
    });
  });

  describe("compare ammTwap & indexPrice", function () {
    beforeEach(async function () {
      await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
      pool1.initialize(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
      await oracle.setupTwap(amm.address);
      await oracle.updateAmmTwap(amm.address);
      pool1.writeObservation();
      await mineBlocks(500);
      await oracle.updateAmmTwap(amm.address);
      pool1.writeObservation();
      await mineBlocks(500);
      await oracle.updateAmmTwap(amm.address);
      pool1.writeObservation();
      await mineBlocks(500);
      await oracle.updateAmmTwap(amm.address);
      pool1.writeObservation();
      await mineBlocks(500);
      await oracle.updateAmmTwap(amm.address);
      pool1.writeObservation();
    });

    it("compare", async function () {
      let baseAmount = BigNumber.from("1000000000000000000");
      let quoteAmountFromTwap = await oracle.quoteFromAmmTwap(amm.address, baseAmount);
      console.log("quoteAmountFromTwap:", BigNumber.from(quoteAmountFromTwap).toString());
      expect(BigNumber.from(quoteAmountFromTwap)).to.be.gt(BigNumber.from("1000000000"));
      expect(BigNumber.from(quoteAmountFromTwap)).to.be.lte(BigNumber.from("2000000000"));

      let result = await oracle.quote(baseToken.address, quoteToken.address, baseAmount);
      console.log("quoteAmountFromIndex:", BigNumber.from(result.quoteAmount).toString());
      expect(BigNumber.from(result.quoteAmount)).to.be.gt(BigNumber.from("1000000000"));
      expect(BigNumber.from(result.quoteAmount)).to.be.lte(BigNumber.from("2000000000"));

      expect(result.quoteAmount).to.be.equal(quoteAmountFromTwap);
    });
  });

  describe("getMarkPrice", function () {
    it("getMarkPrice: price > 1", async function () {
      await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
      let markPrice = await oracle.getMarkPrice(amm.address);
      console.log("markPrice:", BigNumber.from(markPrice).toString());
      expect(markPrice == BigNumber.from("2000000000000000000000"));
    });

    it("getMarkPrice: price < 1", async function () {
      await amm.setReserves(BigNumber.from("1000000000000000000000"), BigNumber.from("2000000"));
      let markPrice = await oracle.getMarkPrice(amm.address);
      console.log("markPrice:", BigNumber.from(markPrice).toString());
      expect(markPrice == BigNumber.from("2000000000000000"));
    });
  });

  describe("getMarkPriceAcc", function () {
    beforeEach(async function () {
      pool1.initialize(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
      await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
      await oracle.setupTwap(amm.address);
      pool1.writeObservation();
      await mineBlocks(500);
      pool1.writeObservation();
      await mineBlocks(500);
      pool1.writeObservation();
      await mineBlocks(500);
      pool1.writeObservation();
      await mineBlocks(500);
      pool1.writeObservation();
    });

    it("getMarkPriceAcc: base < quote", async function () {
      await amm.setReserves(1000, 2000);
      let markPriceAcc = await oracle.getMarkPriceAcc(amm.address, 5, 1000, false);
      console.log("markPriceAcc:", BigNumber.from(markPriceAcc).toString());
    });

    it("getMarkPriceAcc: base > quote", async function () {
      await amm.setReserves(2000000000, 2000);
      let markPriceAcc = await oracle.getMarkPriceAcc(amm.address, 5, 1000, false);
      console.log("markPriceAcc:", BigNumber.from(markPriceAcc).toString());
    });
  });

  describe("getPremiumFraction", function () {
    beforeEach(async function () {
      pool1.initialize(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
      await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
      await oracle.setupTwap(amm.address);
      pool1.writeObservation();
      await mineBlocks(500);
      pool1.writeObservation();
      await mineBlocks(500);
      pool1.writeObservation();
      await mineBlocks(500);
      pool1.writeObservation();
      await mineBlocks(500);
      pool1.writeObservation();
    });

    it("getPremiumFraction: base < quote", async function () {
      await amm.setReserves(1000, 2000);
      let premiumFraction = await oracle.getPremiumFraction(amm.address);
      console.log("premiumFraction:", BigNumber.from(premiumFraction).toString());
    });

    it("getPremiumFraction: base > quote", async function () {
      await amm.setReserves(2000000000, 2000);
      let premiumFraction = await oracle.getPremiumFraction(amm.address);
      console.log("premiumFraction:", BigNumber.from(premiumFraction).toString());
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

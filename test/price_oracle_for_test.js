const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");
const base = "0xD4c652999084ef502Cbe6b0a2bD7277b7dab092E";
const quote = "0xAd4215344396F4B53AaF7B494Cc3580E8CF14104";

describe("PriceOracleForTest contract", function () {
  let poft;
  beforeEach(async function () {
    [owner, addr1, liquidator, ...addrs] = await ethers.getSigners();

    const PriceOracleForTest = await ethers.getContractFactory("PriceOracleForTest");
    poft = await PriceOracleForTest.deploy();

    await poft.setReserve(base, quote, 10000, 20000);
  });
  describe("query", async function () {
    it("get reserves", async function () {
      let result = await poft.getReserves(base, quote);
      expect(result[0]).to.equal(10000);
      expect(result[1]).to.equal(20000);
    });

    it("query quote", async function () {
      let result = await poft.quote(base, quote, 10);
      expect(result).to.equal(20);
    });
  });
});

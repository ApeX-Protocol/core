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

  // describe("quoteFromAmmTwap", function () {
  //   let dateTime = new Date();
  //   let ct = Math.floor(dateTime / 1000);

  //   beforeEach(async function () {
  //     await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000000"));
  //     await oracle.setupTwap(amm.address);
  //     await oracle.updateAmmTwap(amm.address);
  //     ct += 500;
  //     await ethers.provider.send("evm_setNextBlockTimestamp", [ct]);
  //     await network.provider.send("evm_mine");
  //     await amm.setReserves(BigNumber.from("990099009900990099"), BigNumber.from("2020000000000"));
  //     await oracle.updateAmmTwap(amm.address);
  //     ct += 500;
  //     await ethers.provider.send("evm_setNextBlockTimestamp", [ct]);
  //     await network.provider.send("evm_mine");
  //     await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000000"));
  //     await oracle.updateAmmTwap(amm.address);
  //     ct += 500;
  //     await ethers.provider.send("evm_setNextBlockTimestamp", [ct]);
  //     await network.provider.send("evm_mine");
  //     await amm.setReserves(BigNumber.from("1010101010101010101"), BigNumber.from("1980000000000"));
  //     await oracle.updateAmmTwap(amm.address);
  //     ct += 500;
  //     await ethers.provider.send("evm_setNextBlockTimestamp", [ct]);
  //     await network.provider.send("evm_mine");
  //   });

  //   it("quote from amm twap", async function () {
  //     let baseAmount = BigNumber.from("1010101010101010101");
  //     let quoteAmount = await oracle.quoteFromAmmTwap(amm.address, baseAmount);
  //     console.log("quoteAmount:", BigNumber.from(quoteAmount).toString());
  //     expect(BigNumber.from(quoteAmount)).to.be.eq(BigNumber.from("2004345142222"));
  //   });
  // });

  // describe("quote", function () {
  //   let dateTime = new Date();
  //   let ct = Math.floor(dateTime / 1000);
  //   beforeEach(async function () {
  //     pool1.initialize(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
  //     await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
  //     await oracle.setupTwap(amm.address);

  //     for (let i=0; i < 5; i++){
  //       ct += 500;
  //       await pool1.writeObservation();
  //       await ethers.provider.send("evm_setNextBlockTimestamp", [ct]);
  //       await network.provider.send("evm_mine");
  //     }
  //   });

  //   it("quote big number", async function () {
  //     let result = await oracle.quote(baseToken.address, quoteToken.address, BigNumber.from("1000000000000000000"));
  //     console.log("quoteAmount:", BigNumber.from(result.quoteAmount).toString());
  //     expect(BigNumber.from(result.quoteAmount)).to.be.eq(BigNumber.from("1999840305"));
  //   });

  //   it("getIndexPrice: base > quote", async function () {
  //     let indexPrice = await oracle.getIndexPrice(amm.address);
  //     console.log("indexPrice:", BigNumber.from(indexPrice).toString());
  //     expect(BigNumber.from(indexPrice)).to.be.eq(BigNumber.from("1999840305000000000000"));
  //   });
  // });

  // describe("quote", function () {
  //   it("getIndexPrice: base < quote", async function () {
  //   let dateTime = new Date();
  //   let ct = Math.floor(dateTime / 1000);
  //     pool1.initialize(BigNumber.from("10000000"), BigNumber.from("200000000000000"));
  //     await amm.setReserves(BigNumber.from("10000000"), BigNumber.from("200000000000000"));
  //     await oracle.setupTwap(amm.address);

  //     for (let i=0; i < 5; i++){
  //       ct += 500;
  //       await pool1.writeObservation();
  //       await ethers.provider.send("evm_setNextBlockTimestamp", [ct]);
  //       await network.provider.send("evm_mine");
  //     }

  //     let indexPrice = await oracle.getIndexPrice(amm.address);
  //     console.log("indexPrice:", BigNumber.from(indexPrice).toString());
  //     expect(BigNumber.from(indexPrice)).to.be.eq(BigNumber.from("19998332559863423640114816000000000000"));
  //   });
  // });

  // describe("compare ammTwap & indexPrice", function () {
  //   let dateTime = new Date();
  //   let ct = Math.floor(dateTime / 1000);
    
  //   beforeEach(async function () {
  //     await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
  //     await pool1.initialize(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
  //     await oracle.setupTwap(amm.address);

  //     for (let i=0; i < 5; i++){
  //       ct += 500;
  //       await oracle.updateAmmTwap(amm.address);
  //       await pool1.writeObservation();
  //       await ethers.provider.send("evm_setNextBlockTimestamp", [ct]);
  //       await network.provider.send("evm_mine");
  //     }
  //   });

  //   it("compare", async function () {
  //     let baseAmount = BigNumber.from("1000000000000000000");
  //     let quoteAmountFromTwap = await oracle.quoteFromAmmTwap(amm.address, baseAmount);
  //     console.log("quoteAmountFromTwap:", BigNumber.from(quoteAmountFromTwap).toString());
  //     expect(BigNumber.from(quoteAmountFromTwap)).to.be.eq(BigNumber.from("1999840305"));

  //     let result = await oracle.quote(baseToken.address, quoteToken.address, baseAmount);
  //     console.log("quoteAmountFromIndex:", BigNumber.from(result.quoteAmount).toString());
  //     expect(BigNumber.from(result.quoteAmount)).to.be.eq(BigNumber.from("1999840305"));

  //     expect(result.quoteAmount).to.be.equal(quoteAmountFromTwap);
  //   });
  // });

  // describe("getMarkPrice", function () {
  //   it("getMarkPrice: price > 1", async function () {
  //     await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
  //     let markPrice = await oracle.getMarkPrice(amm.address);
  //     console.log("markPrice:", BigNumber.from(markPrice).toString());
  //     expect(markPrice == BigNumber.from("2000000000000000000000"));
  //   });

  //   it("getMarkPrice: price < 1", async function () {
  //     await amm.setReserves(BigNumber.from("1000000000000000000000"), BigNumber.from("2000000"));
  //     let markPrice = await oracle.getMarkPrice(amm.address);
  //     console.log("markPrice:", BigNumber.from(markPrice).toString());
  //     expect(markPrice == BigNumber.from("2000000000000000"));
  //   });
  // });

  // describe("getMarkPriceAcc", function () {
  //   let dateTime = new Date();
  //   let ct = Math.floor(dateTime / 1000);

  //   beforeEach(async function () {
  //     pool1.initialize(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
  //     await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
  //     await oracle.setupTwap(amm.address);

  //     for (let i=0; i < 5; i++){
  //       ct += 500;
  //       await pool1.writeObservation();
  //       await ethers.provider.send("evm_setNextBlockTimestamp", [ct]);
  //       await network.provider.send("evm_mine");
  //     }
  //   });

  //   it("getMarkPriceAcc: base < quote", async function () {
  //     await amm.setReserves(1000, 2000);
  //     let markPriceAcc = await oracle.getMarkPriceAcc(amm.address, 5, 1000, false);
  //     console.log("markPriceAcc:", BigNumber.from(markPriceAcc).toString());
  //   });

  //   it("getMarkPriceAcc: base > quote", async function () {
  //     await amm.setReserves(2000000000, 2000);
  //     let markPriceAcc = await oracle.getMarkPriceAcc(amm.address, 5, 1000, false);
  //     console.log("markPriceAcc:", BigNumber.from(markPriceAcc).toString());
  //   });
  // });

  describe("getPremiumFraction", function () {
    let dateTime = new Date();
    let ct = Math.floor(dateTime / 1000);

    beforeEach(async function () {
      pool1.initialize(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
      await amm.setReserves(BigNumber.from("1000000000000000000"), BigNumber.from("2000000000"));
      await oracle.setupTwap(amm.address);

      for (let i=0; i < 5; i++){
        ct += 500;
        await pool1.writeObservation();
        await ethers.provider.send("evm_setNextBlockTimestamp", [ct]);
        await network.provider.send("evm_mine");
      }
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

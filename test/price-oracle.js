const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");

describe("PriceOracle contract", function () {
  let v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
  let v2FactoryAddress = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4";
  let wethAddress = "0xc778417E063141139Fce010982780140Aa0cD5Ab";
  let baseToken;
  let quoteToken;
  let apeXToken;
  let amm;
  let pool1;
  let pool2;
  let pool3;
  let factory;
  let oracle;

  beforeEach(async function () {
    const MockToken = await ethers.getContractFactory("MockToken");
    baseToken = await MockToken.deploy("Base Token", "BT");
    quoteToken = await MockToken.deploy("Quote Token", "QT");
    apeXToken = await MockToken.deploy("ApeX Token", "APEX");
    console.log("baseToken:", baseToken.address);
    console.log("quoteToken:", quoteToken.address);

    const MockAmm = await ethers.getContractFactory("MockAmm");
    amm = await MockAmm.deploy("amm shares", "AS");
    await amm.initialize(baseToken.address, quoteToken.address);

    const MockUniswapV3Pool = await ethers.getContractFactory("MockUniswapV3Pool");
    const MockUniswapV3Factory = await ethers.getContractFactory("MockUniswapV3Factory");
    pool1 = await MockUniswapV3Pool.deploy(baseToken.address, quoteToken.address, 500);
    await pool1.setLiquidity(10000);
    await pool1.setSqrtPriceX96(4000000);
    pool2 = await MockUniswapV3Pool.deploy(baseToken.address, quoteToken.address, 3000);
    await pool2.setLiquidity(50000);
    await pool2.setSqrtPriceX96(4000000);
    pool3 = await MockUniswapV3Pool.deploy(baseToken.address, quoteToken.address, 10000);
    await pool3.setLiquidity(6000);
    await pool3.setSqrtPriceX96(4000000);

    factory = await MockUniswapV3Factory.deploy();
    await factory.setPool(baseToken.address, quoteToken.address, 500, pool1.address);
    await factory.setPool(baseToken.address, quoteToken.address, 3000, pool2.address);
    await factory.setPool(baseToken.address, quoteToken.address, 10000, pool3.address);

    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    oracle = await PriceOracle.deploy(v3FactoryAddress, v2FactoryAddress, wethAddress);
  });

  // describe("quote", function () {
  //   it("quote small number", async function () {
  //     let quoteAmount = await oracle.quote(baseToken.address, quoteToken.address, 10000);
  //     console.log("quoteAmount:", BigNumber.from(quoteAmount).toString());
  //   });

  //   it("quote big number", async function () {
  //     let quoteAmount = await oracle.quote(
  //       baseToken.address,
  //       quoteToken.address,
  //       BigNumber.from("100000000000000000000")
  //     );
  //     console.log("quoteAmount:", BigNumber.from(quoteAmount).toString());
  //   });
  // });

  // describe("getIndexPrice", function () {
  //   it("getIndexPrice: base < quote", async function () {
  //     await amm.setReserves(1000, 2000);
  //     let indexPrice = await oracle.getIndexPrice(amm.address);
  //     console.log("indexPrice:", BigNumber.from(indexPrice).toString());
  //   });

  //   it("getIndexPrice: base > quote", async function () {
  //     await amm.setReserves(200000000, 2000);
  //     let indexPrice = await oracle.getIndexPrice(amm.address);
  //     console.log("indexPrice:", BigNumber.from(indexPrice).toString());
  //   });
  // });

  // describe("getMarkPrice", function () {
  //   it("getMarkPrice: base < quote", async function () {
  //     await amm.setReserves(1000, 200000000);
  //     let markPrice = await oracle.getMarkPrice(amm.address);
  //     console.log("markPrice:", BigNumber.from(markPrice).toString());
  //   });

  //   it("getMarkPrice: quote > base", async function () {
  //     await amm.setReserves(2000000000, 1000);
  //     let markPrice = await oracle.getMarkPrice(amm.address);
  //     console.log("markPrice:", BigNumber.from(markPrice).toString());
  //   });
  // });

  describe("getMarkPriceAcc", function () {
    it("getMarkPriceAcc: base < quote", async function () {
      await amm.setReserves(1000, 2000);
      let markPriceAcc = await oracle.getMarkPriceAcc(amm.address, 5, 1000, false);
      console.log("markPriceAcc:", BigNumber.from(markPriceAcc).toString());
    });

    // it("getMarkPriceAcc: base > quote", async function () {
    //   await amm.setReserves(2000000000, 2000);
    //   let markPriceAcc = await oracle.getMarkPriceAcc(amm.address, 5, 1000, false);
    //   console.log("markPriceAcc:", BigNumber.from(markPriceAcc).toString());
    // });
  });

  // describe("getPremiumFraction", function () {
  //   it("getPremiumFraction: base < quote", async function () {
  //     await amm.setReserves(1000, 2000);
  //     let premiumFraction = await oracle.getPremiumFraction(amm.address);
  //     console.log("premiumFraction:", BigNumber.from(premiumFraction).toString());
  //   });

  //   it("getPremiumFraction: base > quote", async function () {
  //     await amm.setReserves(2000000000, 2000);
  //     let premiumFraction = await oracle.getPremiumFraction(amm.address);
  //     console.log("premiumFraction:", BigNumber.from(premiumFraction).toString());
  //   });
  // });
});

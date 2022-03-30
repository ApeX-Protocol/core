const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");

describe("PriceOracle contract", function () {
  let weth;
  let apeX;
  let wbtc;
  let usdc;
  let pool1;
  let pool2;
  let pool3;
  let v3factory;
  let oracle;

  beforeEach(async function () {
    const MockWETH = await ethers.getContractFactory("MockWETH");
    weth = await MockWETH.deploy();

    const MyToken = await ethers.getContractFactory("MyToken");
    apeX = await MyToken.deploy("ApeX Token", "APEX", 18, BigNumber.from("100000000000000000000000000"));
    wbtc = await MyToken.deploy("WBTC", "WBTC", 18, BigNumber.from("100000000000000000000000000"));
    usdc = await MyToken.deploy("USDC", "USDC", 6, BigNumber.from("1000000000000000"));
    // console.log("baseToken:", baseToken.address);
    // console.log("quoteToken:", quoteToken.address);

    const MockUniswapV3Factory = await ethers.getContractFactory("MockUniswapV3Factory");
    v3factory = await MockUniswapV3Factory.deploy();
    // console.log("v3factory:", v3factory.address);

    const MockUniswapV3Pool = await ethers.getContractFactory("MockUniswapV3Pool");
    pool1 = await MockUniswapV3Pool.deploy(apeX.address, weth.address, 500);
    await pool1.setLiquidity(1000000000);
    await v3factory.setPool(apeX.address, weth.address, 500, pool1.address);

    pool2 = await MockUniswapV3Pool.deploy(wbtc.address, weth.address, 500);
    await pool2.setLiquidity(1000000000);
    await v3factory.setPool(wbtc.address, weth.address, 500, pool2.address);

    pool3 = await MockUniswapV3Pool.deploy(usdc.address, weth.address, 500);
    await pool3.setLiquidity(1000000000);
    await v3factory.setPool(usdc.address, weth.address, 500, pool3.address);

    const PriceOracle = await ethers.getContractFactory("BondPriceOracle");
    oracle = await PriceOracle.deploy();
    await oracle.initialize(apeX.address, weth.address, v3factory.address);
    await oracle.setupTwap(wbtc.address);
    await oracle.setupTwap(usdc.address);
    // console.log("oracle:", oracle.address);
  });

  describe("quote", function () {
    beforeEach(async function () {
      pool1.initialize(BigNumber.from("2000000000000000000000"), BigNumber.from("1000000000000000000"));
      pool2.initialize(BigNumber.from("100000000000000000"), BigNumber.from("1000000000000000000"));
      pool3.initialize(BigNumber.from("2000000000"), BigNumber.from("1000000000000000000"));
      await pool1.writeObservation();
      await pool2.writeObservation();
      await pool3.writeObservation();
      await mineBlocks(500);
      await pool1.writeObservation();
      await pool2.writeObservation();
      await pool3.writeObservation();
      await mineBlocks(500);
      await pool1.writeObservation();
      await pool2.writeObservation();
      await pool3.writeObservation();
      await mineBlocks(500);
      await pool1.writeObservation();
      await pool2.writeObservation();
      await pool3.writeObservation();
      await mineBlocks(500);
      await pool1.writeObservation();
      await pool2.writeObservation();
      await pool3.writeObservation();
    });

    it("quote weth", async function () {
      let apeXAmount = await oracle.quote(weth.address, BigNumber.from("10000"));
      console.log("result:", BigNumber.from(apeXAmount).toString());
    });

    it("quote wbtc", async function () {
      let apeXAmount = await oracle.quote(wbtc.address, BigNumber.from("10000"));
      console.log("result:", BigNumber.from(apeXAmount).toString());
    });

    it("quote usdc", async function () {
      let apeXAmount = await oracle.quote(usdc.address, BigNumber.from("10000"));
      console.log("result:", BigNumber.from(apeXAmount).toString());
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

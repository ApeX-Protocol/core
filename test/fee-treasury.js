const { expect } = require("chai");
const { BigNumber } = require("@ethersproject/bignumber");

describe("FeeTreasury contract", function () {
  let owner;
  let operator;
  let rewardForStaking;
  let rewardForCashback;
  let weth;
  let usdc;
  let wbtc;
  let swapRouter;
  let v3factory;
  let v3pool1;
  let v3pool2;
  let marginAddress = "0xb9cBC6759a4b71C127047c6aAcdDB569168A5046";
  let amm1;
  let amm2;
  let amm3;
  let feeTreasury;

  beforeEach(async function () {
    [owner, operator, rewardForStaking, rewardForCashback] = await ethers.getSigners();

    const MockWETH = await ethers.getContractFactory("MockWETH");
    weth = await MockWETH.deploy();
    await weth.deposit({
      value: ethers.utils.parseEther("1"),
    });

    const MyToken = await ethers.getContractFactory("MyToken");
    usdc = await MyToken.deploy("USDC", "USDC", 6, BigNumber.from("1000000000000000"));
    wbtc = await MyToken.deploy("WBTC", "WBTC", 8, BigNumber.from("100000000000000000"));

    const MockUniswapV3Factory = await ethers.getContractFactory("MockUniswapV3Factory");
    v3factory = await MockUniswapV3Factory.deploy();

    const MockUniswapV3Pool = await ethers.getContractFactory("MockUniswapV3Pool");
    v3pool1 = await MockUniswapV3Pool.deploy(weth.address, usdc.address, 500);
    await v3pool1.setLiquidity(1000000000);
    await v3factory.setPool(weth.address, usdc.address, 500, v3pool1.address);

    v3pool2 = await MockUniswapV3Pool.deploy(wbtc.address, usdc.address, 500);
    await v3pool2.setLiquidity(1000000000);
    await v3factory.setPool(wbtc.address, weth.address, 500, v3pool2.address);

    const MockSwapRouter = await ethers.getContractFactory("MockSwapRouter");
    swapRouter = await MockSwapRouter.deploy(weth.address, v3factory.address);

    const MyAmm = await ethers.getContractFactory("MyAmm");
    amm1 = await MyAmm.deploy();
    await amm1.initialize(weth.address, usdc.address, marginAddress);

    amm2 = await MyAmm.deploy();
    await amm2.initialize(wbtc.address, usdc.address, marginAddress);

    amm3 = await MyAmm.deploy();
    await amm3.initialize(weth.address, wbtc.address, marginAddress);

    const FeeTreasury = await ethers.getContractFactory("FeeTreasury");
    feeTreasury = await FeeTreasury.deploy(swapRouter.address, usdc.address, operator.address, 1000000);
    await feeTreasury.setRewardForStaking(rewardForStaking.address);
    await feeTreasury.setRewardForCashback(rewardForCashback.address);
  });

  describe("batchRemoveLiquidity", function () {
    beforeEach(async function () {
      await weth.transfer(amm1.address, 1000);
      await amm1.mint(feeTreasury.address);
      await weth.transfer(amm3.address, 1000);
      await amm3.mint(feeTreasury.address);
    });

    it("not operator", async function () {
      await expect(feeTreasury.batchRemoveLiquidity([amm1.address])).to.be.revertedWith("FORBIDDEN");
    });

    it("operator remove one amm", async function () {
      let feeTreasuryWithOperator = feeTreasury.connect(operator);
      await feeTreasuryWithOperator.batchRemoveLiquidity([amm1.address]);
      let balance = await weth.balanceOf(feeTreasury.address);
      console.log("balance:", balance.toString());
      expect(balance).to.be.equal(100);
    });

    it("operator remove two amms", async function () {
      let feeTreasuryWithOperator = feeTreasury.connect(operator);
      await feeTreasuryWithOperator.batchRemoveLiquidity([amm1.address, amm3.address]);
      let balance = await weth.balanceOf(feeTreasury.address);
      console.log("balance:", balance.toString());
      expect(balance).to.be.equal(200);
    });
  });

  describe("batchSwapToETH", function () {
    beforeEach(async function () {
      await weth.transfer(amm1.address, 1000);
      await amm1.mint(feeTreasury.address);
      await wbtc.transfer(amm2.address, 1000);
      await amm2.mint(feeTreasury.address);
      await weth.transfer(v3pool1.address, 100);
      await usdc.transfer(v3pool1.address, 100);
      await weth.transfer(v3pool2.address, 100);
      await wbtc.transfer(v3pool2.address, 100);
    });

    it("not operator", async function () {
      await expect(feeTreasury.batchSwapToETH([wbtc.address])).to.be.revertedWith("FORBIDDEN");
    });

    it("operator execute", async function () {
      let feeTreasuryWithOperator = feeTreasury.connect(operator);
      await feeTreasuryWithOperator.batchRemoveLiquidity([amm2.address]);
      await feeTreasuryWithOperator.batchSwapToETH([wbtc.address]);
    });
  });

  describe("distrbute", function () {
    beforeEach(async function () {
      await weth.transfer(amm1.address, 1000);
      await amm1.mint(feeTreasury.address);
      await wbtc.transfer(amm2.address, 1000);
      await amm2.mint(feeTreasury.address);
      await weth.transfer(v3pool1.address, 100);
      await usdc.transfer(v3pool1.address, 100);
      await weth.transfer(v3pool2.address, 100);
      await wbtc.transfer(v3pool2.address, 100);
    });

    it("not operator", async function () {
      await expect(feeTreasury.distrbute()).to.be.revertedWith("FORBIDDEN");
    });

    it("operator execute", async function () {
      let feeTreasuryWithOperator = feeTreasury.connect(operator);
      await feeTreasuryWithOperator.batchRemoveLiquidity([amm2.address]);
      await feeTreasuryWithOperator.batchSwapToETH([wbtc.address]);
      await feeTreasuryWithOperator.distrbute();
    });
  });
});

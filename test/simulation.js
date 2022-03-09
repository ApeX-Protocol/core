const { expect } = require("chai");
const { BigNumber } = require("@ethersproject/bignumber");
const fs = require('fs');


describe("Simulations", function () {
  let owner;
  let treasury;
  let weth;
  let router;
  let priceOracle;
  let baseToken;
  let quoteToken;
  let v3factory;
  let pool1;
  let config;
  let margin;
  let ammAddress;
  let amm;
  let provider = ethers.provider;

  const tokenQuantity = ethers.utils.parseUnits("250", "ether");
  const largeTokenQuantity = ethers.utils.parseUnits("1000", "ether");
  const infDeadline = "9999999999";

  // normal distribution needed for geometric brownian motion of price in
  // stochastic simulation

  // Standard Normal variate using Box-Muller transform.
  function randn_bm() {
      return Math.sqrt(-2 * Math.log(1 - Math.random())) * Math.cos(2 * Math.PI * Math.random())
  }

  beforeEach(async function () {
    [owner, treasury, alice, bob, arbitrageur] = await ethers.getSigners();

    const MockWETH = await ethers.getContractFactory("MockWETH");
    weth = await MockWETH.deploy();

    const MockToken = await ethers.getContractFactory("MockToken");
    baseToken = await MockToken.deploy("Base Token", "BT");
    quoteToken = await MockToken.deploy("Quote Token", "QT");

    const Config = await ethers.getContractFactory("Config");
    config = await Config.deploy();

    const MockUniswapV3Factory = await ethers.getContractFactory("MockUniswapV3Factory");
    v3factory = await MockUniswapV3Factory.deploy();
    const MockUniswapV3Pool = await ethers.getContractFactory("MockUniswapV3Pool");
    pool1 = await MockUniswapV3Pool.deploy(baseToken.address, quoteToken.address, 500);
    await pool1.setLiquidity(1000000000);
    await v3factory.setPool(baseToken.address, quoteToken.address, 500, pool1.address);

    const PriceOracle = await ethers.getContractFactory("PriceOracleForTest");
    priceOracle = await PriceOracle.deploy();
    //await priceOracle.initialize(v3factory.address);
    await priceOracle.setReserve(baseToken.address, quoteToken.address, 10000000, 20000000);
    await priceOracle.setReserve(weth.address, quoteToken.address, 10000000, 20000000);
    await config.setPriceOracle(priceOracle.address);

    const PairFactory = await ethers.getContractFactory("PairFactory");
    pairFactory = await PairFactory.deploy();

    const AmmFactory = await ethers.getContractFactory("AmmFactory");
    const MarginFactory = await ethers.getContractFactory("MarginFactory");
    let ammFactory = await AmmFactory.deploy(pairFactory.address, config.address, owner.address);
    let marginFactory = await MarginFactory.deploy(pairFactory.address, config.address);
    await pairFactory.init(ammFactory.address, marginFactory.address);
    await pairFactory.createPair(baseToken.address, quoteToken.address);

    let marginAddress = await pairFactory.getMargin(baseToken.address, quoteToken.address);
    const Margin = await ethers.getContractFactory("Margin");
    margin = await Margin.attach(marginAddress);

    ammAddress = await pairFactory.getAmm(baseToken.address, quoteToken.address);
    const Amm = await ethers.getContractFactory("Amm");
    amm = await Amm.attach(ammAddress);

    const Router = await ethers.getContractFactory("Router");
    router = await Router.deploy(pairFactory.address, treasury.address, weth.address);
    await config.registerRouter(router.address);
  });

  describe("check pool pnl given beta", function () {
    it("liquidates a position properly", async function () {
      await config.setBeta(100);
      await baseToken.mint(alice.address, tokenQuantity);
      await baseToken.connect(alice).approve(router.address, tokenQuantity);
      await baseToken.mint(bob.address, tokenQuantity);
      await baseToken.connect(bob).approve(router.address, tokenQuantity);
      await baseToken.mint(owner.address, largeTokenQuantity);
      await baseToken.connect(owner).approve(router.address, largeTokenQuantity);
      await router.addLiquidity(baseToken.address, quoteToken.address, largeTokenQuantity, 1, infDeadline, false);
      await router.connect(alice).openPositionWithWallet(baseToken.address, quoteToken.address, 0, 3300, 10000, 1, infDeadline);
      await router.connect(bob).openPositionWithWallet(baseToken.address, quoteToken.address, 1, 3300, 10000, 5500, infDeadline);
      // check that trader position exists
      // console.log(await margin.getPosition(alice.address));
      await margin.liquidate(alice.address);
      // check that alice's position has been liquidated
      // console.log(await margin.getPosition(alice.address));
      await router.connect(bob).closePosition(baseToken.address, quoteToken.address, 10000, infDeadline, true);
    });
  });

  // TODO in order to set price via price oracle, change reserves in price oracle for test
  // TODO what is the price that I'm starting with effectively
  describe("simulation involving arbitrageur and random trades", function () {
    it("generates simulation data", async function () {
      let logger = fs.createWriteStream('sim.csv');
      logger.write("Oracle Price, Pool Price\n");

      await config.setBeta(100);
      await config.setInitMarginRatio(101);

      await baseToken.mint(arbitrageur.address, largeTokenQuantity);
      await baseToken.connect(arbitrageur).approve(router.address, largeTokenQuantity);
      await baseToken.mint(owner.address, largeTokenQuantity);
      await baseToken.connect(owner).approve(router.address, largeTokenQuantity);
      await router.addLiquidity(baseToken.address, quoteToken.address, largeTokenQuantity, 1, infDeadline, false);

      // variables for geometric brownian motion
      let mu = 0;
      let sig = 0.01;
      let lastPrice = 10000000;

      // variables for the hawkes process simulation
      let simSteps = 3000;
      let lambda0 = 1;
      let a = lambda0;
      let lambdaTplus = lambda0;
      let lambdaTminus;
      let delta = 0.5;
      let meanJump = 0.3;
      let S;

      // active open trades
      let trades = [];

      // Exact simulation of Hawkes process with exponentially decaying intensity 2013
      // TODO should i do two separate simulations of trades from each trader?
      // that doesn't make as much sense as generally clustering trades... have
      // to figure out a good strategy for that.
      for (let i = 0; i < simSteps; i++) {
        let u = Math.random();
        // TODO div by zero?
        let D = 1 + delta * Math.log(u) / (lambdaTplus - a);

        if (D > 0) {
          S = Math.min(1 + delta*Math.log(u), -(1/a) * Math.log(Math.random()));
        } else {
          S = -(1/a) * Math.log(Math.random());
        }

        lambdaTminus = (lambdaTplus-a) * Math.exp(-delta*S) + a;
        lambdaTplus = lambdaTminus + meanJump;

        // consider that a trade occurs whenever S is negative, this happens
        // roughly 10% of the time w/ delta = 0.3, w/ delta = 0.2 it's 1.5% of
        // the time
        if (S < 0) {
          let trader = await ethers.Wallet.createRandom().connect(provider);
          let tx = await owner.sendTransaction({
              to: trader.address,
              value: ethers.utils.parseEther("25.0")
          });
          await baseToken.mint(trader.address, tokenQuantity);
          await baseToken.connect(trader).approve(router.address, tokenQuantity);

          // trader trades randomly
          if (Math.random() > 0.5) {
            await router.connect(trader).openPositionWithWallet(baseToken.address, quoteToken.address, 0, ethers.utils.parseUnits("0.5", "ether"), ethers.utils.parseUnits("5", "ether"), 1, infDeadline);
          } else {
            await router.connect(trader).openPositionWithWallet(baseToken.address, quoteToken.address, 1, ethers.utils.parseUnits("0.5", "ether"), ethers.utils.parseUnits("5", "ether"), ethers.utils.parseUnits("10", "ether"), infDeadline);
          }
          trades.push(trader);
        }

        // TODO liquidator checks all the trader accounts

        // update price in price oracle by geometric brownian motion
        lastPrice = lastPrice * Math.exp((mu - sig*sig / 2) * 0.02 + sig * randn_bm());
        await priceOracle.setReserve(baseToken.address, quoteToken.address, Math.floor(lastPrice), 20000000);
        let price = await priceOracle.getIndexPrice(ammAddress);
        let raw = await amm.lastPrice();
        // get the price out of the 112x112 format & display with 18 decimal accuracy
        let lastPriceAmm = raw.div("5192296858534816");
        logger.write(price + ", " + lastPriceAmm + "\n");

        // arbitrageur gets opportunity to take his trade (should change arb trade sizes? TODO)
        let arbThreshold = 102;
        if (lastPriceAmm * 100 / price > arbThreshold) {
            await router.connect(arbitrageur).openPositionWithWallet(baseToken.address, quoteToken.address, 1, ethers.utils.parseUnits("0.5", "ether"), ethers.utils.parseUnits("5", "ether"), ethers.utils.parseUnits("10", "ether"), infDeadline);
        } else if (price * 100 / lastPriceAmm > arbThreshold) {
            await router.connect(arbitrageur).openPositionWithWallet(baseToken.address, quoteToken.address, 0, ethers.utils.parseUnits("0.5", "ether"), ethers.utils.parseUnits("5", "ether"), 1, infDeadline);
        }

        for (let j = 0; j < trades.length; j++) {
          trader = trades[j];
          let canLiq = await margin.canLiquidate(trader.address);
          let position = await router.getPosition(baseToken.address, quoteToken.address, trader.address);
          console.log(trader.address);
          console.log(j + ": " + canLiq);
          console.log(position);
        }
      }
      logger.end();
    });
  });
});

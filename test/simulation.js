const { expect } = require("chai");
const { BigNumber } = require("@ethersproject/bignumber");
const fs = require('fs');
const seedrandom = require('seedrandom');

let generator = seedrandom('apeX');

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
  let beta = 75;
  let leverage = 10;

  const tokenQuantity = ethers.utils.parseUnits("250000", "ether");
  const largeTokenQuantity = ethers.utils.parseUnits("1000", "ether");
  const infDeadline = "9999999999";

  // normal distribution needed for geometric brownian motion of price in
  // stochastic simulation

  // Standard Normal variate using Box-Muller transform.
  function randn_bm() {
      return Math.sqrt(-2 * Math.log(1 - generator())) * Math.cos(2 * Math.PI * generator())
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
    await priceOracle.setReserve(baseToken.address, quoteToken.address, ethers.utils.parseUnits('1', 'ether'), ethers.utils.parseUnits('2000', 'ether'));
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

    await baseToken.mint(owner.address, largeTokenQuantity);
    await baseToken.connect(owner).approve(router.address, largeTokenQuantity);
    await router.addLiquidity(baseToken.address, quoteToken.address, largeTokenQuantity, 1, infDeadline, false);
  });

  describe.skip("check pool pnl given beta", function () {
    it("liquidates a position properly", async function () {
      await config.setBeta(beta);
      await baseToken.mint(alice.address, tokenQuantity);
      await baseToken.connect(alice).approve(router.address, tokenQuantity);
      await baseToken.mint(bob.address, tokenQuantity);
      await baseToken.connect(bob).approve(router.address, tokenQuantity);
      await baseToken.mint(owner.address, largeTokenQuantity);
      await baseToken.connect(owner).approve(router.address, largeTokenQuantity);
      await router.addLiquidity(baseToken.address, quoteToken.address, largeTokenQuantity, 1, infDeadline, false);
      // get the price out of the 112x112 format & display with 18 decimal accuracy
      await router.connect(alice).openPositionWithWallet(baseToken.address, quoteToken.address, 0, ethers.utils.parseUnits("20", "ether"), ethers.utils.parseUnits("20000", "ether"), 1, infDeadline);

      // NOT LIQUIDATABLE await router.connect(alice).openPositionWithWallet(baseToken.address, quoteToken.address, 1, ethers.utils.parseUnits("1", "ether"), ethers.utils.parseUnits("4000", "ether"), ethers.utils.parseUnits("8000", "ether"), infDeadline);
      await router.connect(bob).openPositionWithWallet(baseToken.address, quoteToken.address, 1, ethers.utils.parseUnits("1", "ether"), ethers.utils.parseUnits("4000", "ether"),  ethers.utils.parseUnits("8000", "ether"), infDeadline);
      // check that trader position exists
      let position = await margin.getPosition(alice.address);

      await margin.liquidate(alice.address);
      // check that alice's position has been liquidated
      await router.connect(bob).closePosition(baseToken.address, quoteToken.address, 10000, infDeadline, true);
    });
  });

  // TODO consider if this function is necessary
  function getMarginAcc(quoteAmount, vUSD, marketPrice) {
    let v1 = 2 * beta / vUSD;
    let v2 = 1 / ((1 / quoteAmount - v1) * marketPrice * 10);
    return v2.abs();
  }

  // TODO in order to set price via price oracle, change reserves in price oracle for test
  // TODO what is the price that I'm starting with effectively
  describe("simulation involving arbitrageur and random trades", function () {
    it("generates simulation data", async function () {
      let simSteps = 3000;
      let logger = fs.createWriteStream('sim_' + beta + '_' + simSteps + '.csv');
      logger.write("Trade, Oracle Price, Pool Price, Liquidation, Liquidation Entry Price, Pool PnL\n");

      await config.setBeta(beta);
      //await config.setInitMarginRatio(101);

      await baseToken.mint(arbitrageur.address, tokenQuantity);
      await baseToken.connect(arbitrageur).approve(router.address, tokenQuantity);

      // variables for geometric brownian motion
      let mu = 0;
      let sig = 0.01;
      let lastPrice = 2000;

      // variables for the hawkes process simulation
      let lambda0 = 1;
      let a = lambda0;
      let lambdaTplus = lambda0;
      let lambdaTminus;
      let delta = 0.5;
      let meanJump = 0.25;
      let S;

      // active open trades
      let trades = [];

      // Exact simulation of Hawkes process with exponentially decaying intensity 2013
      for (let i = 0; i < simSteps; i++) {
        if (i%25 === 0) console.log("SIMULATION STEP #" + i + "\n");
        let u = generator();
        // TODO div by zero? 1st round
        let D = 1 + delta * Math.log(u) / (lambdaTplus - a);

        if (D > 0) {
          S = Math.min(1 + delta*Math.log(u), -(1/a) * Math.log(generator()));
        } else {
          S = -(1/a) * Math.log(generator());
        }

        lambdaTminus = (lambdaTplus-a) * Math.exp(-delta*S) + a;
        lambdaTplus = lambdaTminus + meanJump;

        // update price in price oracle by geometric brownian motion
        lastPrice = lastPrice * Math.exp((mu - sig*sig / 2) * 0.02 + sig * randn_bm());
        await priceOracle.setReserve(baseToken.address, quoteToken.address, ethers.utils.parseUnits("1", "ether"), ethers.utils.parseUnits(Math.floor(lastPrice * 1000000000000).toString(), 6));
        let price = await priceOracle.getIndexPrice(ammAddress);
        let reserves = await amm.getReserves();
        // get the price out of the 112x112 format & display with 18 decimal accuracy
        let lastPriceAmm = reserves[1].mul(ethers.utils.parseUnits("1", "ether")).div(reserves[0]);
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

          let side;
          let quoteAmount = ethers.utils.parseUnits("10000", "ether");
          let marginAmount = quoteAmount.mul(ethers.utils.parseUnits("1", "ether")).div(lastPriceAmm).div(10);
          // trader trades randomly
          if (generator() > 0.5) {
            side = 0;
            await router.connect(trader).openPositionWithWallet(baseToken.address, quoteToken.address, 0, marginAmount, quoteAmount, 1, infDeadline);
            logger.write("1, ");
          } else {
            side = 1;
            await router.connect(trader).openPositionWithWallet(baseToken.address, quoteToken.address, 1, marginAmount, quoteAmount, ethers.utils.parseUnits("1000000", "ether"), infDeadline);
            logger.write("-1, ");
          }
          trades.push([trader, lastPriceAmm, side, side == 0 ? marginAmount.mul(leverage).add(marginAmount)
                                                             : marginAmount.mul(leverage).sub(marginAmount)]);
        } else {
          logger.write("0, ");
        }

        logger.write(price + ", " + lastPriceAmm);

        // TODO this rebase does the opposite of what I'd expect, it rebases in the other direction
        /*
        if (lastPriceAmm * 100 / price > 110 || price * 100 / lastPriceAmm > 110) {
          try {
            await amm.rebase();
            let raw = await amm.lastPrice();
            // get the price out of the 112x112 format & display with 18 decimal accuracy
            let lastPriceAmm = raw.div("5192296858534816");
            console.log("post rebase: " + lastPriceAmm.toString());
          } catch(e) {
          }
        }
        */

        // arbitrageur gets opportunity to take his trade (should change arb trade sizes? TODO)
        let arbThreshold = 101;
        if (lastPriceAmm * 100 / price > arbThreshold) {
            await router.connect(arbitrageur).openPositionWithWallet(baseToken.address, quoteToken.address, 1, ethers.utils.parseUnits("5", "ether"), ethers.utils.parseUnits("8000", "ether"), ethers.utils.parseUnits("1000000", "ether"), infDeadline);
        } else if (price * 100 / lastPriceAmm > arbThreshold) {
            await router.connect(arbitrageur).openPositionWithWallet(baseToken.address, quoteToken.address, 0, ethers.utils.parseUnits("5", "ether"), ethers.utils.parseUnits("8000", "ether"), 1, infDeadline);
        }

        reserves = await amm.getReserves();
        // get the price out of the 112x112 format & display with 18 decimal accuracy
        lastPriceAmm = reserves[1].mul(ethers.utils.parseUnits("1", "ether")).div(reserves[0]);

        let liq = false;

        for (let j = 0; j < trades.length; j++) {
          trader = trades[j][0];
          let canLiq = await margin.canLiquidate(trader.address);
          let position = await router.getPosition(baseToken.address, quoteToken.address, trader.address);
          if (canLiq) {
            let reserves = await amm.getReserves();
            let ammXpreLiq = reserves[0];
            await margin.liquidate(trader.address, owner.address);
            position = await router.getPosition(baseToken.address, quoteToken.address, trader.address);

            // verify that the position is zero'd out
            if (position.quoteSize.isZero()) {
              reserves = await amm.getReserves();
              let originalBaseAmount = trades[j][3];
              let ammXpostLiq = reserves[0];
              // the order of subtraction differs betweeen long/short only to
              // ensure results that are always positive
              let pnl = trades[j][2] == 0 ? originalBaseAmount.sub(ammXpostLiq.sub(ammXpreLiq))
                                          : ammXpreLiq.sub(ammXpostLiq).sub(originalBaseAmount);
              if (trades[j][2] == 0) {
                logger.write(", 1, ");
              } else {
                logger.write(", -1, ");
              }
              logger.write(trades[j][1] + ", " + pnl + "\n");
              liq = true;
              trades.splice(j, 1);
              break;
            } else {
              console.log("Failed to Liquidate!", position);
            }
          }
        }
        if (!liq) logger.write(", 0, 0, 0\n");
      }
      logger.end();
    });
  });
});

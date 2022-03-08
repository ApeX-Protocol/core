const { expect } = require("chai");
const { BN, constants } = require("@openzeppelin/test-helpers");

describe("stakingPoolFactory contract", function () {
  let apexToken;
  let slpToken;
  let esApeXToken;
  let veApeXToken;
  let stakingPoolTemplate;
  let apexPool;
  let stakingPoolFactory;

  let initTimestamp = 1641781192;
  let endTimestamp = 1673288342;
  let secSpanPerUpdate = 2;
  let apeXPerSec = 100;
  let lockTime = 3600 * 24 * 180;

  let owner;
  let addr1;
  let addr2;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    const MockToken = await ethers.getContractFactory("MockToken");
    const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
    const ApeXPool = await ethers.getContractFactory("ApeXPool");
    const EsAPEX = await ethers.getContractFactory("EsAPEX");
    const VeAPEX = await ethers.getContractFactory("VeAPEX");
    const StakingPoolTemplate = await ethers.getContractFactory("StakingPool");

    stakingPoolTemplate = await StakingPoolTemplate.deploy();
    apexToken = await MockToken.deploy("apex token", "at");
    slpToken = await MockToken.deploy("slp token", "slp");
    stakingPoolFactory = await upgrades.deployProxy(StakingPoolFactory, [
      apexToken.address,
      addr1.address,
      apeXPerSec,
      secSpanPerUpdate,
      initTimestamp,
      endTimestamp,
      lockTime,
    ]);
    apexPool = await ApeXPool.deploy(stakingPoolFactory.address, apexToken.address, initTimestamp);
    esApeXToken = await EsAPEX.deploy(stakingPoolFactory.address);
    veApeXToken = await VeAPEX.deploy(stakingPoolFactory.address);

    await stakingPoolFactory.setRemainForOtherVest(50);
    await stakingPoolFactory.setEsApeX(esApeXToken.address);
    await stakingPoolFactory.setVeApeX(veApeXToken.address);
    await stakingPoolFactory.setStakingPoolTemplate(stakingPoolTemplate.address);
    await stakingPoolFactory.registerApeXPool(apexPool.address, 21);

    await apexToken.mint(owner.address, "100000000000000000000");
    await apexToken.mint(stakingPoolFactory.address, "100000000000000000000");
  });

  describe("createPool", function () {
    it("create a pool and register", async function () {
      await stakingPoolFactory.createPool(slpToken.address, initTimestamp, 79);
      expect(await stakingPoolFactory.totalWeight()).to.be.equal(100);
    });

    it("revert when create pool with invalid initTimestamp", async function () {
      await expect(stakingPoolFactory.createPool(slpToken.address, 0, 79)).to.be.revertedWith(
        "spf.initialize: INVALID_INIT_TIMESTAMP"
      );
    });

    it("revert when create pool with invalid poolToken", async function () {
      await expect(stakingPoolFactory.createPool(constants.ZERO_ADDRESS, 10, 79)).to.be.revertedWith(
        "spf.initialize: INVALID_POOL_TOKEN"
      );
    });

    it("revert when create pool with exist poolToken", async function () {
      await stakingPoolFactory.createPool(slpToken.address, 10, 79);
      await expect(stakingPoolFactory.createPool(slpToken.address, 10, 79)).to.be.revertedWith(
        "spf.registerPool: POOL_TOKEN_REGISTERED"
      );
    });
  });

  describe("registerApeXPool", function () {
    it("revert when register a registered stakingPool", async function () {
      await expect(stakingPoolFactory.registerApeXPool(apexPool.address, 79)).to.be.revertedWith(
        "spf.registerPool: POOL_REGISTERED"
      );
    });
  });

  describe("updateApeXPerSec", function () {
    it("update apex rewards per sec", async function () {
      await network.provider.send("evm_mine");
      await stakingPoolFactory.updateApeXPerSec();
      expect(await stakingPoolFactory.apeXPerSec()).to.be.equal(97);
      await network.provider.send("evm_mine");
      await stakingPoolFactory.updateApeXPerSec();
      expect(await stakingPoolFactory.apeXPerSec()).to.be.equal(94);
    });

    it("revert when update apeXPerSec in next block", async function () {
      await stakingPoolFactory.updateApeXPerSec();
      await expect(stakingPoolFactory.updateApeXPerSec()).to.be.revertedWith("spf.updateApeXPerSec: TOO_FREQUENT");
    });
  });

  describe("changePoolWeight", function () {
    it("change pool weight", async function () {
      await stakingPoolFactory.changePoolWeight(apexPool.address, 89);
      expect(await stakingPoolFactory.totalWeight()).to.be.equal(89);
    });
  });

  describe("calStakingPoolApeXReward", function () {
    it("calculate reward after some time", async function () {
      await network.provider.send("evm_mine");
      await stakingPoolFactory.updateApeXPerSec();
      let latestBlock = (await stakingPoolFactory.lastUpdateTimestamp()).toNumber();
      //(latestBlock-0) * 97
      expect(await stakingPoolFactory.calStakingPoolApeXReward(0, apexToken.address)).to.be.equal(latestBlock * 97);
    });
  });

  describe("transferYieldTo", function () {
    it("reverted when transfer apeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.transferYieldTo(addr1.address, 10)).to.be.revertedWith(
        "spf.transferYieldTo: ACCESS_DENIED"
      );
    });
  });

  describe("transferEsApeXTo", function () {
    it("reverted when transfer EsApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.transferEsApeXTo(addr1.address, 10)).to.be.revertedWith(
        "spf.transferEsApeXTo: ACCESS_DENIED"
      );
    });
  });

  describe("transferEsApeXFrom", function () {
    it("reverted when transfer EsApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.transferEsApeXFrom(addr1.address, addr2.address, 10)).to.be.revertedWith(
        "spf.transferEsApeXFrom: ACCESS_DENIED"
      );
    });
  });

  describe("burnEsApeX", function () {
    it("reverted when burn EsApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.burnEsApeX(addr1.address, 10)).to.be.revertedWith(
        "spf.burnEsApeX: ACCESS_DENIED"
      );
    });
  });

  describe("mintEsApeX", function () {
    it("reverted when mint EsApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.mintEsApeX(addr1.address, 10)).to.be.revertedWith(
        "spf.mintEsApeX: ACCESS_DENIED"
      );
    });
  });

  describe("mintVeApeX", function () {
    it("reverted when mint VeApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.mintVeApeX(addr1.address, 10)).to.be.revertedWith(
        "spf.mintVeApeX: ACCESS_DENIED"
      );
    });
  });

  describe("burnVeApeX", function () {
    it("reverted when burn VeApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.burnVeApeX(addr1.address, 10)).to.be.revertedWith(
        "spf.burnVeApeX: ACCESS_DENIED"
      );
    });
  });
});

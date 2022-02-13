const { expect } = require("chai");
const { BN, constants } = require("@openzeppelin/test-helpers");

describe("stakingPoolFactory contract", function () {
  let apexToken;
  let owner;
  let stakingPoolFactory;
  let slpToken;
  let esApeX;
  let mockStakingPool;
  let initTimestamp = 1641781192;
  let endTimestamp = 1673288342;
  let secSpanPerUpdate = 2;
  let apeXPerSec = 100;
  let lockTime = 3600 * 24 * 180;
  let apexStakingPool;
  let addr1;
  let addr2;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    const MockToken = await ethers.getContractFactory("MockToken");
    const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
    const StakingPool = await ethers.getContractFactory("StakingPool");
    const EsAPEX = await ethers.getContractFactory("EsAPEX");

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
    mockStakingPool = await StakingPool.deploy(stakingPoolFactory.address, slpToken.address, apexToken.address, 10);
    esApeX = await EsAPEX.deploy(stakingPoolFactory.address);

    await stakingPoolFactory.setEsApeX(esApeX.address);
    await stakingPoolFactory.createPool(apexToken.address, initTimestamp, 21);
    let apexStakingPoolAddr = (await stakingPoolFactory.pools(apexToken.address))[0];
    apexStakingPool = await StakingPool.attach(apexStakingPoolAddr);

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
        "cp: INVALID_INIT_TIMESTAMP"
      );
    });

    it("revert when create pool with invalid poolToken", async function () {
      await expect(stakingPoolFactory.createPool(constants.ZERO_ADDRESS, 10, 79)).to.be.revertedWith(
        "cp: INVALID_POOL_TOKEN"
      );
    });
  });

  describe("registerPool", function () {
    it("register an unregistered stakingPool", async function () {
      await stakingPoolFactory.registerPool(mockStakingPool.address, 79);
      expect(await stakingPoolFactory.poolTokenMap(mockStakingPool.address)).to.be.equal(slpToken.address);
      expect((await stakingPoolFactory.pools(slpToken.address))[0]).to.be.equal(mockStakingPool.address);
      expect((await stakingPoolFactory.pools(slpToken.address))[1]).to.be.equal(79);
    });

    it("revert when register a registered stakingPool", async function () {
      await stakingPoolFactory.registerPool(mockStakingPool.address, 79);
      await expect(stakingPoolFactory.registerPool(mockStakingPool.address, 79)).to.be.revertedWith(
        "cpf.registerPool: POOL_REGISTERED"
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
      await expect(stakingPoolFactory.updateApeXPerSec()).to.be.revertedWith("cpf.updateApeXPerSec: TOO_FREQUENT");
    });
  });

  describe("changePoolWeight", function () {
    it("change pool weight", async function () {
      await stakingPoolFactory.changePoolWeight(apexStakingPool.address, 89);
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
        "cpf.transferYieldTo: ACCESS_DENIED"
      );
    });
  });

  describe("transferEsApeXTo", function () {
    it("reverted when transfer EsApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.transferEsApeXTo(addr1.address, 10)).to.be.revertedWith(
        "cpf.transferEsApeXTo: ACCESS_DENIED"
      );
    });
  });

  describe("transferEsApeXFrom", function () {
    it("reverted when transfer EsApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.transferEsApeXFrom(addr1.address, addr2.address, 10)).to.be.revertedWith(
        "cpf.transferEsApeXFrom: ACCESS_DENIED"
      );
    });
  });

  describe("burnEsApeX", function () {
    it("reverted when burn EsApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.burnEsApeX(addr1.address, 10)).to.be.revertedWith(
        "cpf.burnEsApeX: ACCESS_DENIED"
      );
    });
  });

  describe("mintEsApeX", function () {
    it("reverted when mint EsApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.mintEsApeX(addr1.address, 10)).to.be.revertedWith(
        "cpf.mintEsApeX: ACCESS_DENIED"
      );
    });
  });
});

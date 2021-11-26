const { expect } = require("chai");
const { BN, constants } = require("@openzeppelin/test-helpers");

describe("stakingPoolFactory contract", function () {
  let apexToken;
  let owner;
  let tx;
  let stakingPoolFactory;
  let slpToken;
  let mockStakingPool;
  let initBlock = 38;
  let endBlock = 7090016;
  let blocksPerUpdate = 2;
  let apexPerBlock = 100;
  let apexStakingPool;
  let treasury;
  let addr1;

  beforeEach(async function () {
    [owner, treasury, addr1] = await ethers.getSigners();

    const MockToken = await ethers.getContractFactory("MockToken");
    const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
    const StakingPool = await ethers.getContractFactory("StakingPool");

    apexToken = await MockToken.deploy("apex token", "at");
    slpToken = await MockToken.deploy("slp token", "slp");
    stakingPoolFactory = await upgrades.deployProxy(StakingPoolFactory, [
      apexToken.address,
      apexPerBlock,
      blocksPerUpdate,
      initBlock,
      endBlock,
    ]);
    mockStakingPool = await StakingPool.deploy(stakingPoolFactory.address, slpToken.address, apexToken.address, 10);

    await stakingPoolFactory.createPool(apexToken.address, initBlock, 21);
    let apexStakingPoolAddr = (await stakingPoolFactory.pools(apexToken.address))[0];
    apexStakingPool = await StakingPool.attach(apexStakingPoolAddr);

    await apexToken.mint(owner.address, "100000000000000000000");
  });

  describe("createPool", function () {
    it("create a pool and register", async function () {
      await stakingPoolFactory.createPool(slpToken.address, initBlock, 79);
      expect(await stakingPoolFactory.totalWeight()).to.be.equal(100);
    });

    it("revert when create pool with invalid initBlock", async function () {
      await expect(stakingPoolFactory.createPool(slpToken.address, 0, 79)).to.be.revertedWith("cp: INVALID_INIT_BLOCK");
    });

    it("revert when create pool with invalid poolToken", async function () {
      await expect(stakingPoolFactory.createPool(constants.ZERO_ADDRESS, 10, 79)).to.be.revertedWith(
        "ERC20Aware: INVALID_POOL_TOKEN"
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

  describe("updateApeXPerBlock", function () {
    it("update apex rewards per block", async function () {
      await network.provider.send("evm_mine");
      await stakingPoolFactory.updateApeXPerBlock();
      expect(await stakingPoolFactory.apeXPerBlock()).to.be.equal(97);
      await network.provider.send("evm_mine");
      await stakingPoolFactory.updateApeXPerBlock();
      expect(await stakingPoolFactory.apeXPerBlock()).to.be.equal(94);
    });

    it("revert when update ApeXPerBlock in next block", async function () {
      await stakingPoolFactory.updateApeXPerBlock();
      await expect(stakingPoolFactory.updateApeXPerBlock()).to.be.revertedWith("cpf.updateApeXPerBlock: TOO_FREQUENT");
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
      await stakingPoolFactory.updateApeXPerBlock();
      let latestBlock = (await stakingPoolFactory.lastUpdateBlock()).toNumber();
      //61 * 97 * 21 / 21
      expect(await stakingPoolFactory.calStakingPoolApeXReward(0, apexToken.address)).to.be.equal(latestBlock * 97);
    });
  });

  describe("setTreasury", function () {
    it("set treasury", async function () {
      await stakingPoolFactory.setTreasury(treasury.address);
      expect(await stakingPoolFactory.treasury()).to.be.equal(treasury.address);
    });
  });

  describe("transferYieldTo", function () {
    beforeEach(async function () {
      let oneYearLockUntil = await oneYearLater();
      await apexToken.approve(apexStakingPool.address, 20000);
      await stakingPoolFactory.setTreasury(treasury.address);

      await apexStakingPool.stake(10000, 0);
    });

    it("transfer apeX from treasury to _to", async function () {
      await network.provider.send("evm_mine");
      await apexStakingPool.unstake(0, 10000);
    });

    it("reverted when transfer apeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.transferYieldTo(addr1.address, 10)).to.be.revertedWith(
        "cpf.transferYieldTo: ACCESS_DENIED"
      );
    });
  });
});

async function oneYearLater() {
  return Math.floor(Date.now() / 1000) + 31536000;
}

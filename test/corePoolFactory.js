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

  beforeEach(async function () {
    [owner] = await ethers.getSigners();

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
    apexStakingPool = (await stakingPoolFactory.pools(apexToken.address))[0];
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

  describe("updateApexPerBlock", function () {
    it("update apex rewards per block", async function () {
      await network.provider.send("evm_mine");
      await stakingPoolFactory.updateApexPerBlock();
      await network.provider.send("evm_mine");
      await stakingPoolFactory.updateApexPerBlock();
    });

    it("revert when update ApexPerBlock in next block", async function () {
      await stakingPoolFactory.updateApexPerBlock();
      await expect(stakingPoolFactory.updateApexPerBlock()).to.be.revertedWith("cpf.updateApexPerBlock: TOO_FREQUENT");
    });
  });

  describe("changePoolWeight", function () {
    it("change pool weight", async function () {
      await stakingPoolFactory.changePoolWeight(apexStakingPool, 89);
      expect(await stakingPoolFactory.totalWeight()).to.be.equal(89);
    });
  });
});

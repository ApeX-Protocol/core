const { expect } = require("chai");
const { BN, constants } = require("@openzeppelin/test-helpers");

describe("corePoolFactory contract", function () {
  let apexToken;
  let owner;
  let tx;
  let corePoolFactory;
  let slpToken;
  let mockCorePool;
  let initBlock = 38;
  let endBlock = 7090016;
  let blocksPerUpdate = 2;
  let apexPerBlock = 100;
  let apexCorePool;

  beforeEach(async function () {
    [owner] = await ethers.getSigners();

    const MockToken = await ethers.getContractFactory("MockToken");
    const CorePoolFactory = await ethers.getContractFactory("CorePoolFactory");
    const CorePool = await ethers.getContractFactory("CorePool");

    apexToken = await MockToken.deploy("apex token", "at");
    slpToken = await MockToken.deploy("slp token", "slp");
    corePoolFactory = await upgrades.deployProxy(CorePoolFactory, [
      apexToken.address,
      apexPerBlock,
      blocksPerUpdate,
      initBlock,
      endBlock,
    ]);
    mockCorePool = await CorePool.deploy(corePoolFactory.address, slpToken.address, apexToken.address, 10);

    await corePoolFactory.createPool(apexToken.address, initBlock, 21);
    apexCorePool = (await corePoolFactory.pools(apexToken.address))[0];
  });

  describe("createPool", function () {
    it("create a pool and register", async function () {
      await corePoolFactory.createPool(slpToken.address, initBlock, 79);
      expect(await corePoolFactory.totalWeight()).to.be.equal(100);
    });

    it("revert when create pool with invalid initBlock", async function () {
      await expect(corePoolFactory.createPool(slpToken.address, 0, 79)).to.be.revertedWith("cp: INVALID_INIT_BLOCK");
    });

    it("revert when create pool with invalid poolToken", async function () {
      await expect(corePoolFactory.createPool(constants.ZERO_ADDRESS, 10, 79)).to.be.revertedWith(
        "ERC20Aware: INVALID_POOL_TOKEN"
      );
    });
  });

  describe("registerPool", function () {
    it("register an unregistered corePool", async function () {
      await corePoolFactory.registerPool(mockCorePool.address, 79);
      expect(await corePoolFactory.poolTokenMap(mockCorePool.address)).to.be.equal(slpToken.address);
      expect((await corePoolFactory.pools(slpToken.address))[0]).to.be.equal(mockCorePool.address);
      expect((await corePoolFactory.pools(slpToken.address))[1]).to.be.equal(79);
    });

    it("revert when register a registered corePool", async function () {
      await corePoolFactory.registerPool(mockCorePool.address, 79);
      await expect(corePoolFactory.registerPool(mockCorePool.address, 79)).to.be.revertedWith(
        "cpf.registerPool: POOL_REGISTERED"
      );
    });
  });

  describe("updateApexPerBlock", function () {
    it("update apex rewards per block", async function () {
      await network.provider.send("evm_mine");
      await corePoolFactory.updateApexPerBlock();
      await network.provider.send("evm_mine");
      await corePoolFactory.updateApexPerBlock();
    });

    it("revert when update ApexPerBlock in next block", async function () {
      await corePoolFactory.updateApexPerBlock();
      await expect(corePoolFactory.updateApexPerBlock()).to.be.revertedWith("cpf.updateApexPerBlock: TOO_FREQUENT");
    });
  });

  describe("changePoolWeight", function () {
    it("change pool weight", async function () {
      await corePoolFactory.changePoolWeight(apexCorePool, 89);
      expect(await corePoolFactory.totalWeight()).to.be.equal(89);
    });
  });
});

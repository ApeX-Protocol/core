const { expect } = require("chai");
const { BN, constants, time } = require("@openzeppelin/test-helpers");

describe("stakingPool contract", function () {
  let apexToken;
  let owner;
  let addr1;
  let tx;
  let stakingPoolFactory;
  let slpToken;
  let initBlock = 1;
  let endBlock = 7090016;
  let blocksPerUpdate = 2;
  let apexPerBlock = 100;
  let apexStakingPoolIns;
  let slpStakingPoolIns;
  let lockUntil = 0;
  let invalidLockUntil = 10;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();

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

    await stakingPoolFactory.createPool(apexToken.address, initBlock, 21);
    apexStakingPoolIns = StakingPool.attach((await stakingPoolFactory.pools(apexToken.address))[0]);

    await stakingPoolFactory.createPool(slpToken.address, initBlock, 79);
    slpStakingPoolIns = StakingPool.attach((await stakingPoolFactory.pools(slpToken.address))[0]);

    await apexToken.mint(owner.address, 1000000);
    await apexToken.approve(apexStakingPoolIns.address, 1000000);
  });

  describe("stake", function () {
    it("reverted when stake invalid amount", async function () {
      await expect(apexStakingPoolIns.stake(0, lockUntil)).to.be.revertedWith("cp._stake: INVALID_AMOUNT");
    });

    it("reverted when exceed balance", async function () {
      await expect(apexStakingPoolIns.connect(addr1).stake(10000, lockUntil)).to.be.revertedWith(
        "ERC20: transfer amount exceeds balance"
      );
    });

    it("reverted when exceed balance", async function () {
      await expect(apexStakingPoolIns.stake(10000, invalidLockUntil)).to.be.revertedWith(
        "cp._stake: INVALID_LOCK_INTERVAL"
      );
    });

    it("stake successfully", async function () {
      await apexStakingPoolIns.stake(10000, lockUntil);

      let user = await apexStakingPoolIns.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(10000);
      expect(user.totalWeight.toNumber()).to.equal(10000 * 1e6);
      expect(user.subYieldRewards.toNumber()).to.equal(0);
    });

    it("stake twice, no lock", async function () {
      await apexStakingPoolIns.stake(10000, 0);
      await apexStakingPoolIns.stake(20000, 0);

      let user = await apexStakingPoolIns.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(30020);
      expect(user.totalWeight.toNumber()).to.equal(30040 * 1e6);
      expect(user.subYieldRewards.toNumber()).to.equal(60);
    });

    it("stake twice, with one year lock", async function () {
      let oneYearLockUntil = await oneYearLater();
      await apexStakingPoolIns.stake(10000, oneYearLockUntil);
      let user = await apexStakingPoolIns.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(10000);
      expect(user.totalWeight.toNumber()).to.be.at.least(19999000000);
      expect(user.subYieldRewards.toNumber()).to.equal(0);

      oneYearLockUntil = await oneYearLater();
      await apexStakingPoolIns.stake(20000, oneYearLockUntil);
      user = await apexStakingPoolIns.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(30019);
      expect(user.totalWeight.toNumber()).to.be.at.most(60037990000);
      expect(user.subYieldRewards.toNumber()).to.equal(60);
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

async function currentBlockNumber() {
  return ethers.provider.getBlockNumber();
}

async function oneYearLater() {
  return Math.floor(Date.now() / 1000) + 31536000;
}

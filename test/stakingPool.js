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
  let apexStakingPool;
  let slpStakingPool;
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
    apexStakingPool = StakingPool.attach((await stakingPoolFactory.pools(apexToken.address))[0]);

    await stakingPoolFactory.createPool(slpToken.address, initBlock, 79);
    slpStakingPool = StakingPool.attach((await stakingPoolFactory.pools(slpToken.address))[0]);

    await apexToken.mint(owner.address, 100_0000);
    await apexToken.approve(apexStakingPool.address, 100_0000);
    await apexToken.mint(stakingPoolFactory.address, 100_0000);
    await slpToken.mint(owner.address, 100_0000);
    await slpToken.approve(slpStakingPool.address, 100_0000);
    await stakingPoolFactory.setLockTime(10);
  });

  describe("stake", function () {
    it("reverted when stake invalid amount", async function () {
      await expect(apexStakingPool.stake(0, lockUntil)).to.be.revertedWith("sp.stake: INVALID_AMOUNT");
    });

    it("reverted when exceed balance", async function () {
      await expect(apexStakingPool.connect(addr1).stake(10000, lockUntil)).to.be.revertedWith(
        "ERC20: transfer amount exceeds balance"
      );
    });

    it("reverted when exceed balance", async function () {
      await expect(apexStakingPool.stake(10000, invalidLockUntil)).to.be.revertedWith(
        "sp._stake: INVALID_LOCK_INTERVAL"
      );
    });

    it("stake successfully", async function () {
      await apexStakingPool.stake(10000, lockUntil);

      let user = await apexStakingPool.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(10000);
      expect(user.totalWeight.toNumber()).to.equal(10000 * 1e6);
      expect(user.subYieldRewards.toNumber()).to.equal(0);
    });

    it("stake twice, no lock", async function () {
      await apexStakingPool.stake(10000, 0);
      await apexStakingPool.stake(20000, 0);

      let user = await apexStakingPool.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(30020);
      expect(user.totalWeight.toNumber()).to.equal(30000 * 1e6);
      expect(user.subYieldRewards.toNumber()).to.equal(60);
    });

    it("stake twice, with one year lock", async function () {
      await stakingPoolFactory.setLockTime(15768000);
      let halfYearLockUntil = await halfYearLater();
      await apexStakingPool.stake(10000, halfYearLockUntil);
      let user = await apexStakingPool.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(10000);
      expect(user.totalWeight.toNumber()).to.be.at.least(19990000000);
      expect(user.subYieldRewards.toNumber()).to.equal(0);

      halfYearLockUntil = await halfYearLater();
      await apexStakingPool.stake(20000, halfYearLockUntil);
      user = await apexStakingPool.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(30019);
      expect(user.totalWeight.toNumber()).to.be.at.most(60037990000);
      expect(user.subYieldRewards.toNumber()).to.be.at.most(60);
    });
  });

  describe("unstake", function () {
    beforeEach(async function () {
      await apexToken.approve(apexStakingPool.address, 20000);

      await apexStakingPool.stake(10000, 0);
    });

    it("stake, process reward, unstake, transfer apeX ", async function () {
      await network.provider.send("evm_mine");
      await apexStakingPool.processRewards();
      await network.provider.send("evm_mine");
      await apexStakingPool.batchWithdraw([0], [10000], [], []);
      await expect(apexStakingPool.batchWithdraw([], [], [1], [10000])).to.be.revertedWith(
        "sp.batchWithdraw: YIELD_LOCKED"
      );
      await mineBlocks(100);
      let oldBalance = (await apexToken.balanceOf(owner.address)).toNumber();
      await apexStakingPool.batchWithdraw([], [], [1], [9]);
      let newBalance = (await apexToken.balanceOf(owner.address)).toNumber();
      expect(oldBalance + 9).to.be.equal(newBalance);
    });
  });

  describe("stakeAsPool", function () {
    beforeEach(async function () {
      await slpStakingPool.stake(10000, 0);
    });

    it("unlock too early", async function () {
      await stakingPoolFactory.setLockTime(15768000);
      let halfYearLockUntil = await halfYearLater();
      await slpStakingPool.stake(10000, halfYearLockUntil);
      await expect(slpStakingPool.batchWithdraw([1], [10000], [], [])).to.be.revertedWith(
        "sp.batchWithdraw: DEPOSIT_LOCKED"
      );
    });

    it("stake, process reward to apeXPool, unstake from slpPool, unstake from apeXPool", async function () {
      await network.provider.send("evm_mine");
      await slpStakingPool.processRewards();

      await network.provider.send("evm_mine");
      await slpStakingPool.batchWithdraw([0], [10000], [], []);
      await mineBlocks(100);
      let oldBalance = (await apexToken.balanceOf(owner.address)).toNumber();
      await apexStakingPool.batchWithdraw([], [], [0], [1]);
      let newBalance = (await apexToken.balanceOf(owner.address)).toNumber();
      expect(oldBalance + 1).to.be.equal(newBalance);
    });
  });

  describe("pendingYieldRewards", function () {
    beforeEach(async function () {
      await slpStakingPool.stake(10000, 0);
    });

    it("stake, process reward to apeXPool, unstake from slpPool, unstake from apeXPool", async function () {
      await network.provider.send("evm_mine");
      //linear to apeXPerBlock, 97*79/100
      expect(await slpStakingPool.pendingYieldRewards(owner.address)).to.be.equal(76);
      await slpStakingPool.processRewards();
      expect(await slpStakingPool.pendingYieldRewards(owner.address)).to.be.equal(0);
      await network.provider.send("evm_mine");
      //linear to apeXPerBlock, 94*79/100
      expect(await slpStakingPool.pendingYieldRewards(owner.address)).to.be.equal(74);
    });
  });

  describe("forceWithdraw", function () {
    beforeEach(async function () {
      await slpStakingPool.stake(10000, 0);
      await apexToken.approve(apexStakingPool.address, 20000);

      await stakingPoolFactory.setMinRemainRatioAfterBurn(5000);
      await apexStakingPool.stake(10000, 0);
    });

    it("revert when force withdraw nonReward", async function () {
      await network.provider.send("evm_mine");
      await expect(apexStakingPool.forceWithdraw([0])).to.be.reverted;
    });

    it("revert when force withdraw from slp pool", async function () {
      await network.provider.send("evm_mine");
      await expect(slpStakingPool.forceWithdraw([0])).to.be.revertedWith("sp.forceWithdraw: INVALID_POOL_TOKEN");
    });

    it("revert when force withdraw invalid depositId", async function () {
      await network.provider.send("evm_mine");
      await expect(apexStakingPool.forceWithdraw([1])).to.be.reverted;
    });

    it("can withdraw", async function () {
      await network.provider.send("evm_mine");
      await network.provider.send("evm_mine");
      await network.provider.send("evm_mine");
      let oldBalance = (await apexToken.balanceOf(owner.address)).toNumber();

      await slpStakingPool.processRewards();
      let oldUser = await apexStakingPool.users(owner.address);
      let oldUsersLockingWeight = await apexStakingPool.usersLockingWeight();
      expect(await apexStakingPool.getDepositsLength(owner.address)).to.be.equal(1);
      await apexStakingPool.forceWithdraw([0]);
      expect(await apexStakingPool.getDepositsLength(owner.address)).to.be.equal(1);

      let newBalance = (await apexToken.balanceOf(owner.address)).toNumber();
      expect(newBalance).to.be.equal(oldBalance + 327);
      let newUser = await apexStakingPool.users(owner.address);
      let newUsersLockingWeight = await apexStakingPool.usersLockingWeight();
      expect(oldUser.tokenAmount.toNumber()).to.be.equal(newUser.tokenAmount.toNumber() + 579);
      expect(oldUser.totalWeight.toNumber()).to.be.equal(newUser.totalWeight.toNumber());
      expect(oldUsersLockingWeight.toNumber()).to.be.equal(newUsersLockingWeight.toNumber());
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

async function halfYearLater() {
  return Math.floor(Date.now() / 1000) + 15758000;
}

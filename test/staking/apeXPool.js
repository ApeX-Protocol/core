const { expect } = require("chai");
const { ethers, upgrades, network } = require("hardhat");
const hre = require("hardhat");

describe("stakingPool contract", function () {
  let apeXToken;
  let slpToken;
  let esApeXToken;
  let veApeXToken;
  let stakingPoolFactory;
  let apeXPool;
  let slpStakingPool;
  let stakingPoolTemplate;

  let initTimestamp = 1641781192;
  let endTimestamp = 1673288342;
  let secSpanPerUpdate = 2;
  let apeXPerSec = 100;
  let lockDuration = 9;
  let invalidLockDuration = 100000000000;
  let lockTime = 10;
  let halfYearLockUntil = 26 * 7 * 24 * 3600;

  let owner;
  let addr1;
  let addr2;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    const MockToken = await ethers.getContractFactory("MockToken");
    const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
    const ApeXPool = await ethers.getContractFactory("ApeXPool");
    const MockEsApeX = await ethers.getContractFactory("MockEsApeX");
    const VeAPEX = await ethers.getContractFactory("VeAPEX");
    const StakingPoolTemplate = await ethers.getContractFactory("StakingPool");

    stakingPoolTemplate = await StakingPoolTemplate.deploy();
    apeXToken = await MockToken.deploy("apeX token", "at");
    slpToken = await MockToken.deploy("slp token", "slp");
    stakingPoolFactory = await upgrades.deployProxy(StakingPoolFactory, [
      apeXToken.address,
      addr1.address,
      apeXPerSec,
      secSpanPerUpdate,
      initTimestamp,
      endTimestamp,
      lockTime,
    ]);
    apeXPool = await ApeXPool.deploy(stakingPoolFactory.address, apeXToken.address);
    esApeXToken = await MockEsApeX.deploy(stakingPoolFactory.address);
    veApeXToken = await VeAPEX.deploy(stakingPoolFactory.address);

    await stakingPoolFactory.setRemainForOtherVest(50);
    await stakingPoolFactory.setEsApeX(esApeXToken.address);
    await stakingPoolFactory.setVeApeX(veApeXToken.address);
    await stakingPoolFactory.setStakingPoolTemplate(stakingPoolTemplate.address);

    await stakingPoolFactory.registerApeXPool(apeXPool.address, 21);
    await stakingPoolFactory.createPool(slpToken.address, 79);
    slpStakingPool = StakingPoolTemplate.attach(await stakingPoolFactory.tokenPoolMap(slpToken.address));

    await apeXToken.mint(owner.address, 100_0000);
    await apeXToken.approve(apeXPool.address, 100_0000);
    await apeXToken.mint(stakingPoolFactory.address, 100_0000_0000);
    await slpToken.mint(owner.address, 100_0000);
    await slpToken.approve(slpStakingPool.address, 100_0000);

    await esApeXToken.setFactory(owner.address);
    await esApeXToken.mint(owner.address, 100_0000);
    await esApeXToken.mint(addr1.address, 100_0000);
    await esApeXToken.approve(stakingPoolFactory.address, 100_0000);
  });

  describe("stake", function () {
    it("reverted when stake invalid amount", async function () {
      await expect(apeXPool.stake(0, lockDuration)).to.be.revertedWith("sp.stake: INVALID_AMOUNT");
    });

    it("reverted when invalid lock interval", async function () {
      await expect(apeXPool.stake(10000, invalidLockDuration)).to.be.revertedWith("sp._stake: INVALID_LOCK_INTERVAL");
    });

    it("reverted when exceed balance", async function () {
      await expect(apeXPool.connect(addr1).stake(10000, lockDuration)).to.be.revertedWith(
        "ERC20: transfer amount exceeds balance"
      );
    });

    it("stake successfully", async function () {
      let user = await apeXPool.users(owner.address);
      let oldPoolTokenBal = await apeXToken.balanceOf(owner.address);
      console.log("11111 ", user.totalWeight.toNumber());
      await apeXPool.stake(10000, lockDuration);
      let newPoolTokenBal = await apeXToken.balanceOf(owner.address);
      expect(oldPoolTokenBal - newPoolTokenBal).to.be.equal(10000);

      user = await apeXPool.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(10000);
      expect(user.totalWeight.toNumber()).to.equal(19000 * 1e6);
      expect(user.subYieldRewards.toNumber()).to.equal(0);
      expect(await apeXPool.getDepositsLength(owner.address)).to.equal(1);
    });

    it("stake twice, no lock", async function () {
      await apeXPool.stake(10000, 0);
      await sleep(1000);
      await apeXPool.stake(20000, 0);

      let user = await apeXPool.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(30000);
      expect(user.totalWeight.toNumber()).to.equal(30000 * 1e6);
      expect(user.subYieldRewards.toNumber()).to.greaterThan(0);
      expect(await apeXPool.getDepositsLength(owner.address)).to.equal(2);
      expect((await esApeXToken.balanceOf(owner.address)).toNumber()).to.greaterThan(0);
    });

    it("stake twice, with one year lock", async function () {
      await stakingPoolFactory.setLockTime(15768000);
      await apeXPool.stake(10000, halfYearLockUntil);
      let user = await apeXPool.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(10000);
      expect(user.totalWeight.toNumber()).to.be.at.least(19000000000);
      expect(user.subYieldRewards.toNumber()).to.equal(0);

      await apeXPool.stake(20000, halfYearLockUntil);
      user = await apeXPool.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(30000);
      expect(user.totalWeight.toNumber()).to.be.at.most(100000000000);
      expect(user.subYieldRewards.toNumber()).to.be.at.most(60);
    });
  });

  describe("stakeEsApeX", function () {
    it("stake esApeX", async function () {
      await stakingPoolFactory.setLockTime(15768000);
      await apeXPool.stakeEsApeX(10000, halfYearLockUntil);
    });

    it("revert when user stake while didn't approve", async function () {
      await stakingPoolFactory.setLockTime(15768000);
      await expect(apeXPool.connect(addr2).stakeEsApeX(10000, halfYearLockUntil)).to.be.revertedWith(
        "esApeX: transfer amount exceeds allowance"
      );
    });

    it("revert when user stake while didn't have balance", async function () {
      await stakingPoolFactory.setLockTime(15768000);
      await esApeXToken.connect(addr2).approve(stakingPoolFactory.address, 10000);
      await expect(apeXPool.connect(addr2).stakeEsApeX(10000, halfYearLockUntil)).to.be.revertedWith(
        "esApeX: transfer amount exceeds balance"
      );
    });
  });

  describe("unstake", function () {
    beforeEach(async function () {
      await apeXToken.approve(apeXPool.address, 20000);
      await apeXPool.stake(10000, 0);
    });

    it("stake, process reward, unstake, transfer apeX", async function () {
      await network.provider.send("evm_mine");
      await apeXPool.processRewards();
      let amount = (await esApeXToken.balanceOf(owner.address)).toNumber();
      await esApeXToken.approve(stakingPoolFactory.address, 1000000000000);

      await apeXPool.vest(amount);
      await network.provider.send("evm_mine");
      await apeXPool.batchWithdraw([0], [10000], [], [], [], []);
      await expect(apeXPool.batchWithdraw([], [], [0], [100], [], [])).to.be.revertedWith(
        "sp.batchWithdraw: YIELD_LOCKED"
      );
      await mineBlocks(100);
      await expect(apeXPool.batchWithdraw([], [], [0], [amount + 1], [], [])).to.be.revertedWith(
        "sp.batchWithdraw: EXCEED_YIELD_STAKED"
      );
      let oldBalance = (await apeXToken.balanceOf(owner.address)).toNumber();
      await apeXPool.batchWithdraw([], [], [0], [amount], [], []);
      let newBalance = (await apeXToken.balanceOf(owner.address)).toNumber();
      expect(oldBalance + amount).to.be.equal(newBalance);
    });
  });

  describe("batchWithdraw", function () {
    beforeEach(async function () {
      await apeXPool.stake(10000, 0);
      await apeXPool.processRewards();
      await esApeXToken.approve(stakingPoolFactory.address, 10000000);
      await stakingPoolFactory.setLockTime(15758000);
    });

    it("batchWithdraw unlocked deposit", async function () {
      let oldStakeInfo = await apeXPool.getStakeInfo(owner.address);
      await apeXPool.batchWithdraw([0], [10000], [], [], [], []);
      let newStakeInfo = await apeXPool.getStakeInfo(owner.address);
      expect(oldStakeInfo.totalWeight.toNumber()).to.greaterThan(newStakeInfo.totalWeight.toNumber());
      expect(oldStakeInfo.tokenAmount.toNumber()).to.greaterThan(newStakeInfo.tokenAmount.toNumber());
    });

    it("revert when withdraw amount bigger than expected", async function () {
      await expect(apeXPool.batchWithdraw([0], [10001], [], [], [], [])).to.be.revertedWith(
        "sp.batchWithdraw: EXCEED_DEPOSIT_STAKED"
      );
    });

    it("batchWithdraw unlocked esDeposit", async function () {
      await apeXPool.stakeEsApeX(10, 0);
      await apeXPool.batchWithdraw([], [], [], [], [0], [10]);
    });

    it("batchWithdraw locked deposit", async function () {
      await apeXPool.stake(20000, halfYearLockUntil);
      await expect(apeXPool.batchWithdraw([1], [10000], [], [], [], [])).to.be.revertedWith(
        "sp.batchWithdraw: DEPOSIT_LOCKED"
      );
    });

    it("batchWithdraw locked esDeposit", async function () {
      await apeXPool.stakeEsApeX(10, halfYearLockUntil);
      await expect(apeXPool.batchWithdraw([], [], [], [], [0], [10])).to.be.revertedWith(
        "sp.batchWithdraw: ESDEPOSIT_LOCKED"
      );
    });

    it("revert when different length", async function () {
      await expect(apeXPool.batchWithdraw([10], [], [], [], [], [])).to.be.revertedWith(
        "sp.batchWithdraw: INVALID_DEPOSITS_AMOUNTS"
      );
    });
  });

  describe("updateStakeLock", function () {
    beforeEach(async function () {
      await stakingPoolFactory.setLockTime(15768000);
      await apeXPool.stake(10000, lockDuration);
      await apeXPool.stakeEsApeX(10000, lockDuration);
    });

    it("update stake lock to half year later", async function () {
      let oneMLater = 30 * 24 * 3600;
      let oldBalance = (await veApeXToken.balanceOf(owner.address)).toNumber();
      let oldLockWeight = (await apeXPool.usersLockingWeight()).toNumber();

      await apeXPool.updateStakeLock(0, oneMLater, false);
      let newBalance = (await veApeXToken.balanceOf(owner.address)).toNumber();
      let newLockWeight = (await apeXPool.usersLockingWeight()).toNumber();
      expect(newBalance).to.greaterThan(oldBalance);
      expect(newLockWeight).to.greaterThan(oldLockWeight);
    });

    it("reverted when stake invalid lockDuration", async function () {
      await expect(apeXPool.updateStakeLock(0, 0, false)).to.be.revertedWith("sp.updateStakeLock: INVALID_LOCK_DURATION");
    });

    describe("existStake", function () {
      let oneMLater;
      beforeEach(async function () {
        await stakingPoolFactory.setLockTime(15768000);
        await apeXPool.stake(10000, halfYearLockUntil);
        oneMLater = 30 * 24 * 3600;
      });

      it("reverted when update unlocked stake to time early than previous lock", async function () {
        await expect(apeXPool.updateStakeLock(1, oneMLater, false)).to.be.revertedWith(
          "sp.updateStakeLock: INVALID_NEW_LOCK"
        );
      });
    });

    it("reverted when exceed balance", async function () {
      await expect(apeXPool.connect(addr1).stake(10000, lockDuration)).to.be.revertedWith(
        "ERC20: transfer amount exceeds balance"
      );
    });
  });

  describe("vest", function () {
    beforeEach(async function () {
      await slpStakingPool.stake(10000, 0);
    });

    it("stake, process reward to apeXPool, unstake from slpPool, unstake from apeXPool", async function () {
      await esApeXToken.mint(owner.address, 10000);
      await esApeXToken.approve(stakingPoolFactory.address, 10000000);

      let oldAmount = (await esApeXToken.balanceOf(owner.address)).toNumber();
      let oldYieldsLength = (await apeXPool.getYieldsLength(owner.address)).toNumber();
      await apeXPool.vest(oldAmount);

      let newAmount = (await esApeXToken.balanceOf(owner.address)).toNumber();
      let newYieldsLength = (await apeXPool.getYieldsLength(owner.address)).toNumber();

      expect(oldAmount).to.greaterThan(newAmount);
      expect(newYieldsLength).to.greaterThan(oldYieldsLength);
    });

    it("stake, process reward to apeXPool, unstake from slpPool, unstake from apeXPool", async function () {
      await network.provider.send("evm_mine");
      await slpStakingPool.processRewards();
      await esApeXToken.approve(stakingPoolFactory.address, 10000000);

      let amount = (await esApeXToken.balanceOf(owner.address)).toNumber();
      await apeXPool.vest(amount);
      await network.provider.send("evm_mine");
      await slpStakingPool.batchWithdraw([0], [10000]);
      await mineBlocks(100);
      let oldBalance = (await apeXToken.balanceOf(owner.address)).toNumber();
      await apeXPool.batchWithdraw([], [], [0], [amount], [], []);
      let newBalance = (await apeXToken.balanceOf(owner.address)).toNumber();
      expect(oldBalance + amount).to.be.equal(newBalance);
    });
  });

  describe("processRewards", function () {
    beforeEach(async function () {
      await slpStakingPool.stake(10000, 0);
    });

    it("pendingYieldRewards and process rewards", async function () {
      await network.provider.send("evm_mine");
      await slpStakingPool.processRewards();
      expect(await slpStakingPool.pendingYieldRewards(owner.address)).to.be.equal(0);
      await network.provider.send("evm_mine");
      //linear to apeXPerSec, 94*79/100
      expect(await slpStakingPool.pendingYieldRewards(owner.address)).to.be.equal(74);
    });
  });

  describe("pendingYieldRewards", function () {
    beforeEach(async function () {
      await slpStakingPool.stake(10000, 0);
    });

    it("query pendingYieldRewards", async function () {
      await network.provider.send("evm_mine");
      //linear to apeXPerSec, 97*79/100
      expect(await slpStakingPool.pendingYieldRewards(owner.address)).to.be.equal(76);
    });
  });

  describe("syncWeightPrice", function () {
    beforeEach(async function () {
      await slpStakingPool.stake(10000, 0);
    });

    it("query pendingYieldRewards", async function () {
      let oldPricePerWeight = (await slpStakingPool.yieldRewardsPerWeight()).toNumber();

      let result = await stakingPoolFactory.poolWeightMap(slpStakingPool.address);
      let oldLastYieldPriceOfWeight = result.lastYieldPriceOfWeight.toNumber();

      await network.provider.send("evm_mine");
      await slpStakingPool.syncWeightPrice();
      let newPricePerWeight = (await slpStakingPool.yieldRewardsPerWeight()).toNumber();

      result = await stakingPoolFactory.poolWeightMap(slpStakingPool.address);
      let newLastYieldPriceOfWeight = result.lastYieldPriceOfWeight.toNumber();

      expect(newPricePerWeight).to.greaterThan(oldPricePerWeight);
      expect(newLastYieldPriceOfWeight).to.greaterThan(oldLastYieldPriceOfWeight);
    });
  });

  describe("forceWithdraw", function () {
    beforeEach(async function () {
      await slpStakingPool.stake(10000, 0);
      await apeXToken.approve(apeXPool.address, 20000);

      await stakingPoolFactory.setMinRemainRatioAfterBurn(5000);
      await stakingPoolFactory.setRemainForOtherVest(50);
      await apeXPool.stake(10000, 0);
    });

    it("revert when force withdraw nonReward", async function () {
      await network.provider.send("evm_mine");
      await expect(apeXPool.forceWithdraw([0])).to.be.reverted;
    });

    it("revert when force withdraw invalid depositId", async function () {
      await network.provider.send("evm_mine");
      await expect(apeXPool.forceWithdraw([1])).to.be.reverted;
    });

    it("can withdraw", async function () {
      await network.provider.send("evm_mine");
      await network.provider.send("evm_mine");
      await network.provider.send("evm_mine");
      let ownerOldBalance = (await apeXToken.balanceOf(owner.address)).toNumber();
      let treasuryOldBalance = (await apeXToken.balanceOf(addr1.address)).toNumber();

      await slpStakingPool.processRewards();
      await esApeXToken.approve(stakingPoolFactory.address, 10000000);
      await apeXPool.vest(575);

      let oldUser = await apeXPool.users(owner.address);
      let oldUsersLockingWeight = await apeXPool.usersLockingWeight();
      expect(await apeXPool.getDepositsLength(owner.address)).to.be.equal(1);
      expect(await apeXPool.getYieldsLength(owner.address)).to.be.equal(1);
      await apeXPool.forceWithdraw([0]);
      expect(await apeXPool.getDepositsLength(owner.address)).to.be.equal(1);
      expect(await apeXPool.getYieldsLength(owner.address)).to.be.equal(1);

      let newBalance = (await apeXToken.balanceOf(owner.address)).toNumber();
      let treasuryNewBalance = (await apeXToken.balanceOf(addr1.address)).toNumber();
      expect(newBalance).to.greaterThanOrEqual(ownerOldBalance + 300);
      expect(treasuryNewBalance).to.greaterThanOrEqual(treasuryOldBalance + 130);
      let newUser = await apeXPool.users(owner.address);
      let newUsersLockingWeight = await apeXPool.usersLockingWeight();
      expect(oldUser.tokenAmount.toNumber()).to.be.equal(newUser.tokenAmount.toNumber() + 575);
      expect(oldUser.totalWeight.toNumber()).to.be.equal(newUser.totalWeight.toNumber());
      expect(oldUsersLockingWeight.toNumber()).to.be.equal(newUsersLockingWeight.toNumber());
    });
  });

  describe("veApeXTokenBalance", function () {
    beforeEach(async function () {
      await apeXPool.stake(10000, 0);
      await apeXPool.processRewards();
      await esApeXToken.approve(stakingPoolFactory.address, 10000000);
    });

    it("vest dont change veApeXTokenBalance", async function () {
      let veApeXTokenBalance = await veApeXToken.balanceOf(owner.address);
      expect(veApeXTokenBalance.toNumber()).to.be.equal(10000);

      await apeXPool.vest(5);
      veApeXTokenBalance = await veApeXToken.balanceOf(owner.address);
      expect(veApeXTokenBalance.toNumber()).to.be.equal(10000);
    });

    it("stake, stakeEsApeX, batchWithdraw change veApeXTokenBalance", async function () {
      let amount = (await esApeXToken.balanceOf(owner.address)).toNumber();
      expect(amount).to.greaterThan(5);
      let veApeXTokenBalance = await veApeXToken.balanceOf(owner.address);
      expect(veApeXTokenBalance.toNumber()).to.be.equal(10000);

      await stakingPoolFactory.setLockTime(1);
      await apeXPool.stakeEsApeX(5, 0);
      veApeXTokenBalance = await veApeXToken.balanceOf(owner.address);
      expect(veApeXTokenBalance.toNumber()).to.be.equal(10005);

      await mineBlocks(100);
      await apeXPool.batchWithdraw([], [], [], [], [0], [5]);
      veApeXTokenBalance = await veApeXToken.balanceOf(owner.address);
      expect(veApeXTokenBalance.toNumber()).to.be.equal(10000);

      await apeXPool.batchWithdraw([0], [10000], [], [], [], []);
      veApeXTokenBalance = await veApeXToken.balanceOf(owner.address);
      expect(veApeXTokenBalance.toNumber()).to.be.equal(0);
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

async function oneMonthLater() {
  return Math.floor(Date.now() / 1000) + 2626000;
}

function sleep(ms = 10000) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

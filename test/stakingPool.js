const { expect } = require("chai");
const { BN, constants, time } = require("@openzeppelin/test-helpers");

describe("stakingPool contract", function () {
  let apexToken;
  let slpToken;
  let esApeXToken;
  let veApeXToken;
  let stakingPoolFactory;
  let apexPool;
  let slpStakingPool;
  let stakingPoolTemplate;

  let initTimestamp = 1641781192;
  let endTimestamp = 1673288342;
  let secSpanPerUpdate = 2;
  let apeXPerSec = 100;
  let lockUntil = 0;
  let invalidLockUntil = 10;
  let lockTime = 10;

  let owner;
  let addr1;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();

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
    await stakingPoolFactory.createPool(slpToken.address, initTimestamp, 79);
    slpStakingPool = StakingPoolTemplate.attach((await stakingPoolFactory.pools(slpToken.address))[0]);

    await apexToken.mint(owner.address, 100_0000);
    await apexToken.approve(apexPool.address, 100_0000);
    await apexToken.mint(stakingPoolFactory.address, 100_0000);
    await slpToken.mint(owner.address, 100_0000);
    await slpToken.approve(slpStakingPool.address, 100_0000);
  });

  describe("stake", function () {
    it("reverted when stake invalid amount", async function () {
      await expect(apexPool.stake(0, lockUntil)).to.be.revertedWith("sp.stake: INVALID_AMOUNT");
    });

    it("reverted when exceed balance", async function () {
      await expect(apexPool.connect(addr1).stake(10000, lockUntil)).to.be.revertedWith(
        "ERC20: transfer amount exceeds balance"
      );
    });

    it("reverted when invalid lock interval", async function () {
      await expect(apexPool.stake(10000, invalidLockUntil)).to.be.revertedWith("sp._stake: INVALID_LOCK_INTERVAL");
    });

    it("stake successfully", async function () {
      await apexPool.stake(10000, lockUntil);

      let user = await apexPool.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(10000);
      expect(user.totalWeight.toNumber()).to.equal(10000 * 1e6);
      expect(user.subYieldRewards.toNumber()).to.equal(0);
    });

    it("stake twice, no lock", async function () {
      await apexPool.stake(10000, 0);
      await sleep(1000);
      await apexPool.stake(20000, 0);

      let user = await apexPool.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(30000);
      expect(user.totalWeight.toNumber()).to.equal(30000 * 1e6);
      expect(user.subYieldRewards.toNumber()).to.greaterThan(0);
      expect((await esApeXToken.balanceOf(owner.address)).toNumber()).to.greaterThan(0);
    });

    it("stake twice, with one year lock", async function () {
      await stakingPoolFactory.setLockTime(15768000);
      let halfYearLockUntil = await halfYearLater();
      await apexPool.stake(10000, halfYearLockUntil);
      let user = await apexPool.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(10000);
      expect(user.totalWeight.toNumber()).to.be.at.least(19000000000);
      expect(user.subYieldRewards.toNumber()).to.equal(0);

      halfYearLockUntil = await halfYearLater();
      await apexPool.stake(20000, halfYearLockUntil);
      user = await apexPool.users(owner.address);
      expect(user.tokenAmount.toNumber()).to.equal(30000);
      expect(user.totalWeight.toNumber()).to.be.at.most(100000000000);
      expect(user.subYieldRewards.toNumber()).to.be.at.most(60);
    });
  });

  describe("unstake", function () {
    beforeEach(async function () {
      await apexToken.approve(apexPool.address, 20000);

      await apexPool.stake(10000, 0);
    });

    it("stake, process reward, unstake, transfer apeX ", async function () {
      await network.provider.send("evm_mine");
      await apexPool.processRewards();
      let amount = (await esApeXToken.balanceOf(owner.address)).toNumber();
      await esApeXToken.approve(stakingPoolFactory.address, 10000000);

      await apexPool.vest(amount);
      await network.provider.send("evm_mine");
      await apexPool.batchWithdraw([0], [10000], [], [], [], []);
      await expect(apexPool.batchWithdraw([], [], [0], [100], [], [])).to.be.revertedWith(
        "sp.batchWithdraw: YIELD_LOCKED"
      );
      await mineBlocks(100);
      await expect(apexPool.batchWithdraw([], [], [0], [amount + 1], [], [])).to.be.revertedWith(
        "sp.batchWithdraw: EXCEED_YIELD_STAKED"
      );
      let oldBalance = (await apexToken.balanceOf(owner.address)).toNumber();
      await apexPool.batchWithdraw([], [], [0], [amount], [], []);
      let newBalance = (await apexToken.balanceOf(owner.address)).toNumber();
      expect(oldBalance + amount).to.be.equal(newBalance);
    });
  });

  describe("batchWithdraw", function () {
    beforeEach(async function () {
      await apexPool.stake(10000, 0);
      await apexPool.processRewards();
      await esApeXToken.approve(stakingPoolFactory.address, 10000000);
      await stakingPoolFactory.setLockTime(15758000);
    });

    it("batchWithdraw unlocked deposit", async function () {
      await apexPool.batchWithdraw([0], [10000], [], [], [], []);
    });

    it("batchWithdraw unlocked esDeposit", async function () {
      await apexPool.stakeEsApeX(10, 0);
      await apexPool.batchWithdraw([], [], [], [], [0], [10]);
    });

    it("batchWithdraw locked deposit", async function () {
      await apexPool.stake(20000, await halfYearLater());
      await expect(apexPool.batchWithdraw([1], [10000], [], [], [], [])).to.be.revertedWith(
        "sp.batchWithdraw: DEPOSIT_LOCKED"
      );
    });

    it("batchWithdraw locked esDeposit", async function () {
      await apexPool.stakeEsApeX(10, await halfYearLater());
      await expect(apexPool.batchWithdraw([], [], [], [], [0], [10])).to.be.revertedWith(
        "sp.batchWithdraw: ESDEPOSIT_LOCKED"
      );
    });
  });

  describe("vest", function () {
    beforeEach(async function () {
      await slpStakingPool.stake(10000, 0);
    });

    it("unlock too early", async function () {
      await stakingPoolFactory.setLockTime(15768000);
      let halfYearLockUntil = await halfYearLater();
      await slpStakingPool.stake(10000, halfYearLockUntil);
      await expect(slpStakingPool.batchWithdraw([1], [10000])).to.be.revertedWith("sp.batchWithdraw: DEPOSIT_LOCKED");
    });

    it("stake, process reward to apeXPool, unstake from slpPool, unstake from apeXPool", async function () {
      await network.provider.send("evm_mine");
      await slpStakingPool.processRewards();
      await esApeXToken.approve(stakingPoolFactory.address, 10000000);

      let amount = (await esApeXToken.balanceOf(owner.address)).toNumber();
      await apexPool.vest(amount);
      await network.provider.send("evm_mine");
      await slpStakingPool.batchWithdraw([0], [10000]);
      await mineBlocks(100);
      let oldBalance = (await apexToken.balanceOf(owner.address)).toNumber();
      await apexPool.batchWithdraw([], [], [0], [amount], [], []);
      let newBalance = (await apexToken.balanceOf(owner.address)).toNumber();
      expect(oldBalance + amount).to.be.equal(newBalance);
    });
  });

  describe("pendingYieldRewards", function () {
    beforeEach(async function () {
      await slpStakingPool.stake(10000, 0);
    });

    it("stake, process reward to apeXPool, unstake from slpPool, unstake from apeXPool", async function () {
      await network.provider.send("evm_mine");
      //linear to apeXPerSec, 97*79/100
      expect(await slpStakingPool.pendingYieldRewards(owner.address)).to.be.equal(76);
      await slpStakingPool.processRewards();
      expect(await slpStakingPool.pendingYieldRewards(owner.address)).to.be.equal(0);
      await network.provider.send("evm_mine");
      //linear to apeXPerSec, 94*79/100
      expect(await slpStakingPool.pendingYieldRewards(owner.address)).to.be.equal(74);
    });
  });

  describe("forceWithdraw", function () {
    beforeEach(async function () {
      await slpStakingPool.stake(10000, 0);
      await apexToken.approve(apexPool.address, 20000);

      await stakingPoolFactory.setMinRemainRatioAfterBurn(5000);
      await stakingPoolFactory.setRemainForOtherVest(50);
      await apexPool.stake(10000, 0);
    });

    it("revert when force withdraw nonReward", async function () {
      await network.provider.send("evm_mine");
      await expect(apexPool.forceWithdraw([0])).to.be.reverted;
    });

    it("revert when force withdraw invalid depositId", async function () {
      await network.provider.send("evm_mine");
      await expect(apexPool.forceWithdraw([1])).to.be.reverted;
    });

    it("can withdraw", async function () {
      await network.provider.send("evm_mine");
      await network.provider.send("evm_mine");
      await network.provider.send("evm_mine");
      let oldBalance = (await apexToken.balanceOf(owner.address)).toNumber();
      let treasuryOldBalance = (await apexToken.balanceOf(addr1.address)).toNumber();

      await slpStakingPool.processRewards();
      await esApeXToken.approve(stakingPoolFactory.address, 10000000);
      let amount = (await esApeXToken.balanceOf(owner.address)).toNumber();
      await apexPool.vest(amount);

      let oldUser = await apexPool.users(owner.address);
      let oldUsersLockingWeight = await apexPool.usersLockingWeight();
      expect(await apexPool.getDepositsLength(owner.address)).to.be.equal(1);
      expect(await apexPool.getYieldsLength(owner.address)).to.be.equal(1);
      await apexPool.forceWithdraw([0]);
      expect(await apexPool.getDepositsLength(owner.address)).to.be.equal(1);
      expect(await apexPool.getYieldsLength(owner.address)).to.be.equal(1);

      let newBalance = (await apexToken.balanceOf(owner.address)).toNumber();
      let treasuryNewBalance = (await apexToken.balanceOf(addr1.address)).toNumber();
      expect(newBalance).to.greaterThanOrEqual(oldBalance + 300);
      expect(treasuryNewBalance).to.greaterThanOrEqual(treasuryOldBalance + 130);
      let newUser = await apexPool.users(owner.address);
      let newUsersLockingWeight = await apexPool.usersLockingWeight();
      expect(oldUser.tokenAmount.toNumber()).to.be.equal(newUser.tokenAmount.toNumber() + 575);
      expect(oldUser.totalWeight.toNumber()).to.be.equal(newUser.totalWeight.toNumber());
      expect(oldUsersLockingWeight.toNumber()).to.be.equal(newUsersLockingWeight.toNumber());
    });
  });

  describe("veApeXTokenBalance", function () {
    beforeEach(async function () {
      await apexPool.stake(10000, 0);
      await apexPool.processRewards();
      await esApeXToken.approve(stakingPoolFactory.address, 10000000);
    });

    it("vest dont change veApeXTokenBalance", async function () {
      let veApeXTokenBalance = await veApeXToken.balanceOf(owner.address);
      expect(veApeXTokenBalance.toNumber()).to.be.equal(10000);

      await apexPool.vest(5);
      veApeXTokenBalance = await veApeXToken.balanceOf(owner.address);
      expect(veApeXTokenBalance.toNumber()).to.be.equal(10000);
    });

    it("stake, stakeEsApeX, batchWithdraw change veApeXTokenBalance", async function () {
      let amount = (await esApeXToken.balanceOf(owner.address)).toNumber();
      expect(amount).to.greaterThan(5);
      let veApeXTokenBalance = await veApeXToken.balanceOf(owner.address);
      expect(veApeXTokenBalance.toNumber()).to.be.equal(10000);

      await stakingPoolFactory.setLockTime(1);
      await apexPool.stakeEsApeX(5, 0);
      veApeXTokenBalance = await veApeXToken.balanceOf(owner.address);
      expect(veApeXTokenBalance.toNumber()).to.be.equal(10005);

      await mineBlocks(100);
      await apexPool.batchWithdraw([], [], [], [], [0], [5]);
      veApeXTokenBalance = await veApeXToken.balanceOf(owner.address);
      expect(veApeXTokenBalance.toNumber()).to.be.equal(10000);

      await apexPool.batchWithdraw([0], [10000], [], [], [], []);
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

function sleep(ms = 10000) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

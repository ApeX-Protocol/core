const { expect } = require("chai");
const { BN, constants } = require("@openzeppelin/test-helpers");
const { ethers, upgrades, network } = require("hardhat");

describe("stakingPoolFactory contract", function () {
  let apexToken;
  let slpToken;
  let esApeXToken;
  let veApeXToken;
  let stakingPoolTemplate;
  let apexPool;
  let anotherApexPool;
  let fakeApexPool;
  let stakingPoolFactory;

  let initTimestamp = 1641781192; //10 January 2022 10:19:52
  let endTimestamp = 1673288342; //10 January 2023 02:19:02
  let secSpanPerUpdate = 2;
  let apeXPerSec = 100;
  let lockTime = 3600 * 24 * 180; //half year

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
    apexPool = await ApeXPool.deploy(stakingPoolFactory.address, apexToken.address);
    fakeApexPool = await ApeXPool.deploy(stakingPoolFactory.address, apexToken.address);
    fakeApexPoolWithSlpToken = await ApeXPool.deploy(stakingPoolFactory.address, slpToken.address);
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

  describe("initialize", function () {
    it("reverted when initialize factory again", async function () {
      await expect(
        stakingPoolFactory.initialize(
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          apeXPerSec,
          secSpanPerUpdate,
          initTimestamp,
          endTimestamp,
          lockTime
        )
      ).to.be.revertedWith("Initializable: contract is already initialized");
    });
  });

  describe("setStakingPoolTemplate", function () {
    it("can set not-null address", async function () {
      await stakingPoolFactory.setStakingPoolTemplate(addr1.address);
      expect(await stakingPoolFactory.stakingPoolTemplate()).to.be.equal(addr1.address);
    });

    it("reverted when set by unauthorized account", async function () {
      await expect(
        stakingPoolFactory.connect(addr1).setStakingPoolTemplate(ethers.constants.AddressZero)
      ).to.be.revertedWith("Ownable: REQUIRE_OWNER");
    });

    it("revert when set null address", async function () {
      await expect(stakingPoolFactory.setStakingPoolTemplate(ethers.constants.AddressZero)).to.be.reverted;
    });

    describe("after set new pool template", function () {
      let alpToken;
      let StakingPoolTemplate;
      let NewStakingPoolTemplate;
      let MockToken;
      beforeEach(async function () {
        StakingPoolTemplate = await ethers.getContractFactory("StakingPool");
        NewStakingPoolTemplate = await ethers.getContractFactory("NewPoolTemplate");
        MockToken = await ethers.getContractFactory("MockToken");

        alpToken = await MockToken.deploy("alp token", "alp");
        newStakingPoolTemplate = await NewStakingPoolTemplate.deploy();

        await stakingPoolFactory.createPool(slpToken.address, 79);
        await stakingPoolFactory.setStakingPoolTemplate(newStakingPoolTemplate.address);
        await stakingPoolFactory.createPool(alpToken.address, 1000);
      });

      it("old created pool use old pool template", async function () {
        slpPoolAddress = await stakingPoolFactory.tokenPoolMap(slpToken.address);
        slpPool = StakingPoolTemplate.attach(slpPoolAddress);
        expect((await slpPool.getDepositsLength(owner.address)).toNumber()).to.be.equal(0);
      });

      it("new created pool use new pool template", async function () {
        alpPoolAddress = await stakingPoolFactory.tokenPoolMap(alpToken.address);
        alpPool = NewStakingPoolTemplate.attach(alpPoolAddress);
        expect((await alpPool.getDepositsLength(owner.address)).toNumber()).to.be.equal(10000);
      });
    });
  });

  describe("createPool", function () {
    it("create a pool and register", async function () {
      await stakingPoolFactory.createPool(slpToken.address, 79);
      expect(await stakingPoolFactory.totalWeight()).to.be.equal(100);
    });

    it("reverted when create by unauthorized account", async function () {
      await expect(stakingPoolFactory.connect(addr1).createPool(slpToken.address, 79)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });

    it("revert when create pool with invalid poolToken", async function () {
      await expect(stakingPoolFactory.createPool(constants.ZERO_ADDRESS, 79)).to.be.revertedWith(
        "spf.createPool: ZERO_ADDRESS"
      );
    });

    it("revert when create pool with apeX", async function () {
      await expect(stakingPoolFactory.createPool(apexToken.address, 79)).to.be.revertedWith(
        "spf.createPool: CANT_APEX"
      );
    });

    it("revert when create pool while not set template", async function () {
      const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
      let spf = await upgrades.deployProxy(StakingPoolFactory, [
        addr1.address,
        addr1.address,
        apeXPerSec,
        secSpanPerUpdate,
        initTimestamp,
        endTimestamp,
        lockTime,
      ]);

      await expect(spf.createPool(apexToken.address, 79)).to.be.revertedWith("spf.createPool: ZERO_TEMPLATE");
    });

    it("revert when initialize a pool again", async function () {
      const StakingPoolTemplate = await ethers.getContractFactory("StakingPool");
      await stakingPoolFactory.createPool(slpToken.address, 79);
      slpPoolAddress = await stakingPoolFactory.tokenPoolMap(slpToken.address);
      slpPool = StakingPoolTemplate.attach(slpPoolAddress);
      await expect(slpPool.initialize(stakingPoolFactory.address, slpToken.address)).to.be.revertedWith(
        "Initializable: contract is already initialized"
      );
    });

    it("revert when create pool with exist poolToken", async function () {
      await stakingPoolFactory.createPool(slpToken.address, 79);
      await expect(stakingPoolFactory.createPool(slpToken.address, 79)).to.be.revertedWith(
        "spf.registerPool: POOL_TOKEN_REGISTERED"
      );
    });

    describe("create an unregistered pool again", function () {
      beforeEach(async function () {
        await stakingPoolFactory.createPool(slpToken.address, 79);
      });

      it("can create pool again", async function () {
        let slpPoolAddress = await stakingPoolFactory.tokenPoolMap(slpToken.address);
        await stakingPoolFactory.unregisterPool(slpPoolAddress);

        await stakingPoolFactory.createPool(slpToken.address, 69);
        expect(await stakingPoolFactory.totalWeight()).to.be.equal(90);
      });
    });

    describe("settle the former pools when register new pool or unregister old pool", function () {
      let pendingReward;
      let oldPriceOfWeight;
      let newPriceOfWeight;
      beforeEach(async function () {
        pendingReward = await stakingPoolFactory.calPendingFactoryReward();
        expect(pendingReward.toNumber()).to.greaterThan(0);

        oldPriceOfWeight = await stakingPoolFactory.priceOfWeight();
        expect(oldPriceOfWeight.toNumber()).to.equal(0);
      });

      it("price of weight increase", async function () {
        await stakingPoolFactory.createPool(slpToken.address, 79);
        pendingReward = await stakingPoolFactory.calPendingFactoryReward();
        expect(pendingReward).to.be.equal(0);
        newPriceOfWeight = await stakingPoolFactory.priceOfWeight();
        expect(newPriceOfWeight - oldPriceOfWeight).to.greaterThan(0);
        oldPriceOfWeight = newPriceOfWeight;

        await stakingPoolFactory.unregisterPool(await stakingPoolFactory.tokenPoolMap(slpToken.address));
        pendingReward = await stakingPoolFactory.calPendingFactoryReward();
        expect(pendingReward).to.be.equal(0);
        newPriceOfWeight = await stakingPoolFactory.priceOfWeight();
        expect(newPriceOfWeight - oldPriceOfWeight).to.greaterThan(0);
        oldPriceOfWeight = newPriceOfWeight;

        await stakingPoolFactory.createPool(slpToken.address, 69);
        pendingReward = await stakingPoolFactory.calPendingFactoryReward();
        expect(pendingReward).to.be.equal(0);
        newPriceOfWeight = await stakingPoolFactory.priceOfWeight();
        expect(newPriceOfWeight - oldPriceOfWeight).to.greaterThan(0);
      });
    });
  });

  describe("registerApeXPool", function () {
    it("reverted when register by unauthorized account", async function () {
      await expect(stakingPoolFactory.connect(addr1).registerApeXPool(slpToken.address, 79)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });

    it("reverted when register non apeX pool", async function () {
      await expect(stakingPoolFactory.registerApeXPool(fakeApexPoolWithSlpToken.address, 79)).to.be.revertedWith(
        "spf.registerApeXPool: MUST_APEX"
      );
    });

    it("reverted when register apeX pool already", async function () {
      await expect(stakingPoolFactory.registerApeXPool(fakeApexPool.address, 79)).to.be.revertedWith(
        "spf.registerPool: POOL_TOKEN_REGISTERED"
      );
    });
  });

  describe("unregisterPool", function () {
    it("unregister a registered stakingPool", async function () {
      await stakingPoolFactory.unregisterPool(apexPool.address);
      expect(await stakingPoolFactory.totalWeight()).to.be.equal(0);
      expect((await stakingPoolFactory.lastTimeUpdatePriceOfWeight()).toNumber()).to.greaterThan(0);

      let poolWeight = await stakingPoolFactory.poolWeightMap(apexPool.address);
      expect(poolWeight.weight).to.be.equal(21);
      expect(poolWeight.lastYieldPriceOfWeight).to.be.equal(0);
      expect(poolWeight.exitYieldPriceOfWeight.toNumber()).to.be.equal(await stakingPoolFactory.priceOfWeight());

      expect(await stakingPoolFactory.tokenPoolMap(apexPool.address)).to.be.equal(ethers.constants.AddressZero);
    });

    it("reverted when unregister a unregistered stakingPool", async function () {
      await stakingPoolFactory.unregisterPool(apexPool.address);
      await expect(stakingPoolFactory.unregisterPool(apexPool.address)).to.be.revertedWith(
        "spf.unregisterPool: POOL_HAS_UNREGISTERED"
      );
    });

    it("reverted when unregister by unauthorized account", async function () {
      await expect(stakingPoolFactory.connect(addr1).unregisterPool(slpToken.address)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });

    it("revert when unregister a never registered stakingPool", async function () {
      await expect(stakingPoolFactory.unregisterPool(fakeApexPool.address)).to.be.revertedWith(
        "spf.unregisterPool: POOL_NOT_REGISTERED"
      );
    });

    describe("after unregister pool", function () {
      let StakingPoolTemplate;
      beforeEach(async function () {
        StakingPoolTemplate = await ethers.getContractFactory("StakingPool");
        await stakingPoolFactory.createPool(slpToken.address, 79);
      });

      it("can process exist reward after unregister pool", async function () {
        let slpPoolAddress = await stakingPoolFactory.tokenPoolMap(slpToken.address);
        let slpPool = StakingPoolTemplate.attach(slpPoolAddress);
        await slpToken.mint(owner.address, 100_0000);
        await slpToken.approve(slpPool.address, 100_0000);
        await slpPool.stake(10000, 0);
        await slpPool.processRewards();

        let oldEsApeXBalance = (await esApeXToken.balanceOf(owner.address)).toNumber();
        await stakingPoolFactory.unregisterPool(slpPoolAddress);

        await slpPool.processRewards();
        let newEsApeXBalance = (await esApeXToken.balanceOf(owner.address)).toNumber();
        expect(newEsApeXBalance).to.greaterThan(oldEsApeXBalance);
      });

      it("final reward of unregister pool is fixed", async function () {
        let slpPoolAddress = await stakingPoolFactory.tokenPoolMap(slpToken.address);
        let slpPool = StakingPoolTemplate.attach(slpPoolAddress);
        await slpToken.mint(owner.address, 100_0000);
        await slpToken.approve(slpPool.address, 100_0000);
        await slpPool.stake(10000, 0);
        await slpPool.processRewards();

        await stakingPoolFactory.unregisterPool(slpPoolAddress);
        await slpPool.processRewards();
        let newEsApeXBalance = (await esApeXToken.balanceOf(owner.address)).toNumber();

        await network.provider.send("evm_mine");
        await slpPool.processRewards();
        let finalEsApeXBalance = (await esApeXToken.balanceOf(owner.address)).toNumber();
        expect(finalEsApeXBalance).to.equal(newEsApeXBalance);

        await network.provider.send("evm_mine");
        await slpPool.processRewards();
        let finalEsApeXBalance1 = (await esApeXToken.balanceOf(owner.address)).toNumber();
        expect(finalEsApeXBalance1).to.equal(newEsApeXBalance);
      });
    });
  });

  describe("changePoolWeight", function () {
    it("change pool weight", async function () {
      await stakingPoolFactory.changePoolWeight(apexPool.address, 89);
      let poolWeight = await stakingPoolFactory.poolWeightMap(apexPool.address);
      expect(poolWeight.weight).to.be.equal(89);
      expect(await stakingPoolFactory.totalWeight()).to.be.equal(89);
    });

    it("revert when change pool weight with invalid user", async function () {
      await expect(stakingPoolFactory.connect(addr1).changePoolWeight(apexPool.address, 89)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });

    it("revert when pool not exist", async function () {
      await expect(stakingPoolFactory.changePoolWeight(addr1.address, 89)).to.be.revertedWith(
        "spf.changePoolWeight: POOL_NOT_EXIST"
      );
    });

    it("revert when change pool weight to 0 weight", async function () {
      await stakingPoolFactory.unregisterPool(apexPool.address);
      await expect(stakingPoolFactory.changePoolWeight(apexPool.address, 0)).to.be.revertedWith(
        "spf.changePoolWeight: POOL_INVALID"
      );
    });

    it("revert when change pool weight to 0", async function () {
      await expect(stakingPoolFactory.changePoolWeight(apexPool.address, 0)).to.be.revertedWith(
        "spf.changePoolWeight: CANT_CHANGE_TO_ZERO_WEIGHT"
      );
    });

    describe("settle the former pools when change pool weight", function () {
      let pendingReward;
      let oldPriceOfWeight;
      let newPriceOfWeight;
      beforeEach(async function () {
        pendingReward = await stakingPoolFactory.calPendingFactoryReward();
        expect(pendingReward.toNumber()).to.greaterThan(0);

        oldPriceOfWeight = await stakingPoolFactory.priceOfWeight();
        expect(oldPriceOfWeight.toNumber()).to.equal(0);
      });

      it("price of weight increase after change pool weight", async function () {
        await stakingPoolFactory.changePoolWeight(apexPool.address, 79);
        pendingReward = await stakingPoolFactory.calPendingFactoryReward();
        expect(pendingReward).to.be.equal(0);
        newPriceOfWeight = await stakingPoolFactory.priceOfWeight();
        expect(newPriceOfWeight - oldPriceOfWeight).to.greaterThan(0);
        oldPriceOfWeight = newPriceOfWeight;

        await stakingPoolFactory.changePoolWeight(apexPool.address, 69);
        pendingReward = await stakingPoolFactory.calPendingFactoryReward();
        expect(pendingReward).to.be.equal(0);
        newPriceOfWeight = await stakingPoolFactory.priceOfWeight();
        expect(newPriceOfWeight - oldPriceOfWeight).to.greaterThan(0);
        oldPriceOfWeight = newPriceOfWeight;

        await stakingPoolFactory.changePoolWeight(apexPool.address, 59);
        pendingReward = await stakingPoolFactory.calPendingFactoryReward();
        expect(pendingReward).to.be.equal(0);
        newPriceOfWeight = await stakingPoolFactory.priceOfWeight();
        expect(newPriceOfWeight - oldPriceOfWeight).to.greaterThan(0);
      });
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

    it("after update apeXPerSec, decrease release ratio", async function () {
      await network.provider.send("evm_mine");
      await stakingPoolFactory.updateApeXPerSec();
      let oldPendingReward = await stakingPoolFactory.calPendingFactoryReward();

      await network.provider.send("evm_mine");
      await stakingPoolFactory.updateApeXPerSec();
      let newPendingReward = await stakingPoolFactory.calPendingFactoryReward();
      expect(oldPendingReward * 0.97 - newPendingReward).to.lessThan(oldPendingReward * 0.001);
    });
  });

  describe("calStakingPoolApeXReward", function () {
    it("calculate reward after some time", async function () {
      await network.provider.send("evm_mine");
      await stakingPoolFactory.updateApeXPerSec();
      let result = await stakingPoolFactory.calStakingPoolApeXReward(apexToken.address);
      let pending = (await stakingPoolFactory.calPendingFactoryReward()).toNumber();
      expect(result[0].toNumber()).to.lessThanOrEqual(pending);
      expect(result[0].toNumber()).to.greaterThan(0);
    });
  });

  describe("transferYieldTo", function () {
    it("reverted when transfer apeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.transferYieldTo(addr1.address, 10)).to.be.revertedWith(
        "spf.transferYieldTo: ACCESS_DENIED"
      );
    });
  });

  describe("transferYieldToTreasury", function () {
    it("reverted when transfer apeX to treasury by unauthorized account", async function () {
      await expect(stakingPoolFactory.transferYieldToTreasury(10)).to.be.revertedWith(
        "spf.transferYieldToTreasury: ACCESS_DENIED"
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

  describe("setEsApeX", function () {
    it("reverted when set EsApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.connect(addr1).setEsApeX(addr1.address)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });

    it("reverted when set esApeX which has been set", async function () {
      await expect(stakingPoolFactory.setEsApeX(addr1.address)).to.be.revertedWith("spf.setEsApeX: HAS_SET");
    });
  });

  describe("setVeApeX", function () {
    it("reverted when set VeApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.connect(addr1).setVeApeX(addr1.address)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });

    it("reverted when set veApeX which has been set", async function () {
      await expect(stakingPoolFactory.setVeApeX(addr2.address)).to.be.revertedWith("spf.setVeApeX: HAS_SET");
    });
  });

  describe("setMinRemainRatioAfterBurn", function () {
    it("can set min remain ratio after burn", async function () {
      await stakingPoolFactory.setMinRemainRatioAfterBurn(10);
      expect(await stakingPoolFactory.minRemainRatioAfterBurn()).to.be.equal(10);
    });

    it("reverted when set by unauthorized account", async function () {
      await expect(stakingPoolFactory.connect(addr1).setMinRemainRatioAfterBurn(10)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });

    it("reverted when set number bigger than 10k", async function () {
      await expect(stakingPoolFactory.setMinRemainRatioAfterBurn(10001)).to.be.revertedWith(
        "spf.setMinRemainRatioAfterBurn: INVALID_VALUE"
      );
    });
  });

  describe("setRemainForOtherVest", function () {
    it("can set remain for other vest", async function () {
      await stakingPoolFactory.setRemainForOtherVest(10);
      expect(await stakingPoolFactory.remainForOtherVest()).to.be.equal(10);
    });

    it("reverted when set by unauthorized account", async function () {
      await expect(stakingPoolFactory.connect(addr1).setRemainForOtherVest(10)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });

    it("reverted when set number bigger than 100", async function () {
      await expect(stakingPoolFactory.setRemainForOtherVest(101)).to.be.revertedWith(
        "spf.setRemainForOtherVest: INVALID_VALUE"
      );
    });
  });
});

const { expect } = require("chai");
const { BN, constants } = require("@openzeppelin/test-helpers");

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
      slpPool = await StakingPoolTemplate.attach(slpPoolAddress);
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
    });

    it("reverted when unregister by unauthorized account", async function () {
      await expect(stakingPoolFactory.connect(addr1).unregisterPool(slpToken.address)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });

    it("revert when unregister a unregistered stakingPool", async function () {
      await expect(stakingPoolFactory.unregisterPool(fakeApexPool.address)).to.be.revertedWith(
        "spf.unregisterPool: POOL_NOT_REGISTERED"
      );
    });

    describe("create an unregistered pool again", function () {
      let StakingPoolTemplate;
      beforeEach(async function () {
        StakingPoolTemplate = await ethers.getContractFactory("StakingPool");
        await stakingPoolFactory.createPool(slpToken.address, 79);
      });

      it("can create pool", async function () {
        let slpPoolAddress = await stakingPoolFactory.tokenPoolMap(slpToken.address);
        await stakingPoolFactory.unregisterPool(slpPoolAddress);

        await stakingPoolFactory.createPool(slpToken.address, 69);
        expect(await stakingPoolFactory.totalWeight()).to.be.equal(90);
      });

      it("can process exist reward after unregister pool", async function () {
        let slpPoolAddress = await stakingPoolFactory.tokenPoolMap(slpToken.address);
        let slpPool = await StakingPoolTemplate.attach(slpPoolAddress);
        await slpToken.mint(owner.address, 100_0000);
        await slpToken.approve(slpPool.address, 100_0000);
        await slpPool.stake(10000, 0);
        await slpPool.processRewards();

        await stakingPoolFactory.unregisterPool(slpPoolAddress);
        await slpPool.processRewards();
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
  });

  describe("changePoolWeight", function () {
    it("change pool weight", async function () {
      await stakingPoolFactory.changePoolWeight(apexPool.address, 89);
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

    it("revert when change pool weight to 0", async function () {
      await expect(stakingPoolFactory.changePoolWeight(apexPool.address, 0)).to.be.revertedWith(
        "spf.changePoolWeight: CANT_CHANGE_TO_ZERO_WEIGHT"
      );
    });

    it("revert when change pool with 0 weight", async function () {
      await stakingPoolFactory.unregisterPool(apexPool.address);
      await expect(stakingPoolFactory.changePoolWeight(apexPool.address, 0)).to.be.revertedWith(
        "spf.changePoolWeight: POOL_NOT_EXIST"
      );
    });
  });

  describe("calStakingPoolApeXReward", function () {
    it("calculate reward after some time", async function () {
      await network.provider.send("evm_mine");
      await stakingPoolFactory.updateApeXPerSec();
      let result = await stakingPoolFactory.calStakingPoolApeXReward(apexToken.address);
      let pending = (await stakingPoolFactory.calPendingFactoryReward()).toNumber();
      expect(result[0].toNumber()).to.lessThanOrEqual(pending);
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
  });

  describe("setVeApeX", function () {
    it("reverted when set VeApeX by unauthorized account", async function () {
      await expect(stakingPoolFactory.connect(addr1).setVeApeX(addr1.address)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });
  });

  describe("setMinRemainRatioAfterBurn", function () {
    it("reverted when set by unauthorized account", async function () {
      await expect(stakingPoolFactory.connect(addr1).setMinRemainRatioAfterBurn(10)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });
  });

  describe("setRemainForOtherVest", function () {
    it("reverted when set by unauthorized account", async function () {
      await expect(stakingPoolFactory.connect(addr1).setRemainForOtherVest(10)).to.be.revertedWith(
        "Ownable: REQUIRE_OWNER"
      );
    });
  });
});

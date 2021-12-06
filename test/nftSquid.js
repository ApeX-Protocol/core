const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");

describe("nftSquid contract", function () {
  let nftSquid;
  beforeEach(async function () {
    [owner, addr1, liquidator, ...addrs] = await ethers.getSigners();

    const NftSquid = await ethers.getContractFactory("NftSquid");
    nftSquid = await NftSquid.deploy();
  });
  describe("startTime", async function () {
    it("reverted if invalid startTime", async function () {
      await expect(nftSquid.setStartTime(0)).to.be.revertedWith("INVALID_START_TIME");
    });

    it("reverted if not arrived startTime", async function () {
      await nftSquid.setStartTime(1922747905);
      expect(await nftSquid.startTime()).to.be.equal(1922747905);
      await expect(nftSquid.burn(0)).to.be.revertedWith("NOT_STARTED");
    });

    it("set startTime", async function () {
      let ct = currentTimestamp();
      await nftSquid.setStartTime(ct + 10);
      expect(await nftSquid.startTime()).to.be.equal(ct + 10);
    });
  });

  describe("burn", async function () {
    beforeEach(async function () {
      let ct = currentTimestamp();
      await nftSquid.setStartTime(ct + 10);
    });

    it("burn 0", async function () {
      let oldRemainOwners = await nftSquid.remainOwners();
      await sleep(10000);
      await nftSquid.burn(0);
      expect(await nftSquid.remainOwners()).to.be.equal(oldRemainOwners - 1);
    });
  });
});

function currentTimestamp() {
  let dateTime = new Date();
  return Math.floor(dateTime / 1000);
}

async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

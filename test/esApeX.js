const { expect } = require("chai");
const { BN, constants, time } = require("@openzeppelin/test-helpers");

describe("esApeX contract", function () {
  let esApeXToken;

  let owner;
  let addr1;
  let addr2;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    const EsAPEX = await ethers.getContractFactory("EsAPEX");
    esApeXToken = await EsAPEX.deploy(addr1.address);
  });

  describe("mint", function () {
    it("can mint by whitelist operator", async function () {
      let oldBalance = (await esApeXToken.balanceOf(owner.address)).toNumber();
      await esApeXToken.connect(addr1).mint(owner.address, 100);
      let newBalance = (await esApeXToken.balanceOf(owner.address)).toNumber();
      expect(newBalance).to.be.equal(oldBalance + 100);
    });

    it("revert when mint by non-whitelist operator", async function () {
      await expect(esApeXToken.mint(owner.address, 100)).to.be.revertedWith("whitelist: NOT_IN_WHITELIST");
    });

    it("can mint by whitelist operator who is added", async function () {
      await esApeXToken.addWhitelist(owner.address);
      let oldBalance = (await esApeXToken.balanceOf(owner.address)).toNumber();
      await esApeXToken.mint(owner.address, 100);
      let newBalance = (await esApeXToken.balanceOf(owner.address)).toNumber();
      expect(newBalance).to.be.equal(oldBalance + 100);
    });

    it("revert when mint by non-whitelist operator who is removed", async function () {
      await esApeXToken.removeWhitelist(addr1.address);
      await expect(esApeXToken.connect(addr1).mint(owner.address, 100)).to.be.revertedWith(
        "whitelist: NOT_IN_WHITELIST"
      );
    });
  });
});

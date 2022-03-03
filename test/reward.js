// const ether = require("@openzeppelin/test-helpers/src/ether");
const { expect } = require("chai");

describe("Invitation", function () {
  let rewardContract;
  let owner;
  let alice;
  let signature;

  beforeEach(async function () {
    [alice] = await ethers.getSigners();
    let privateKey = "0x0123456789012345678901234567890123456789012345678901234567890123";
    owner = new ethers.Wallet(privateKey);
    const Reward = await ethers.getContractFactory("Reward");

    rewardContract = await Reward.deploy(owner.address);
    let messageHash = ethers.utils.solidityKeccak256(["string"], ["message"]);
    signature = await owner.signMessage(ethers.utils.arrayify(messageHash));
  });

  it("correct message and signer", async function () {
    expect(await rewardContract.tryVerify("message", signature)).to.equal(owner.address);
  });

  it("wrong message", async function () {
    expect(await rewardContract.tryVerify("wrong message", signature)).to.not.equal(owner.address);
  });

  it("wrong signer", async function () {
    expect(await rewardContract.tryVerify("message", signature)).to.not.equal(alice.address);
  });
});

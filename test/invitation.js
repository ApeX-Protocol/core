const { expect } = require("chai");
const { ethers } = require("hardhat");

// const MINIMUM_LIQUIDITY = bigNumberify(10).pow(3)

describe("Invitation", function () {
  let invitation;
  let alice;
  let owner;
  let bob;

  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();
    console.log("owner:", owner.address);
    console.log("alice:", alice.address);
    const InvivationFactory = await ethers.getContractFactory("Invitation");

    invitation = await InvivationFactory.deploy();
    console.log("invitation address: ", invitation.address);
  });

  // it("register", async function () {
  //   console.log("---------test begin---------");
  //   console.log(await invitation.totalRegisterCount());

  //   await expect(invitation.register())
  //     .to.emit(invitation, "Invite")
  //     .withArgs(owner.address, "0x0000000000000000000000000000000000000000", 2);
  //   expect(await invitation.totalRegisterCount()).to.equal(1);

  //   const invitationAlice = invitation.connect(alice);

  //   await invitationAlice.acceptInvitation(owner.address);

  //   expect(await invitation.totalRegisterCount()).to.equal(2);

  //   console.log(await invitationAlice.getLowers1(owner.address));

  //   expect((await invitationAlice.getLowers1(owner.address))[0]).equal(alice.address);
  //   expect(await invitationAlice.getUpper1(alice.address)).equal(owner.address);
  // });

  it("A invite B, then B invite C, then C invite A", async function() {
    const invitationAlice = invitation.connect(alice);
    await invitationAlice.acceptInvitation(owner.address);

    const invitationBob = invitation.connect(bob);
    await invitationBob.acceptInvitation(alice.address);

    await invitation.acceptInvitation(bob.address);
  });
});

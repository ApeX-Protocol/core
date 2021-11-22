const { expect } = require("chai");

// const MINIMUM_LIQUIDITY = bigNumberify(10).pow(3)

describe("Invitation", function () {
  let invitation;
  let alice;
  let owner;
  let bob;
  
  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();
    console.log("owner:", owner.address);
    const InvivationFactory = await ethers.getContractFactory("Invivation");

    //ammFactory
    
    invitation = await InvivationFactory.deploy();
    console.log("invitation address: ", invitation.address);

  });

  it("register", async function () {
  
    console.log("---------test begin---------");
    await invitation.register();
    console.log(await invitation.totalRegisterCount());
    
    await expect(invitation.register())
      .to.emit(invitation, "Invite")
      .withArgs(
        owner.address,
        0,
        1
      );

      const invitationAlice = invitation.connect(alice);


     await invitationAlice.acceptInvitation(owner.address);
     
     console.log(await invitation.totalRegisterCount());
    

  });



  
});

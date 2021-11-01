const { expect } = require("chai");

// const MINIMUM_LIQUIDITY = bigNumberify(10).pow(3)

describe("Amm", function () {
  let math;
  let owner;
  let alice;
  let bob;

  let exp1 = ethers.BigNumber.from("10").pow(18);
  let exp2 = ethers.BigNumber.from("10").pow(6);

  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();
    console.log(owner.address);
    const MathTestFactory = await ethers.getContractFactory("MathTest");
   

    //math deploy
    math = await MathTestFactory.deploy();
    console.log("math: ", math.address);
  });
    
  it("check boundary", async function () {

  let tx = await math.swapQueryWithAcctSpecMarkPrice( ethers.BigNumber.from("17000").mul(exp1),0);

   console.log(tx);
   //   quoteAmount = 17000000000000000000000
   //  denominator = 40161075531336156738371338784040912734718073971073827466384
   //   L =          20080524955802356784175387030783501615047019890098731084
   expect(tx).to.equal(ethers.BigNumber.from("8499994577642297028"));
   
   });

  });

  

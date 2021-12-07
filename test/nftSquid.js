const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");

async function deploy(name, ...params) {
  const Contract = await ethers.getContractFactory(name);
  return await Contract.deploy(...params).then((f) => f.deployed());
}

describe("nftSquid contract", function () {
  let nftSquid;
  let erc20;
  let exp1 = ethers.BigNumber.from("10").pow(18);
  let ct;
  let args;

  beforeEach(async function () {
    [owner, addr1, liquidator, ...addrs] = await ethers.getSigners();
    erc20 = await deploy("MyToken", "AAA token", "AAA", 18, 100000000);

    const NftSquid = await ethers.getContractFactory("NftSquid");
    nftSquid = await NftSquid.deploy(erc20.address);
    ct = currentTimestamp();
    console.log("ct:", ct);

    await nftSquid.setStartTime(ct + 500);
    await erc20.transfer(nftSquid.address, ethers.BigNumber.from("10000000").mul(exp1));
  });

  // it("burn 0", async function () {
  //   let overrides = {
  //     value: ethers.utils.parseEther("0.01")
  //   }
  //    await nftSquid.claimApeXNFT(overrides);

  //   let oldRemainOwners = await nftSquid.remainOwners();
  //   await network.provider.send("evm_increaseTime", [60])
  //   await network.provider.send("evm_mine")
  //   await nftSquid.burn(0);
  //   expect(await nftSquid.remainOwners()).to.be.equal(oldRemainOwners - 1);
  // });
  // it("burn 456 in  0 month", async function () {
  //   let i =0;
  //   let overrides = {
  //     value: ethers.utils.parseEther("0.01")
  //   }
  //   for( i =0 ;i< 456; i++) {
  //    await nftSquid.claimApeXNFT(overrides);
  //   }
  //   await network.provider.send("evm_increaseTime", [600])
  //   await network.provider.send("evm_mine")
  //   console.log("mint successfully.");
  //    i =0;

  //   for( i =0 ;i< 456; i++) {

  //   let tx = await nftSquid.burn(i);
  //   let txReceipt = await tx.wait();
  //    args = txReceipt["events"][2].args;
  //   // if(i%100==0) {
  //   console.log("id : ", args[0].toString());
  //   console.log("amount ", args[1].div(exp1).toString());
  //  // }

  //   }
  //   expect(args[1].div(exp1).toString()).to.be.equal('165548');
  //   expect(args[0].toString()).to.be.equal('455');
  // });

  it("burn 456 in  1 month", async function () {
    let i = 0;
    let overrides = {
      value: ethers.utils.parseEther("0.01"),
    };
    for (i = 0; i < 456; i++) {
      await nftSquid.claimApeXNFT(overrides);
    }
    await network.provider.send("evm_increaseTime", [2592000 * 6]);
    await network.provider.send("evm_mine");
    console.log("mint successfully.");
    i = 0;

    for (i = 0; i < 456; i++) {
      let tx = await nftSquid.burn(i);
      let txReceipt = await tx.wait();
      args = txReceipt["events"][2].args;
      // if(i%100==0) {
      console.log("id : ", args[0].toString());
      console.log("amount ", args[1].div(exp1).toString());
      // }
    }
    expect(args[1].div(exp1).toString()).to.be.equal("75221");
    expect(args[0].toString()).to.be.equal("455");
  });
});

function currentTimestamp() {
  let dateTime = new Date();
  return Math.floor(dateTime / 1000);
}

//ms
async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}


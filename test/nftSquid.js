const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");
const  fs  = require('fs');
const { ethers } = require("hardhat");

async function deploy(name, ...params) {
  const Contract = await ethers.getContractFactory(name);
  return await Contract.deploy(...params).then((f) => f.deployed());
}
// it takes long time to test.  please open it individually
describe("nftSquid contract", function () {
  let nftSquid;
  let erc20;
  let exp1 = ethers.BigNumber.from("10").pow(18);
  let players = 4560;

  let args;
  let dateTime = new Date();
  let ct = Math.floor(dateTime / 1000);

  beforeEach(async function () {
    [owner, addr1, liquidator, ...addrs] = await ethers.getSigners();
    erc20 = await deploy("MyToken", "AAA token", "AAA", 18, 100000000);

    const NftSquid = await ethers.getContractFactory("NftSquid");
    nftSquid = await NftSquid.deploy("APEX NFT", "APEXNFT", "https://apexNFT/", erc20.address, ct-1000, ct+5800);
    console.log("nftSquid: ", nftSquid.address);
    let symbol = await nftSquid.symbol();
    console.log("nftSquid: ", nftSquid.address);
    console.log("nftSquid symbol ", symbol);
  });

  // it("burn  4560 in  0 month", async function () {
  //   //await nftSquid.setStartTime(ct + 500);
  //   let balance = await ethers.provider.getBalance(owner.address);
  //   console.log("balance: ", balance.div(exp1).toString());

  //   let i = 0;

  //   let overrides = {
  //     value: ethers.utils.parseEther("0.001"),
  //   };

  //   const mySet1 = new Set()
  //   for (i = 0; i < players; i++) {
  //     let tx = await nftSquid.claimApeXNFT(1,overrides);
  //     let txReceipt = await tx.wait();
  //     args = txReceipt["events"][0].args;
  //     mySet1.add(args[2].toString());
     
  //   }
  //   expect(mySet1.size).to.be.equal(4560);
  //   let token0URI = await nftSquid.tokenURI(0);

  //   await erc20.transfer(nftSquid.address, ethers.BigNumber.from(4500 * players).mul(exp1));

  //   await nftSquid.setSquidStartTime(ct + 6000);
  //   await ethers.provider.send("evm_setNextBlockTimestamp", [ct + 6000]);
  //   await network.provider.send("evm_mine");
  //   console.log("mint nft successfully.");
  //   i = 0;

  //   for (i = 0; i < players; i++) {
  //     // await ethers.provider.send("evm_setNextBlockTimestamp", [ct + 33696 + 33696 * i]);
  //     // await network.provider.send("evm_mine");
  //     let tx = await nftSquid.burnAndEarn(i);
  //     let txReceipt = await tx.wait();
  //     args = txReceipt["events"][2].args;
  //     // if (i % 100 == 0) {
  //     //   console.log("id : ", i, "     amount ", args[1].div(exp1).toString());
  //     // }
  //     // if(i >= 4550) {
  //     //   console.log("id : ", i , "     amount ", args[1].div(exp1).toString());
  //     // }
  //   }

  //   expect(args[1].div(exp1).toString()).to.be.equal("123635");
  //   expect(args[0].toString()).to.be.equal("4559");

  //   await nftSquid.withdrawETH(owner.address);
  //   let balanceAfter = await ethers.provider.getBalance(owner.address);
  //   expect(balanceAfter.div(exp1).toString()).to.be.equal("9998");
  //   let apexAmount = await erc20.balanceOf(nftSquid.address);
  //   expect(apexAmount.div(exp1).toString()).to.be.equal("0");
  // });

  // it("add reserved", async function () {
  //    let dateTime = new Date();
  //    let ct = Math.floor(dateTime / 1000);
  //    console.log("ct:", ct);
  //   await nftSquid.setNFTEndTime(ct + 1000);
  //   let balance = await ethers.provider.getBalance(owner.address);
  //   console.log("balance: ", balance.div(exp1).toString());

  //   let i = 0;

  //   await nftSquid.setSquidStartTime(ct + 2000);
  //   await nftSquid.setNFTEndTime(ct + 6000);
  //   await nftSquid.addToReserved([addr1.address]);
  //   let overrides = {
  //     value: ethers.utils.parseEther("0.001"),
  //   };
  //   let reservedCount = await nftSquid.reservedCount();
  //   for (i = 0; i < players - reservedCount; i++) {
  //     await nftSquid.claimApeXNFT(overrides);
  //   }
  // });
});

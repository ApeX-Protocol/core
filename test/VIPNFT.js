const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");
const { ethers } = require("hardhat");

async function deploy(name, ...params) {
  const Contract = await ethers.getContractFactory(name);
  return await Contract.deploy(...params).then((f) => f.deployed());
}

describe("VIPNFT contract", function () {
  let vipNFT;

  let exp1 = ethers.BigNumber.from("10").pow(18);
  let players = 1;

  let ct;

  it("claim", async function () {
    [owner, Alice, liquidator, ...addrs] = await ethers.getSigners();
    erc20 = await deploy("MyToken", "AAA token", "AAA", 18, 100000000);

    const ApeXVIPNFT = await ethers.getContractFactory("ApeXVIPNFT");
    let dateTime = new Date();
    ct = Math.floor(dateTime / 1000);
    console.log("ct:", ct);

    let startTime = ct + 36000;
    let cliff = 3600 * 24 * 180;
    let duration = 3600 * 24 * 360;
    vipNFT = await ApeXVIPNFT.deploy(
      "APEX NFT",
      "APEXNFT",
      "https://apexVIPNFT/",
      erc20.address,
      startTime,
      cliff,
      duration);
 
    await vipNFT.addManyToWhitelist([Alice.address]);
    let vipNFTAlice = vipNFT.connect(Alice);
    let i = 0;
    let overrides = {
      value: ethers.utils.parseEther("0.01"),
    };

    // await ethers.provider.send("evm_setNextBlockTimestamp", [ct + 600]);
    // await ethers.provider.send("evm_mine");


    for (i = 0; i < players; i++) {
      await vipNFTAlice.claimApeXVIPNFT(overrides);
    }
    await vipNFT.setTotalAmount(ethers.BigNumber.from(625000).mul(exp1));

    await erc20.transfer(vipNFT.address, ethers.BigNumber.from(100000 * players).mul(exp1));
    await ethers.provider.send("evm_setNextBlockTimestamp", [ct + 3600 * 24 * 200]);
    await ethers.provider.send("evm_mine");

    await vipNFTAlice.claimAPEX();

    let balanceAfter = await ethers.provider.getBalance(vipNFT.address);
   
    expect(balanceAfter.mul(100).div(exp1).toString()).to.be.equal("1");
    let apexBalance = await erc20.balanceOf(Alice.address);
    // //expect(apexBalance.div(exp1).toString()).to.be.equal("69299");
    expect(apexBalance.div(exp1).toNumber()).to.be.greaterThan(60000);
  });
});

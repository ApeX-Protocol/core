const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");

async function deploy(name, ...params) {
  const Contract = await ethers.getContractFactory(name);
  return await Contract.deploy(...params).then((f) => f.deployed());
}

describe("VIPNFT contract", function () {
  let vipNFT;

  let exp1 = ethers.BigNumber.from("10").pow(18);
  let players = 20;
  let ct;

  beforeEach(async function () {
    [owner, Alice, liquidator, ...addrs] = await ethers.getSigners();

    const ApeXVIPNFT = await ethers.getContractFactory("ApeXVIPNFT");
    let dateTime = new Date();
    ct = Math.floor(dateTime / 1000);
    console.log("ct:", ct);
    vipNFT = await ApeXVIPNFT.deploy("APEX NFT", "APEXNFT", "https://apexVIPNFT/", ct + 500);
    console.log("vipNFT: ", vipNFT.address);
    let symbol = await vipNFT.symbol();
    console.log("vipNFT symbol ", symbol);
  });

  it("claim", async function () {
    await vipNFT.addManyToWhitelist([Alice.address]);
    let vipNFTAlice = vipNFT.connect(Alice);
    let i = 0;
    let overrides = {
      value: ethers.utils.parseEther("40"),
    };

    await ethers.provider.send("evm_setNextBlockTimestamp", [ct + 600]);
    await ethers.provider.send("evm_mine");

    for (i = 0; i < players; i++) {
      await vipNFTAlice.claimApeXVIPNFT(overrides);
    }

    console.log("mint nft successfully.");

    let balanceAfter = await ethers.provider.getBalance(vipNFT.address);
    console.log("balanceAfter: ", balanceAfter.div(exp1).toString());
  });
});

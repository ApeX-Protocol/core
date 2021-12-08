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
  let players = 456;

  let args;

  beforeEach(async function () {
    [owner, addr1, liquidator, ...addrs] = await ethers.getSigners();
    erc20 = await deploy("MyToken", "AAA token", "AAA", 18, 100000000);

    const NftSquid = await ethers.getContractFactory("NftSquid");
    nftSquid = await NftSquid.deploy("APEX NFT", "APEXNFT", "https://apexNFT/", erc20.address);
    console.log("nftSquid: ", nftSquid.address);
    let symbol = await nftSquid.symbol();
    console.log("nftSquid: ", nftSquid.address);
    console.log("nftSquid symbol ", symbol);
  });

  it("burn  456 in  6 month", async function () {
    let dateTime = new Date();
    let ct = Math.floor(dateTime / 1000);
    console.log("ct:", ct);
    await nftSquid.setStartTime(ct + 500);
    let balance = await ethers.provider.getBalance(owner.address);
    console.log("balance: ", balance.div(exp1).toString());
    let i = 0;
    let overrides = {
      value: ethers.utils.parseEther("2.5"),
    };

    for (i = 0; i < players; i++) {
      await nftSquid.claimApeXNFT(overrides);
    }
    let token0URI = await nftSquid.tokenURI(0);

    console.log("***token0URI***: ", token0URI);
    await erc20.transfer(nftSquid.address, ethers.BigNumber.from(15000 * players).mul(exp1));

    // await ethers.provider.send('evm_setNextBlockTimestamp', [ct+600])
    // await network.provider.send("evm_mine");
    console.log("mint nft successfully.");
    i = 0;

    for (i = 0; i < players; i++) {
      await ethers.provider.send("evm_setNextBlockTimestamp", [ct + 33696 + 33696 * i]);
      await network.provider.send("evm_mine");
      let tx = await nftSquid.burnAndEarn(i);
      let txReceipt = await tx.wait();
      args = txReceipt["events"][2].args;

      // console.log("id : ", args[0].add(1).toString());
      // console.log("amount ", (args[1].div(exp1).sub(10000)).toString());
    }
    expect(args[1].div(exp1).toString()).to.be.equal("103864");
    expect(args[0].toString()).to.be.equal("455");
    let balanceBefore = await ethers.provider.getBalance(owner.address);

    await nftSquid.withdrawETH(owner.address);
    let balanceAfter = await ethers.provider.getBalance(owner.address);
    console.log("balanceAfter: ", balanceAfter.div(exp1).toString());
    let apexAmount = await erc20.balanceOf(nftSquid.address);
    console.log("APEX token Amount: ", apexAmount);
  });
});

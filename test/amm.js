const { expect } = require("chai");

// const MINIMUM_LIQUIDITY = bigNumberify(10).pow(3)

describe("Amm", function () {
  let amm;
  let owner;
  let alice;
  let bob;
  let AAAToken;
  let USDT;
  let priceOracle;
  let config;
  let margin = 0x0;
  let exp1 = ethers.BigNumber.from("10").pow(18);
  let exp2 = ethers.BigNumber.from("10").pow(6);

  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();
    console.log(owner.address);
    const AMMFactory = await ethers.getContractFactory("Amm");
    const MyToken = await ethers.getContractFactory("MyToken");
    const PriceOracle = await ethers.getContractFactory("MockPriceOracle");
    const MockConfig = await ethers.getContractFactory("Config");

    //amm deploy
    amm = await AMMFactory.deploy();
    console.log("amm: ", amm.address);
    // oracle
    priceOracle = await PriceOracle.deploy();
    console.log("priceOracle: ", priceOracle.address);
    //config
    config = await MockConfig.deploy();
    console.log("config: ", config.address);

    await config.setPriceOracle(priceOracle.address);
    //token deploy
    //aaa 100m
    AAAToken = await MyToken.deploy("AAA Token", "AAA", 18, 100000000);
    console.log("AAA:", AAAToken.address);
    // usdt 1000m
    USDT = await MyToken.deploy("USDT MOCK", "UDST", 6, 1000000000);
    console.log("USDT:", USDT.address);

    const ownerBalance = await amm.balanceOf(owner.address);
    console.log("owner balance:", ownerBalance);

    // init alice and bob balance
    await AAAToken.transfer(alice.address, ethers.BigNumber.from("10000").mul(exp1));
    await AAAToken.transfer(bob.address, ethers.BigNumber.from("1000000").mul(exp1));
    await USDT.transfer(alice.address, ethers.BigNumber.from("10000").mul(exp2));
    await USDT.transfer(bob.address, ethers.BigNumber.from("1000000").mul(exp2));

    const tx = {
      to: amm.address,
      value: ethers.utils.parseEther("0.1"),
    };

    let fundtx = await owner.sendTransaction(tx);
    console.log(await fundtx.wait());

    // amm initialize
    await amm.initialize(AAAToken.address, USDT.address, config.address, alice.address, config.address);

    expect(await amm.totalSupply()).to.equal(ownerBalance);
    expect(await USDT.balanceOf(alice.address)).to.equal(ethers.BigNumber.from("10000").mul(exp2));
    expect(await AAAToken.balanceOf(alice.address)).to.equal(ethers.BigNumber.from("10000").mul(exp1));
    expect(await config.priceOracle()).to.equal(priceOracle.address);
    expect(await config.beta()).to.equal(100);
  });

  it("owner add liquidity", async function () {
    //owner mint 100W AAA, correspinding to generate 10W usdt
    // price AAA/usdt = 1/10
    console.log("---------test begin---------");
    await AAAToken.transfer(amm.address, ethers.BigNumber.from("1000000").mul(exp1));

    // let tx = await amm.mint(owner.address);
    // const minRes = await tx.wait();
    // const events = minRes["events"];
    // let args = events[4]["args"];
    // console.log("mint event baseAmount  : ", args.baseAmount.toString());
    // console.log("mint event quoteAmount: ", args.quoteAmount.toString());
    // console.log("mint event liquidity: ", args.liquidity.toString());

    await expect(amm.mint(owner.address))
      .to.emit(amm, "Mint")
      .withArgs(
        owner.address,
        owner.address,
        ethers.BigNumber.from("1000000").mul(exp1),
        100000000000,
        ethers.BigNumber.from("316227766016836933")
      );

    //alice swap in
    const ammAlice = amm.connect(alice);
    // alice swap 100AAA to usdt
    let tx1 = await ammAlice.swap(AAAToken.address, USDT.address, ethers.BigNumber.from("100").mul(exp1), 0);
    const swapRes = await tx1.wait();
    let eventabi = [
      "event Swap(address indexed inputToken, address indexed outputToken, uint256 inputAmount, uint256 outputAmount);",
    ];
    let iface1 = new ethers.utils.Interface(eventabi);
    let log1 = iface1.parseLog(swapRes.logs[1]);
    let args1 = log1["args"];
    //  console.log("swap input AAA for vusd event input  : ", args1.inputAmount.toString());
    //  console.log("swap input AAA for vusd event output: ", args1.outputAmount.toString());
    expect(args1.outputAmount).to.equal(9989002);

    //alice swap out
    let tx2 = await ammAlice.swap(AAAToken.address, USDT.address, 0, ethers.BigNumber.from("100").mul(exp2));
    // alice swap to 100 usdt
    const swapRes2 = await tx2.wait();
    let log2 = iface1.parseLog(swapRes2.logs[1]);
    let args2 = log2["args"];
    //  console.log("swap output vusd  for AAA event input  : ", args2.inputAmount.toString());
    //  console.log("swap output vusd  for AAA event output: ", args2.outputAmount.toString());
    expect(args2.inputAmount).to.equal(ethers.BigNumber.from("1002203414634867914265"));
  });

  it("check swap input in large size ", async function () {
    //owner mint 100W AAA, correspinding to generate 10W usdt
    // price AAA/usdt = 1/10
    console.log("---------test begin---------");
    await AAAToken.transfer(alice.address, ethers.BigNumber.from("10000000").mul(exp1));
    await AAAToken.transfer(amm.address, ethers.BigNumber.from("1000000").mul(exp1));

    await expect(amm.mint(owner.address))
      .to.emit(amm, "Mint")
      .withArgs(
        owner.address,
        owner.address,
        ethers.BigNumber.from("1000000").mul(exp1),
        100000000000,
        ethers.BigNumber.from("316227766016836933")
      );

    const ammAlice = amm.connect(alice);
    // alice swap 1000000AAA to usdt
    //alice swap out
    let tx1 = await ammAlice.swap(AAAToken.address, USDT.address, ethers.BigNumber.from("10000000").mul(exp1), 0);

    const swapRes = await tx1.wait();
    let eventabi = [
      "event Swap(address indexed inputToken, address indexed outputToken, uint256 inputAmount, uint256 outputAmount);",
    ];
    let iface1 = new ethers.utils.Interface(eventabi);
    let log1 = iface1.parseLog(swapRes.logs[1]);
    let args1 = log1["args"];

    expect(args1.outputAmount).to.equal(90900818926);
  });

  it("check swap output oversize  ", async function () {
    //owner mint 100W AAA, correspinding to generate 10W usdt
    // price AAA/usdt = 1/10
    console.log("---------test begin---------");
    await AAAToken.transfer(amm.address, ethers.BigNumber.from("1000000").mul(exp1));

    await expect(amm.mint(owner.address))
      .to.emit(amm, "Mint")
      .withArgs(
        owner.address,
        owner.address,
        ethers.BigNumber.from("1000000").mul(exp1),
        100000000000,
        ethers.BigNumber.from("316227766016836933")
      );

    const ammAlice = amm.connect(alice);
    // alice swap 100000AAA to usdt
    //alice swap out
    await expect(
      ammAlice.swap(AAAToken.address, USDT.address, 0, ethers.BigNumber.from("100000").mul(exp2))
    ).to.be.revertedWith("AMM: INSUFFICIENT_LIQUIDITY");
  });
});

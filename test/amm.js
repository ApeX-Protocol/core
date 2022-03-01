const { expect } = require("chai");

describe("Amm", function () {
  let amm;
  let ammFactory;
  let owner;
  let alice;
  let bob;
  let AAAToken;
  let USDT;
  let priceOracle;
  let config;
  let margin;
  let exp1 = ethers.BigNumber.from("10").pow(18);
  let exp2 = ethers.BigNumber.from("10").pow(6);
  let feeToSetter;

  beforeEach(async function () {
    [owner, alice, bob, feeToSetter] = await ethers.getSigners();
    console.log("owner:", owner.address);
    console.log("feeToSetter:", feeToSetter.address);
    const AMMContract = await ethers.getContractFactory("Amm");
    const AMMFactoryContract = await ethers.getContractFactory("AmmFactory");
    const MyToken = await ethers.getContractFactory("MyToken");
    const PriceOracle = await ethers.getContractFactory("MockPriceOracle");
    const MockConfig = await ethers.getContractFactory("MockConfig");
    const MockMargin = await ethers.getContractFactory("MockMargin");

    config = await MockConfig.deploy();
    console.log("config: ", config.address);
    // await config.initialize(owner.address);

    await config.setBeta(100);

    // ammFactory
    // ( upperFactory_, address config_, address feeToSetter_)
    ammFactory = await AMMFactoryContract.deploy(owner.address, config.address, feeToSetter.address);
    console.log("amm factory: ", ammFactory.address);

    // oracle
    priceOracle = await PriceOracle.deploy();
    console.log("priceOracle: ", priceOracle.address);

    await config.setPriceOracle(priceOracle.address);

    // token deploy
    // aaa 100m
    AAAToken = await MyToken.deploy("AAA Token", "AAA", 18, 100000000);
    console.log("AAA:", AAAToken.address);
    // usdt 1000m
    USDT = await MyToken.deploy("USDT MOCK", "UDST", 6, 1000000000);
    console.log("USDT:", USDT.address);

    // init alice and bob balance
    await AAAToken.transfer(alice.address, ethers.BigNumber.from("10000").mul(exp1));
    await AAAToken.transfer(bob.address, ethers.BigNumber.from("1000000").mul(exp1));
    await USDT.transfer(alice.address, ethers.BigNumber.from("10000").mul(exp2));
    await USDT.transfer(bob.address, ethers.BigNumber.from("1000000").mul(exp2));
    const tx1 = {
      to: AAAToken.address,
      value: ethers.utils.parseEther("0.1"),
    };

    await expect(owner.sendTransaction(tx1)).to.be.revertedWith(
      "function selector was not recognized and there's no fallback nor receive function"
    );

    let tx = await ammFactory.createAmm(AAAToken.address, USDT.address);
    let txReceipt = await tx.wait();
    console.log("amm: ", txReceipt["events"][0].args[2]);
    let ammAddress = txReceipt["events"][0].args[2];

    amm = AMMContract.attach(ammAddress);

    // mock margin
    margin = await MockMargin.deploy();
    console.log("margin: ", margin.address);
    await margin.initialize(AAAToken.address, USDT.address, amm.address, config.address);
    await ammFactory.initAmm(AAAToken.address, USDT.address, margin.address);
    expect(await amm.totalSupply()).to.equal(0);
    expect(await USDT.balanceOf(alice.address)).to.equal(ethers.BigNumber.from("10000").mul(exp2));
    expect(await AAAToken.balanceOf(alice.address)).to.equal(ethers.BigNumber.from("10000").mul(exp1));
    expect(await config.priceOracle()).to.equal(priceOracle.address);
    expect(await config.beta()).to.equal(100);
  });

  it("owner add liquidity", async function () {
    // owner mint 100W AAA, correspinding to generate 10W usdt
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
    // alice swap in
    const marginAlice = margin.connect(alice);
    // alice swap 100AAA to usdt
    let tx1 = await marginAlice.swapProxy(alice.address, AAAToken.address, USDT.address, ethers.BigNumber.from("100").mul(exp1), 0);
    const swapRes = await tx1.wait();
    let eventabi = [
      "event Swap(address indexed trader, address indexed inputToken, address indexed outputToken, uint256 inputAmount, uint256 outputAmount)"
    ];

    let iface1 = new ethers.utils.Interface(eventabi);
    let log1 = iface1.parseLog(swapRes.logs[1]);
    let args1 = log1["args"];
    console.log("swap input AAA for vusd event input  : ", args1.inputAmount.toString());
    console.log("swap input AAA for vusd event output: ", args1.outputAmount.toString());
    expect(args1.outputAmount).to.equal(9989002);

    // alice swap out
    let tx2 = await marginAlice.swapProxy(alice.address, AAAToken.address, USDT.address, 0, ethers.BigNumber.from("100").mul(exp2));
    // alice swap to 100 usdt
    const swapRes2 = await tx2.wait();
    let log2 = iface1.parseLog(swapRes2.logs[1]);
    let args2 = log2["args"];
    // console.log("swap output vusd  for AAA event input  : ", args2.inputAmount.toString());
    // console.log("swap output vusd  for AAA event output: ", args2.outputAmount.toString());
    expect(args2.inputAmount).to.equal(ethers.BigNumber.from("1002203414634867914265"));
  });

  it("check swap input in large size ", async function () {
    // owner mint 100W AAA, correspinding to generate 10W usdt
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

    const marginAlice = margin.connect(alice);
    // alice swap 1000000AAA to usdt
    // alice swap in
    let price2 = await amm.lastPrice();

    // let reserver = await amm.getReserves();
    await expect(
      marginAlice.swapProxy(alice.address, AAAToken.address, USDT.address, ethers.BigNumber.from("10000000").mul(exp1), 0)
    ).to.be.revertedWith("AMM._update: TRADINGSLIPPAGE_TOO_LARGE");

    let tx1 = await marginAlice.swapProxy(alice.address, AAAToken.address, USDT.address, ethers.BigNumber.from("10000").mul(exp1), 0);
    const swapRes = await tx1.wait();
    let eventabi = [
      "event Swap(address indexed trader, address indexed inputToken, address indexed outputToken, uint256 inputAmount, uint256 outputAmount)",
    ];
    let iface1 = new ethers.utils.Interface(eventabi);
    let log1 = iface1.parseLog(swapRes.logs[1]);
    let args1 = log1.args;

    let price3 = await amm.lastPrice();

    expect(price2).to.equal(price3);

    expect(args1.outputAmount).to.equal(989118704);
    await marginAlice.swapProxy(alice.address, AAAToken.address, USDT.address, ethers.BigNumber.from("10000").mul(exp1), 0);

    let price4 = await amm.lastPrice();

    expect(price3).to.not.equal(price4);
  });

  it("check swap output oversize  ", async function () {
    // owner mint 100W AAA, correspinding to generate 10W usdt
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

    const marginAlice = margin.connect(alice);
    // alice swap  some AAA to 100000 usdt
    // alice swap out
    await expect(
      marginAlice.swapProxy(alice.address, AAAToken.address, USDT.address, 0, ethers.BigNumber.from("100000").mul(exp2))
    ).to.be.revertedWith("AMM._estimateSwap: INSUFFICIENT_LIQUIDITY");
  });
});

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
      //aaa 1 亿
      AAAToken = await MyToken.deploy("AAA Token", "AAA", 18, 100000000);
      console.log("AAA:", AAAToken.address);
      // usdt 10亿
      USDT = await MyToken.deploy("USDT MOCK", "UDST", 6, 1000000000);
      console.log("USDT:", USDT.address);
     
      const ownerBalance = await amm.balanceOf(owner.address);
      console.log("owner balance:", ownerBalance);

  

      // init alice and bob balance
     await AAAToken.transfer(alice.address, ethers.BigNumber.from("10000").mul(exp1));
     await AAAToken.transfer(bob.address, ethers.BigNumber.from("1000000").mul(exp1));
     await USDT.transfer(alice.address, ethers.BigNumber.from("10000").mul(exp2));
     await USDT.transfer(bob.address, ethers.BigNumber.from("1000000").mul(exp2));
      
     
      // amm initialize
     await amm.initialize(AAAToken.address, USDT.address, config.address, config.address, config.address);

   

      expect(await amm.totalSupply()).to.equal(ownerBalance);
      expect(await USDT.balanceOf(alice.address)).to.equal(ethers.BigNumber.from("10000").mul(exp2));
      expect(await AAAToken.balanceOf(alice.address)).to.equal(ethers.BigNumber.from("10000").mul(exp1));
      expect(await config.priceOracle()).to.equal(priceOracle.address);
      expect(await config.beta()).to.equal(100);
  
    });

    it("owner add liquidity", async function () {
      //owner 转100W AAA作为流动性
      // price AAA/usdt = 1/10
      console.log("---------test begin---------");
      await AAAToken.transfer(amm.address, ethers.BigNumber.from("1000000").mul(exp1) );
      let tx = await amm.mint(owner.address);
      const minRes = await tx.wait();
      const events = minRes["event"];

      console.log("mint event:", events);
     
      // var abi = [ "Mint(address indexed sender,address indexed to,uint256 baseAmount,uint256 quoteAmount,uint256 liquidity)" ];
      // var iface = new ethers.utils.Interface(abi);  
      // var parsedEvents = events.map(function(log) {iface.parseLog(log)});
      // console.log(parsedEvents);
      const ownerBalance = await amm.balanceOf(owner.address);
      console.log(ownerBalance);
      expect(await amm.totalSupply()).to.equal(ownerBalance.add("1000"));
   

      //const AAAAlice = AAAToken.connect(alice);
  
    });
});

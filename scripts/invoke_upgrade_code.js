const { upgrades,ethers } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

//// prod
// const apeXTokenAddress = "0x61A1ff55C5216b636a294A07D77C6F4Df10d3B56"; // Layer2 ApeX Token
// const v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; // UniswapV3Factory address
// const wethAddress = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1"; // WETH address in ArbitrumOne

// test
const apeXTokenAddress = "0x3f355c9803285248084879521AE81FF4D3185cDD"; // testnet apex token
const v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; // testnet uniV3factory
const wethAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44"; // mockWETH

let signer;

let config;
let pairFactory;
let ammFactory;
let marginFactory;

/// below variables only for testnet
let mockWETH;
let mockWBTC;
let mockUSDC;
let mockSHIB;
let ammAddress;
let marginAddress;
let ammAddress1;
let marginAddress1;
let proxyAdmin = "0xEd0b8F2afFA277B6Fac06885376B441693146871";
let pairFactoryAddress = "0x631c7Fb066b8e8488de79043489e622F412164D6";
let ammFactoryAddress = "0xd0ceEE1Ac88B74F538c5375F75529babbA168D6B";
let marginFactoryAddress = "0x5F46787C1fB332aBe35181F30C7D279dc7e5995d";
let router = "0xd141c074A62d42a6B848b21d9D31B37Dc88B5D13";

//eth-usdc
let  amm =  0xcD13EF6811b220feB6c4D65aAc5fACCF85250340;

let margin =  0xe240b8C0c19caF57c7EEA9D11b80e5f86CC1426b;

let marginNew = "0xf0D440E07d4aE1Bb3f9FC70a7f4E1E48821d0cb5";
let marginNewContract;

const main = async () => {
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  console.log(signer.address)

  // await testMarginUpgrade();

 
 // await testSetPairhash();

 // await prepareCheck();
 
};



async function prepareCheck() {
  let marginNewContractFactory = await ethers.getContractFactory('MarginNew');
  console.log("marginNew ", ethers.utils.sha256(marginNewContractFactory.bytecode));

  let marginContractFactory = await ethers.getContractFactory('Margin');
  console.log("margin ", ethers.utils.sha256(marginContractFactory.bytecode));

  const PairFactory = await ethers.getContractFactory("PairFactory");
  pairFactory = await PairFactory.attach(pairFactoryAddress);

  let marginBytecode = await pairFactory.marginBytecode();
  console.log("marginBytecode :", ethers.utils.sha256(marginBytecode));
}

async function testMarginUpgrade() {
  await loadProxyAdmin();

  await attachPairFactory();

  await checkMargin();

  await loadNewMargin();

  await checkMarginAfter();
}


async function testSetPairhash() {
  await loadProxyAdmin();

  await attachPairFactory();

  await createNewPair();

  await checkMarginAfter();
}





async function loadProxyAdmin() {
  let proxyAdminContractFactory = await ethers.getContractFactory(
    'ProxyAdmin'
  );
  proxyAdminContract = await proxyAdminContractFactory.attach(proxyAdmin);
}

async function loadNewMargin() {
  let marginNewContractFactory = await ethers.getContractFactory('MarginNew');
   marginNewContract = await marginNewContractFactory.attach(marginNew);
  
}

async function checkMargin() {
  const marginFactory = await ethers.getContractFactory("Margin");
  let marginContract = await marginFactory.attach(marginAddress);

  let baseToken = await marginContract.baseToken();
  console.log("margin baseToken: ", baseToken.toString());

  let netposition = await marginContract.netPosition();
  console.log("netPosition: ", netposition.toString());
}

async function checkMarginAfter() {
  const marginNewFactory = await ethers.getContractFactory("Margin");
  let marginNewContract = await marginNewFactory.attach(marginAddress1);

  let quoteToken = await marginNewContract.quoteToken();
  console.log("marginNew quoteToken: ", quoteToken.toString());

  let netposition = await marginNewContract.netPosition();
  console.log("marginNew netPosition: ", netposition.toString());


}



async function attachPairFactory() {
  

  const PairFactory = await ethers.getContractFactory("PairFactory");
  const AmmFactory = await ethers.getContractFactory("AmmFactory");
  const MarginFactory = await ethers.getContractFactory("MarginFactory");

  pairFactory = await PairFactory.attach(pairFactoryAddress);
  

  ammFactory = await AmmFactory.attach(ammFactoryAddress);
 
  marginFactory = await MarginFactory.attach(marginFactoryAddress);


  let marginBytecode =  await pairFactory.marginBytecode();
   console.log("marginBytecode before:", ethers.utils.sha256(marginBytecode));
 


}


async function createNewPair() {
  

  const PairFactory = await ethers.getContractFactory("PairFactory");
  const AmmFactory = await ethers.getContractFactory("AmmFactory");
  const MarginFactory = await ethers.getContractFactory("MarginFactory");



  pairFactory = await PairFactory.attach(pairFactoryAddress);
  
  ammFactory = await AmmFactory.attach(ammFactoryAddress);
 
  marginFactory = await MarginFactory.attach(marginFactoryAddress);
  let baseTokenAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44"; // mockWETH in testnet
  let quoteTokenAddress = "0x3f355c9803285248084879521AE81FF4D3185cDD"; // mshib in testnet


  let marginNewContractFactory = await ethers.getContractFactory('MarginNew');

  // set new code hash 
  await pairFactory.setMarginBytecode(marginNewContractFactory.bytecode); 


  await pairFactory.createPair(baseTokenAddress, quoteTokenAddress);
 
   ammAddress1 = await pairFactory.getAmm(baseTokenAddress, quoteTokenAddress);
   marginAddress1 = await pairFactory.getMargin(baseTokenAddress, quoteTokenAddress);

  console.log("Amm1:", ammAddress1);
  console.log("Margin1:", marginAddress1);

  let marginBytecode =  await pairFactory.marginBytecode();
  console.log("marginBytecode after:", ethers.utils.sha256(marginBytecode));

 



}



async function createMockTokens() {
  const MockWETH = await ethers.getContractFactory("MockWETH");
  mockWETH = await MockWETH.deploy();

  const MyToken = await ethers.getContractFactory("MyToken");
  mockWBTC = await MyToken.deploy("Mock WBTC", "mWBTC", 8, 21000000);
  mockUSDC = await MyToken.deploy("Mock USDC", "mUSDC", 6, 10000000000);
  mockSHIB = await MyToken.deploy("Mock SHIB", "mSHIB", 18, 999992012570472);
  console.log("mockWETH:", mockWETH.address);
  console.log("mockWBTC:", mockWBTC.address);
  console.log("mockUSDC:", mockUSDC.address);
  console.log("mockSHIB:", mockSHIB.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, mockWETH.address, "Mock WBTC", "mWBTC", 8, 21000000);
}

async function checkMarginHash() {
  

  // let baseTokenAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44"; // mockWETH in testnet
  // let quoteTokenAddress = "0x79dCF515aA18399CF8fAda58720FAfBB1043c526"; // mockUSDC in testnet



  // console.log("begin to deploy pair of EHT-USDC" );
  // await pairFactory.createPair(baseTokenAddress, quoteTokenAddress);
  // ammAddress = await pairFactory.getAmm(baseTokenAddress, quoteTokenAddress);
  // marginAddress = await pairFactory.getMargin(baseTokenAddress, quoteTokenAddress);

  // console.log("Amm:", ammAddress);
  // console.log("Margin:", marginAddress);

  let marginBytecode1 =  await pairFactory.marginBytecode();
  console.log("marginBytecode after:", ethers.utils.sha256(marginBytecode1));

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

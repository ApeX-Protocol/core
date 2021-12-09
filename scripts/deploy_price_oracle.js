const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");
const verifyStr = "npx hardhat verify --network";

let v3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; // UniswapV3Factory address
let v2FactoryAddress = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4"; // SushiV2Factory address
let wethAddress = "0xc778417E063141139Fce010982780140Aa0cD5Ab";
let mockWBTC;
let mockUSDC;
let apeXToken;
let priceOracle;

const main = async () => {
  await createMockTokens();
  await createApeXToken();
  await createPriceOracle();

  // await checkPriceOracle();
};

async function createMockTokens() {
  const MyToken = await ethers.getContractFactory("MyToken");
  mockWBTC = await MyToken.deploy("Mock WBTC", "mWBTC", 8, 100000000);
  mockUSDC = await MyToken.deploy("Mock USDC", "mUSDC", 6, 100000000);
  console.log("mockWBTC:", mockWBTC.address);
  console.log("mockUSDC:", mockUSDC.address);
}

async function createApeXToken() {
  const ApeXToken = await ethers.getContractFactory("ApeXToken");
  apeXToken = await ApeXToken.deploy();
  console.log("apeXToken:", apeXToken.address);
  console.log(verifyStr, process.env.HARDHAT_NETWORK, apeXToken.address);
}

async function createPriceOracle() {
  const PriceOracle = await ethers.getContractFactory("PriceOracle");
  priceOracle = await PriceOracle.deploy(v3FactoryAddress, v2FactoryAddress, wethAddress);
  console.log("PriceOracle:", priceOracle.address);
  console.log(
    verifyStr,
    process.env.HARDHAT_NETWORK,
    priceOracle.address,
    v3FactoryAddress,
    v2FactoryAddress,
    wethAddress
  );
}

/// need add liquidity to UniswapV3 & SushiSwap
async function checkPriceOracle() {
  let mWBTCAddress = "0x7aBF19CE8696A1D8945F9125758EbCe2F6F0Fd91";
  let mUSDCAddress = "0x1b3631A99A69275bC7E3b539FeD4DaAFaDDfe1B0";
  let apeXAddress = "0x94aD21Bf72F0f4ab545E59ea3d5C1F863d74C629";
  let priceOracleAddress = "0x3a62F3b224Dfe5E13dfa360D1E03aE32191bF091";
  const PriceOracle = await ethers.getContractFactory("PriceOracle");
  priceOracle = await PriceOracle.attach(priceOracleAddress);

  let usdcAmount = await priceOracle.quoteFromV3(mWBTCAddress, mUSDCAddress, 1000);
  console.log("usdcAmount:", usdcAmount.toNumber());

  let apeXAmount = await priceOracle.quoteFromV2(mUSDCAddress, apeXAddress, 1000);
  console.log("apeXAmount:", apeXAmount.toNumber());

  let wbtcAmount = await priceOracle.quoteFromHybrid(mWBTCAddress, apeXAddress, 10);
  console.log("wbtcAmount:", BigNumber.from(wbtcAmount).toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

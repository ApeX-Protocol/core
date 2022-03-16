const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");

let signer;
let esApeX;
let veApeX;
let apeXPool;
let slpPool;
let stakingPoolTemplate;
let stakingPoolFactory;

let apeXTokenAddress = "0x851356ae760d987E095750cCeb3bC6014560891C";
let slpTokenAddress = "0xf5059a5D33d5853360D16C683c16e67980206f36";
let stakingPoolFactoryAddress = "0xAA292E8611aDF267e563f334Ee42320aC96D0463";
let apeXPoolAddress = "0x720472c8ce72c2A2D711333e064ABD3E6BbEAdd3";
let slpPoolAddress = "0x74fcA3bE84BBd0bAE9C973Ca2d16821FEa867fE8";
let esApeXAddress = "0xe8D2A1E88c91DCd5433208d4152Cc4F399a7e91d";
let veApeXAddress = "0x5067457698Fd6Fa1C6964e416b3f42713513B3dD";

let treasury = "0xba5129359491007F82C79C4e1f322B6341C28D8F";
const apeXAmountForStaking = BigNumber.from("3000000000000000000000000");
let apeXPerSec = BigNumber.from("82028346620490110");
let secSpanPerUpdate = 1209600; //two weeks
let initTimestamp = 1641781192;
let endTimestamp = 1673288342; //one year after init time
let apeXPoolWeight = 21;
let slpPoolWeight = 79;
let sixMonth = 15552000;
let remainForOtherVest = 50;
let minRemainRatioAfterBurn = 6000;

const main = async () => {
  // await mockTokens();
  // await createContracts();
  await flow();
};

async function mockTokens() {
  [signer] = await hre.ethers.getSigners();
  const MockToken = await ethers.getContractFactory("MockToken");
  let apeXToken = await MockToken.deploy("apeX Token", "apeX");
  console.log(`let apeXTokenAddress = "${apeXToken.address}"`);

  let slpToken = await MockToken.deploy("slp token", "slp");
  console.log(`let slpTokenAddress = "${slpToken.address}"`);

  await apeXToken.mint(signer.address, 10000);
  console.log((await apeXToken.balanceOf(signer.address)).toNumber());
}

async function createContracts() {
  [signer] = await hre.ethers.getSigners();
  const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
  const StakingPool = await ethers.getContractFactory("StakingPool");
  const ApeXPool = await ethers.getContractFactory("ApeXPool");
  const EsAPEX = await ethers.getContractFactory("EsAPEX");
  const VeAPEX = await ethers.getContractFactory("VeAPEX");

  stakingPoolTemplate = await StakingPool.deploy();
  stakingPoolFactory = await StakingPoolFactory.deploy();
  await stakingPoolFactory.initialize(
    apeXTokenAddress,
    treasury,
    apeXPerSec,
    secSpanPerUpdate,
    initTimestamp,
    endTimestamp,
    sixMonth
  );
  apeXPool = await ApeXPool.deploy(stakingPoolFactory.address, apeXTokenAddress);
  esApeX = await EsAPEX.deploy(stakingPoolFactory.address);
  veApeX = await VeAPEX.deploy(stakingPoolFactory.address);

  await stakingPoolFactory.setRemainForOtherVest(remainForOtherVest);
  await stakingPoolFactory.setMinRemainRatioAfterBurn(minRemainRatioAfterBurn);
  await stakingPoolFactory.setEsApeX(esApeX.address);
  await stakingPoolFactory.setVeApeX(veApeX.address);
  await stakingPoolFactory.setStakingPoolTemplate(stakingPoolTemplate.address);

  await stakingPoolFactory.registerApeXPool(apeXPool.address, apeXPoolWeight);
  await stakingPoolFactory.createPool(slpTokenAddress, slpPoolWeight);
  slpPool = StakingPool.attach(await stakingPoolFactory.tokenPoolMap(slpTokenAddress));

  console.log(`let stakingPoolFactoryAddress = "${stakingPoolFactory.address}"`);
  console.log(`let apeXPoolAddress = "${apeXPool.address}"`);
  console.log(`let slpPoolAddress = "${slpPool.address}"`);
  console.log(`let esApeXAddress = "${esApeX.address}"`);
  console.log(`let veApeXAddress = "${veApeX.address}"`);
}

async function flow() {
  [signer] = await hre.ethers.getSigners();
  const MockToken = await ethers.getContractFactory("MockToken");
  const EsAPEX = await ethers.getContractFactory("EsAPEX");
  const VeAPEX = await ethers.getContractFactory("VeAPEX");
  const StakingPoolFactory = await ethers.getContractFactory("StakingPoolFactory");
  const StakingPool = await ethers.getContractFactory("StakingPool");

  stakingPoolFactory = StakingPoolFactory.attach(stakingPoolFactoryAddress);
  apeXPool = StakingPool.attach(apeXPoolAddress);
  slpPool = StakingPool.attach(slpPoolAddress);

  apeXToken = MockToken.attach(apeXTokenAddress);
  slpToken = MockToken.attach(slpTokenAddress);

  esApeX = EsAPEX.attach(esApeXAddress);
  veApeX = VeAPEX.attach(veApeXAddress);

  await apeXToken.mint(stakingPoolFactory.address, apeXAmountForStaking);
  await slpToken.mint(signer.address, 1000000000000);
  await slpToken.approve(slpPool.address, 1000000000000);
  await apeXToken.mint(signer.address, 10000);
  await apeXToken.approve(apeXPool.address, 10000);

  console.log("before claim: ", (await esApeX.balanceOf(signer.address)).toString());
  await slpPool.stake(10000, 0);
  await slpPool.processRewards();
  await stakingPoolFactory.changePoolWeight(apeXPool.address, 22);
  await apeXPool.stake(10000, 0);
  await apeXPool.processRewards();
  console.log("after claim: ", (await esApeX.balanceOf(signer.address)).toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

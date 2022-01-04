const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");

let apeXAddress = "0x4eB450a1f458cb60fc42B915151E825734d06dd8";
let wethAddress = "0x655e2b2244934Aea3457E3C56a7438C271778D44";
let factoryAddress = "0x9ef193943E14D83BcdAD9e3d782DBafA93bd25A1";
let routerAddress = "0xF18B7247Da6883896Ce2C79FD5AA2E5955498f7b";

let apeX;
let weth;
let factory;

const main = async () => {
    // const UniswapV2Factory = await ethers.getContractFactory("IUniswapV2Factory");
    // factory = await UniswapV2Factory.attach(factoryAddress);

    const ApeXToken = await ethers.getContractFactory("ApeXToken");
    apeX = await ApeXToken.attach(apeXAddress);

    const WETH = await ethers.getContractFactory("MockWETH");
    weth = await WETH.attach(wethAddress);

    await approve();
};

async function approve() {
    await apeX.approve(routerAddress, BigNumber.from("1000000000000000000000000000000000000").toString());
    await weth.approve(routerAddress, BigNumber.from("1000000000000000000000000000000000000").toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
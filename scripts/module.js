const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");

let test = "0xAD3A45194eC873d8d6ED908590CF59F7309d6a5f";
let exp1 = ethers.BigNumber.from("10").pow(18);

async function deploy(name, ...params) {
  const Contract = await ethers.getContractFactory(name);
  return await Contract.deploy(...params).then((f) => f.deployed());
}


const main = async () => {
 
  const accounts = await hre.ethers.getSigners();
  signer = accounts[0].address;
  console.log("signer: ", signer.address);

  [owner, addr1, liquidator, ...addrs] = await ethers.getSigners();
  erc20 = await deploy("MyToken", "AAA token", "BBB", 18, 100000000);
  await erc20.transfer(test, ethers.BigNumber.from(100000000).mul(exp1));
  
  console.log("owner:", owner.address);
  

};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

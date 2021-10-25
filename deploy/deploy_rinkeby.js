const { ethers } = require('hardhat')
const { expect } = require('chai')

async function main() {
    const [deployer] = await ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);

    const Config = await ethers.getContractFactory("Config");
    const config = await Config.deploy();
    console.log("config address: ", config.address)

    const Factory = await ethers.getContractFactory("Factory");
    const factory = await Factory.deploy(config.address);
    console.log("factory address: ", factory.address)
}
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
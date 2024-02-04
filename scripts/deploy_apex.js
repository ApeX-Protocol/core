const {
    ethers
} = require("hardhat");
const verifyStr = "npx hardhat verify --network";

const main = async () => {
    const ApexToken = await ethers.getContractFactory("ApeXToken");
    let apexToken = await ApexToken.deploy();
    console.log("ApexToken:", apexToken.address);
    console.log(verifyStr, process.env.HARDHAT_NETWORK);
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

const {
    ethers,hre
} = require("hardhat");
const verifyStr = "npx hardhat verify --network";

const l2Bridge = "0x4200000000000000000000000000000000000010";
const l1Address = "0x52A8845DF664D76C69d2EEa607CD793565aF42B8";
const name = "ApeX Token";
const symbol = "APEX";
const decimals = 18;

const main = async () => {
    const [owner] = await ethers.getSigners();
    console.log("owner:", owner.address);

    const ApexToken = await ethers.getContractFactory("ApeXTokenMantle");
    let apexToken = await ApexToken.deploy(
        l2Bridge,
        l1Address,
        name,
        symbol,
        decimals
    );
    console.log("ApexToken:", apexToken.address);
    console.log(verifyStr, process.env.HARDHAT_NETWORK);
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

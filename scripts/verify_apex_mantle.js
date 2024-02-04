const {
    ethers
} = require("hardhat");

const apexMantleToken = "0x96630b0D78d29E7E8d87f8703dE7c14b2d5AE413";

const l2Bridge = "0x4200000000000000000000000000000000000010";
const l1Address = "0x52A8845DF664D76C69d2EEa607CD793565aF42B8";
const name = "ApeX Token";
const symbol = "APEX";
const decimals = 18;

const main = async () => {
    await hre.run("verify:verify", {
        address: apexMantleToken,
        contract: "contracts/token/ApeXTokenMantle.sol:ApeXTokenMantle",
        constructorArguments: [
            l2Bridge,
            l1Address,
            name,
            symbol,
            decimals
        ],
    });
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

const {
    ethers
} = require("hardhat");

const apexToken = "0x6fDd9fa8237883de7c2ebC6908Ab9e243600567E";

const main = async () => {
    await hre.run("verify:verify", {
        address: apexToken,
        contract: "contracts/token/ApeXToken.sol:ApeXToken",
        constructorArguments: [
        ],
    });
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

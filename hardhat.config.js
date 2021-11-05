/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require("dotenv").config();
require("hardhat-deploy");
require("@nomiclabs/hardhat-waffle");
require("hardhat-watcher");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },

  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    l1rinkeby: {
      url: `https://rinkeby.infura.io/v3/` + process.env["INFURA_KEY"],
      chainId: 4,
      accounts: [process.env["DEVNET_PRIVKEY"]],
    },
    l2rinkeby: {
      gasPrice: 0,
      url: process.env["L2RPC"] || "",
      accounts: [process.env["DEVNET_PRIVKEY"]],
    },
    localhost: {
      url: "http://localhost:8545",
    },
  },
  etherscan: {
    apiKey: process.env["ETHERSCAN_APIKEY"],
  },
  watcher: {
    compilation: {
      tasks: ["compile"],
    },
    test: {
      tasks: ["test"],
      files: ["./test/*"],
    },
  },
};

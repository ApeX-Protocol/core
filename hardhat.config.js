require("dotenv").config();
require("hardhat-deploy");
require("@nomiclabs/hardhat-waffle");
require("hardhat-watcher");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("@openzeppelin/hardhat-upgrades");

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.2",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  mocha: {
    timeout: 600000,
  },

  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    localhost: {
      url: "http://localhost:8545",
    },
    mainnet: {
      url: process.env.MAINNET_RPC,
      accounts: process.env.DEVNET_PRIVKEY !== undefined ? [process.env.DEVNET_PRIVKEY] : [],
    },
    rinkeby: {
      url: process.env.RINKEBY_RPC,
      accounts: process.env.DEVNET_PRIVKEY !== undefined ? [process.env.DEVNET_PRIVKEY] : [],
    },
    arbitrumOne: {
      url: process.env.ARBITRUM_ONE_RPC,
      accounts: process.env.DEVNET_PRIVKEY !== undefined ? [process.env.DEVNET_PRIVKEY] : [],
    },
    arbitrumTestnet: {
      url: process.env.ARBITRUM_TESTNET_RPC,
      accounts: process.env.DEVNET_PRIVKEY !== undefined ? [process.env.DEVNET_PRIVKEY] : [],
    },
    bscMainnet: {
      url: process.env.BSC_MAINNET_PRC,
      accounts: process.env.DEVNET_PRIVKEY !== undefined ? [process.env.DEVNET_PRIVKEY] : [],
    },
    bscTestnet: {
      url: process.env.BSC_TESTNET_PRC,
      accounts: process.env.DEVNET_PRIVKEY !== undefined ? [process.env.DEVNET_PRIVKEY] : [],
    },
  },
  etherscan: {
    apiKey: process.env.ARBISCAN_API_KEY,
    // apiKey: {
    //   mainnet: process.env.ETHERSCAN_API_KEY,
    //   rinkeby: process.env.ETHERSCAN_API_KEY,
    //   // arbitrum
    //   arbitrumOne: process.env.ARBISCAN_API_KEY,
    //   arbitrumTestnet: process.env.ARBISCAN_API_KEY,
    // },
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

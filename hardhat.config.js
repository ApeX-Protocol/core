/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('dotenv').config()
require('hardhat-deploy');
require("@nomiclabs/hardhat-waffle");
require("hardhat-watcher");
require('@nomiclabs/hardhat-ethers')
require("@nomiclabs/hardhat-etherscan");
module.exports = {
  solidity: "0.8.0",
  networks: {
    kovan: {
      url: `https://kovan.infura.io/v3/` + process.env['INFURA_KEY'],
      chainId: 42,
      accounts: [process.env['DEVNET_PRIVKEY']],
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/` + process.env['INFURA_KEY'],
      chainId: 4,
      accounts: [process.env['DEVNET_PRIVKEY']],
    },
    l1: {
      url: process.env['L1RPC'] || '',
      accounts: [process.env['DEVNET_PRIVKEY']],
    },
    l2: {
      gasPrice: 0,
      url: process.env['L2RPC'] || '',
      accounts: [process.env['DEVNET_PRIVKEY']],
    },
  },
  etherscan: {
    apiKey: process.env['ETHERSCAN_APIKEY']
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


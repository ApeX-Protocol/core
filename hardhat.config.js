/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require("@nomiclabs/hardhat-waffle");
require("hardhat-watcher");
module.exports = {
  solidity: "0.8.0",
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

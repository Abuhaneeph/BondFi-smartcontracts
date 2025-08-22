require("@nomicfoundation/hardhat-toolbox");
const { vars } = require("hardhat/config"); 

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true, // Fix for stack too deep
    },
  },
  networks: {
    liskSepolia: {
      url: "https://rpc.sepolia-api.lisk.com",
      accounts: [vars.get("PRIVATE_KEY")],
    },
    mantleSepolia: {
      url: "https://rpc.sepolia.mantle.xyz",
      accounts: [vars.get("PRIVATE_KEY")],
    },
  },
};

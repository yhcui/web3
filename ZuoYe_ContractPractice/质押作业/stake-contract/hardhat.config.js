require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();
require("hardhat-deploy");
require("@openzeppelin/hardhat-upgrades");
require("solidity-coverage");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        version: "0.8.22",
        settings: {
            optimizer: {
                enabled: false,
                runs: 200
            }
        }
    },
    namedAccounts: {
        deployer: {
            default: 0
        },
        user1: {
            default: 1
        },
        user2: {
            default: 2
        }
    }
};

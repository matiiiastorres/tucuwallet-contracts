import { defineConfig } from "hardhat/config";
import hardhatUpgrades from "@openzeppelin/hardhat-upgrades";

export default defineConfig({
  plugins: [hardhatUpgrades],
  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: {
          evmVersion: "shanghai",
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.8.36",
        settings: {
          evmVersion: "cancun",
          viaIR: false,
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ],
    overrides: {
      "src/RewardsDistributorV2.sol": {
        version: "0.8.36",
        settings: {
          evmVersion: "cancun",
          viaIR: false,
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    }
  },
  paths: {
    sources: "./src",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  networks: {
    worldchainFork: {
      type: "edr-simulated",
      chainType: "op",
      chainId: 480,
      forking: {
        url: "https://worldchain-mainnet.g.alchemy.com/public"
      }
    },
    worldchain: {
      type: "http",
      chainType: "op",
      chainId: 480,
      url: "https://worldchain-mainnet.g.alchemy.com/public",
      accounts: process.env.TUCU_DEPLOYER_PRIVATE_KEY
        ? [process.env.TUCU_DEPLOYER_PRIVATE_KEY]
        : []
    }
  }
});

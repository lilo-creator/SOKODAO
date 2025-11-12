import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable, defineConfig } from "hardhat/config";

import hardhatVerify from "@nomicfoundation/hardhat-verify";
import hardhatViem from "@nomicfoundation/hardhat-viem";

import * as dotenv from "dotenv";

dotenv.config(); // load .env variables
export default defineConfig({
 plugins: [hardhatVerify, hardhatViem, hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("PRIVATE_KEY")],
    },
  },
verify: {
    etherscan: {
      apiKey: configVariable("ETHERSCAN_API_KEY") || "",
    },
  },
});

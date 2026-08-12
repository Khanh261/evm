import { defineConfig } from "hardhat/config";
import hardhatIgnition from "@nomicfoundation/hardhat-ignition";
import hardhatIgnitionEthers from "@nomicfoundation/hardhat-ignition-ethers";

const dev0PrivateKey =
  process.env.PRIVATE_KEY ||
  // Public local-node dev0 key from ../local_node.sh. Do not use on public networks.
  "0x88cbead91aee890d27bf06e003ade3d4e952427e88f88d31d61d3ef5e5d54305"; // gitleaks:allow

export default defineConfig({
  plugins: [hardhatIgnition, hardhatIgnitionEthers],
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 100,
          },
          viaIR: true,
        },
      },
      // This version is required to compile the werc9 contract.
      {
        version: "0.4.22",
      },
    ],
  },
  paths: { sources: "./solidity/deploy" },
  networks: {
    validator: {
      type: "http",
      chainType: "l1",
      url: process.env.VALIDATOR_RPC_URL || "http://10.2.12.177:8545",
      accounts: process.env.VALIDATOR_PRIVATE_KEY
        ? [process.env.VALIDATOR_PRIVATE_KEY]
        : [dev0PrivateKey],
      chainId: Number(process.env.CHAIN_ID || 262144),
    },
  },
});

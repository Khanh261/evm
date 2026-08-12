// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IChainInfo {
    // This tells Hardhat how to talk to the Go precompile
    function getCosmosBlockHeight() external view returns (uint256);
}

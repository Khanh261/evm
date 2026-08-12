// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IChainInfo.sol";

contract MyDapp {
    // The exact address we hardcoded in the Go file
    address constant PRECOMPILE_ADDR = 0x0000000000000000000000000000000000000999;

    function checkNativeHeight() public view returns (uint256) {
        // Calls the Go code and returns the result!
        return IChainInfo(PRECOMPILE_ADDR).getCosmosBlockHeight();
    }
}

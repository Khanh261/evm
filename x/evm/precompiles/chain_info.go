package chaininfo

import (
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/vm"
)

// 1. Define the hardcoded address for our precompile (0x...999)
var PrecompileAddress = common.HexToAddress("0x0000000000000000000000000000000000000999")

// 2. Define the Precompile Struct
type ChainInfoPrecompile struct{}

// 3. Define the Gas Cost (Fixed at 1000 gas)
func (p *ChainInfoPrecompile) RequiredGas(input []byte) uint64 {
	return 1000
}

// 4. Define the Execution Logic
func (p *ChainInfoPrecompile) Run(evm *vm.EVM, contract *vm.Contract, readonly bool) ([]byte, error) {
	// Grab the current Native L1 Block Number directly from the context
	var blockHeight *big.Int = evm.Context.BlockNumber

	// EVM requires all returned data to be 32-bytes long
	// We pad the block height and return it directly to the smart contract
	return common.LeftPadBytes(blockHeight.Bytes(), 32), nil
}
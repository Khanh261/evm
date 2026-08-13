package precompile

import (
	"bytes"
	_ "embed"
	"fmt"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/vm"

	cmn "github.com/cosmos/evm/precompiles/common"
	"github.com/cosmos/evm/x/validatorgroup/keeper"

	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
)

var (
	PrecompileAddress = common.HexToAddress("0x0000000000000000000000000000000000000808")
)

//go:embed abi.json
var abiJSON []byte

// Precompile implements the validator group admin control precompile
type Precompile struct {
	cmn.Precompile
	abi      abi.ABI
	vgKeeper keeper.Keeper
}

// NewPrecompile creates a new validator group precompile instance
func NewPrecompile(vg keeper.Keeper) *Precompile {
	parsedABI, err := abi.JSON(bytes.NewReader(abiJSON))
	if err != nil {
		panic(err)
	}

	p := &Precompile{
		Precompile: cmn.Precompile{
			KvGasConfig:          storetypes.GasConfig{},
			TransientKVGasConfig: storetypes.GasConfig{},
			ContractAddress:      PrecompileAddress,
		},
		abi:      parsedABI,
		vgKeeper: vg,
	}
	return p
}

// Name returns the precompile name
func (p Precompile) Name() string { return "validatorgroup" }

// Address returns the precompile address
func (p Precompile) Address() common.Address { return p.ContractAddress }

// RequiredGas implements the vm.PrecompiledContract interface
func (p Precompile) RequiredGas(input []byte) uint64 {
	// Treat all calls as reads or writes with small fixed gas
	if len(input) < 4 {
		return 0
	}
	methodID := input[:4]
	// cheap base value
	_ = methodID
	return 1000
}

// Run executes the precompile logic
func (p Precompile) Run(evm *vm.EVM, contract *vm.Contract, readonly bool) ([]byte, error) {
	return p.Precompile.RunNativeAction(evm, contract, func(ctx sdk.Context) ([]byte, error) {
		method, args, err := cmn.SetupABI(p.abi, contract, readonly, func(m *abi.Method) bool {
			return !(m.StateMutability == "view" || m.StateMutability == "pure")
		})
		if err != nil {
			return nil, err
		}

		switch method.Name {
		case "admin":
			admin := p.vgKeeper.GetAdmin(ctx)
			if admin == nil {
				return method.Outputs.Pack(common.Address{})
			}
			return method.Outputs.Pack(common.BytesToAddress(admin.Bytes()))
		case "addValidatorAddress":
			if err := p.requireAdmin(ctx, contract); err != nil {
				return nil, err
			}
			valAddr, err := unpackValidatorAddress(args)
			if err != nil {
				return nil, err
			}
			p.vgKeeper.AddValidator(ctx, valAddr)
			return method.Outputs.Pack(true)
		case "removeValidatorAddress":
			if err := p.requireAdmin(ctx, contract); err != nil {
				return nil, err
			}
			valAddr, err := unpackValidatorAddress(args)
			if err != nil {
				return nil, err
			}
			p.vgKeeper.RemoveValidator(ctx, valAddr)
			return method.Outputs.Pack(true)
		case "isWhitelisted":
			valAddr, err := unpackValidatorAddress(args)
			if err != nil {
				return nil, err
			}
			ok := p.vgKeeper.IsWhitelisted(ctx, valAddr)
			return method.Outputs.Pack(ok)
		default:
			return nil, vm.ErrExecutionReverted
		}
	})
}

func (p Precompile) requireAdmin(ctx sdk.Context, contract *vm.Contract) error {
	caller := sdk.AccAddress(contract.Caller().Bytes())
	if !p.vgKeeper.IsAdmin(ctx, caller) {
		return fmt.Errorf("caller is not validatorgroup admin")
	}
	return nil
}

func unpackValidatorAddress(args []interface{}) (sdk.ValAddress, error) {
	if len(args) < 1 {
		return nil, fmt.Errorf("missing arg")
	}

	addr, ok := args[0].(common.Address)
	if !ok {
		return nil, fmt.Errorf("invalid address type: %T", args[0])
	}

	return sdk.ValAddress(addr.Bytes()), nil
}

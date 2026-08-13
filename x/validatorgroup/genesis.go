package validatorgroup

import (
	"fmt"

	"github.com/ethereum/go-ethereum/common"

	"github.com/cosmos/evm/x/validatorgroup/keeper"
	"github.com/cosmos/evm/x/validatorgroup/types"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

func InitGenesis(ctx sdk.Context, k keeper.Keeper, data types.GenesisState) {
	if data.Admin != "" {
		admin := common.HexToAddress(data.Admin)
		k.SetAdmin(ctx, sdk.AccAddress(admin.Bytes()))
	}

	for _, validator := range data.Validators {
		valAddr, err := parseValidatorAddress(validator)
		if err != nil {
			panic(err)
		}
		k.AddValidator(ctx, valAddr)
	}
}

func ExportGenesis(ctx sdk.Context, k keeper.Keeper) *types.GenesisState {
	gs := types.DefaultGenesisState()

	admin := k.GetAdmin(ctx)
	if admin != nil {
		gs.Admin = common.BytesToAddress(admin.Bytes()).Hex()
	}

	k.IterateWhitelistedValidators(ctx, func(valAddr sdk.ValAddress) bool {
		gs.Validators = append(gs.Validators, common.BytesToAddress(valAddr.Bytes()).Hex())
		return false
	})

	return gs
}

func parseValidatorAddress(address string) (sdk.ValAddress, error) {
	if common.IsHexAddress(address) {
		return sdk.ValAddress(common.HexToAddress(address).Bytes()), nil
	}

	valAddr, err := sdk.ValAddressFromBech32(address)
	if err != nil {
		return nil, fmt.Errorf("invalid validator address %s: %w", address, err)
	}

	return valAddr, nil
}

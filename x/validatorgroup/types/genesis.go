package types

import (
	"fmt"

	"github.com/ethereum/go-ethereum/common"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

type GenesisState struct {
	Admin      string   `json:"admin"`
	Validators []string `json:"validators"`
}

func DefaultGenesisState() *GenesisState {
	return &GenesisState{
		Admin:      "",
		Validators: []string{},
	}
}

func NewGenesisState(admin string, validators []string) *GenesisState {
	return &GenesisState{
		Admin:      admin,
		Validators: validators,
	}
}

func (gs GenesisState) Validate() error {
	if gs.Admin != "" && !common.IsHexAddress(gs.Admin) {
		return fmt.Errorf("invalid admin address: %s", gs.Admin)
	}

	seen := make(map[string]struct{}, len(gs.Validators))
	for _, validator := range gs.Validators {
		if _, ok := seen[validator]; ok {
			return fmt.Errorf("duplicated validator address: %s", validator)
		}
		seen[validator] = struct{}{}

		if common.IsHexAddress(validator) {
			continue
		}
		if _, err := sdk.ValAddressFromBech32(validator); err != nil {
			return fmt.Errorf("invalid validator address %s: %w", validator, err)
		}
	}

	return nil
}

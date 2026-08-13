package types

import sdk "github.com/cosmos/cosmos-sdk/types"

const (
	ModuleName = "validatorgroup"
	StoreKey   = ModuleName
)

var (
	AdminKey           = []byte{0x01}
	WhitelistKeyPrefix = []byte{0x02}
)

func GetWhitelistKey(valAddr sdk.ValAddress) []byte {
	return append(WhitelistKeyPrefix, valAddr.Bytes()...)
}

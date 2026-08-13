package keeper

import (
	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/cosmos/evm/x/validatorgroup/types"
)

// Keeper maintains the validatorgroup store
type Keeper struct {
	storeKey storetypes.StoreKey
}

// NewKeeper creates a new keeper instance
func NewKeeper(storeKey storetypes.StoreKey) Keeper {
	return Keeper{storeKey: storeKey}
}

// SetAdmin stores the EVM address that can manage the validator whitelist.
func (k Keeper) SetAdmin(ctx sdk.Context, admin sdk.AccAddress) {
	store := ctx.KVStore(k.storeKey)
	store.Set(types.AdminKey, admin.Bytes())
}

// GetAdmin returns the stored whitelist admin.
func (k Keeper) GetAdmin(ctx sdk.Context) sdk.AccAddress {
	store := ctx.KVStore(k.storeKey)
	bz := store.Get(types.AdminKey)
	if len(bz) == 0 {
		return nil
	}

	return sdk.AccAddress(bz)
}

// IsAdmin checks whether the provided EVM address is the configured admin.
func (k Keeper) IsAdmin(ctx sdk.Context, addr sdk.AccAddress) bool {
	admin := k.GetAdmin(ctx)
	return admin != nil && admin.Equals(addr)
}

// AddValidator adds an address to the approved organization list
func (k Keeper) AddValidator(ctx sdk.Context, valAddr sdk.ValAddress) {
	store := ctx.KVStore(k.storeKey)
	store.Set(types.GetWhitelistKey(valAddr), []byte{1})
}

// RemoveValidator revokes an address from the approved list
func (k Keeper) RemoveValidator(ctx sdk.Context, valAddr sdk.ValAddress) {
	store := ctx.KVStore(k.storeKey)
	store.Delete(types.GetWhitelistKey(valAddr))
}

// IsWhitelisted checks if an address is permitted to be a validator
func (k Keeper) IsWhitelisted(ctx sdk.Context, valAddr sdk.ValAddress) bool {
	store := ctx.KVStore(k.storeKey)
	return store.Has(types.GetWhitelistKey(valAddr))
}

func (k Keeper) IterateWhitelistedValidators(ctx sdk.Context, cb func(sdk.ValAddress) bool) {
	store := ctx.KVStore(k.storeKey)
	iterator := storetypes.KVStorePrefixIterator(store, types.WhitelistKeyPrefix)
	defer iterator.Close()

	for ; iterator.Valid(); iterator.Next() {
		key := iterator.Key()
		valAddr := sdk.ValAddress(key[len(types.WhitelistKeyPrefix):])
		if cb(valAddr) {
			break
		}
	}
}

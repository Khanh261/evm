package ante

import (
	sdk "github.com/cosmos/cosmos-sdk/types"
	errorsmod "cosmossdk.io/errors"
	errortypes "github.com/cosmos/cosmos-sdk/types/errors"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"
)

type Keeper interface {
	IsWhitelisted(ctx sdk.Context, valAddr sdk.ValAddress) bool
}

type PermissionedValidatorDecorator struct {
	vgKeeper Keeper
}

func NewPermissionedValidatorDecorator(k Keeper) PermissionedValidatorDecorator {
	return PermissionedValidatorDecorator{vgKeeper: k}
}

func (pvd PermissionedValidatorDecorator) AnteHandle(
	ctx sdk.Context,
	tx sdk.Tx,
	simulate bool,
	next sdk.AnteHandler,
) (newCtx sdk.Context, err error) {

	for _, msg := range tx.GetMsgs() {
		// Intercept any attempt to create a validator
		if createValMsg, ok := msg.(*stakingtypes.MsgCreateValidator); ok {
			valAddr, err := sdk.ValAddressFromBech32(createValMsg.ValidatorAddress)
			if err != nil {
				return ctx, err
			}

			// Reject if the address is not in your organization's whitelist
			if !pvd.vgKeeper.IsWhitelisted(ctx, valAddr) {
				return ctx, errorsmod.Wrap(
					errortypes.ErrUnauthorized,
					"validator address is not authorized in organization whitelist",
				)
			}
		}
	}

	return next(ctx, tx, simulate)
}

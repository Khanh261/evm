# validatorgroup admin workflow

Scripts for managing the `validatorgroup` module's whitelist precompile
(`0x0000000000000000000000000000000000000808`). Covers first-time node
setup and day-to-day admin operations.

The same guide is also available as a formatted page:
[`docs/validatorgroup-runbook.html`](../docs/validatorgroup-runbook.html)
(open it in a browser). Keep the two in sync when editing.

## The one rule that matters

`validatorgroup.InitGenesis` (and every other module's `InitGenesis`) only
runs **once**, at chain height 0. Any edit to `genesis.json` — admin
address, validator whitelist, denom metadata, active precompiles — has
**no effect** unless followed by a full reset before the next start:

```bash
sudo systemctl stop evmd
evmd comet unsafe-reset-all --home ~/.evmd
sudo systemctl start evmd
```

Use `evmd comet unsafe-reset-all`, never a raw `rm -rf ~/.evmd/data` — the
raw wipe deletes `priv_validator_state.json` without regenerating it,
which crashes the node on the next start.

Runtime settings in `app.toml` / `config.toml` (JSON-RPC enable, bind
address, mempool type) are **not** genesis state — a plain restart picks
those up, no reset needed.

## Admin can only be set at genesis — there is no rotation path

`SetAdmin` is only ever called from `InitGenesis`
([genesis.go:14-18](../x/validatorgroup/genesis.go#L14-L18)). There is no
`Msg` service and no `setAdmin` precompile method — the module's `Run()`
switch only has `admin` (read), `addValidatorAddress`,
`removeValidatorAddress`, `isWhitelisted`
([precompile.go:80-116](../x/validatorgroup/precompile/precompile.go#L80-L116)).

That means once the chain has real history, **the admin address can
never be changed** — the only mechanism (`unsafe-reset-all` + re-edit
genesis) wipes all chain data, which is fine during dev setup but not an
option on a live chain. If admin rotation will ever be needed (lost key,
org handoff), add a `setAdmin(address)` precompile method gated by
`requireAdmin` (same pattern as `addValidatorAddress`) before going to
production — treat this as a blocker, not a nice-to-have.

---

## 1. First-time node setup

Only needed once, when bootstrapping a fresh chain.

```bash
evmd init my-validator --chain-id mytestnet_9000-1 --home ~/.evmd
evmd keys add validator --keyring-backend test --home ~/.evmd
evmd genesis add-genesis-account \
  $(evmd keys show validator -a --keyring-backend test --home ~/.evmd) \
  10000000000000000000000stake --keyring-backend test --home ~/.evmd
evmd genesis gentx validator 1000000000000000000stake \
  --chain-id mytestnet_9000-1 --keyring-backend test --home ~/.evmd
evmd genesis collect-gentxs --home ~/.evmd
```

### 1a. Genesis fixes required before the first start

All of these must be in place **before** the node's first `InitGenesis`
run, because none of them apply retroactively:

```bash
GENESIS=~/.evmd/config/genesis.json

# Set the module admin (prompts for the address if not passed as an argument)
./scripts/setup_admin.sh 0xYourAdminEvmAddress

# Whitelist the gentx validator(s), or InitGenesis will reject the gentx
# (the validatorgroup ante handler blocks MsgCreateValidator for anyone
# not already whitelisted — this runs even for genesis gentxs)
VAL_ADDR="cosmosvaloper1..."   # from `evmd keys show validator --bech val -a`
jq --arg val "$VAL_ADDR" '.app_state.validatorgroup.validators += [$val]' \
  "$GENESIS" > "$GENESIS.tmp" && mv "$GENESIS.tmp" "$GENESIS"

# Add bank denom_metadata for the EVM's evm_denom param
# (x/vm InitGenesis panics without this — "denom metadata X could not be found")
EVM_DENOM=$(jq -r '.app_state.evm.params.evm_denom' "$GENESIS")
DISPLAY_DENOM="display${EVM_DENOM}"
jq --arg base "$EVM_DENOM" --arg display "$DISPLAY_DENOM" '
  .app_state.bank.denom_metadata += [{
    description: ("Native denom metadata for " + $base),
    denom_units: [
      {denom: $base, exponent: 0, aliases: []},
      {denom: $display, exponent: 18, aliases: []}
    ],
    base: $base, display: $display, name: $base,
    symbol: ($base | ascii_upcase)
  }]' "$GENESIS" > "$GENESIS.tmp" && mv "$GENESIS.tmp" "$GENESIS"

# Activate the validatorgroup precompile (registered in code, but gated
# behind this genesis/governance param — off by default)
jq '.app_state.evm.params.active_static_precompiles +=
    ["0x0000000000000000000000000000000000000808"] |
    .app_state.evm.params.active_static_precompiles |= sort' \
  "$GENESIS" > "$GENESIS.tmp" && mv "$GENESIS.tmp" "$GENESIS"
```

### 1b. Node/service config (one-time per host)

```bash
# CometBFT mempool must be "app" when the EVM app-side mempool is enabled
sed -i '/^\[mempool\]/,/^\[/ s/^type = .*/type = "app"/' ~/.evmd/config/config.toml

# Enable the JSON-RPC server (off by default)
sed -i '/^\[json-rpc\]/,/^\[/ s/^enable = .*/enable = true/' ~/.evmd/config/app.toml
```

Systemd unit (`/etc/systemd/system/evmd.service`) — pass `--chain-id`
explicitly so startup never depends on `client.toml` having it set:

```
ExecStart=/home/ekoios/go/bin/evmd start --home /home/ekoios/.evmd --chain-id mytestnet_9000-1
```

```bash
sudo systemctl daemon-reload
```

### 1c. First start

```bash
sudo systemctl start evmd
sleep 5
sudo systemctl status evmd | cat
journalctl -u evmd -n 30 --no-pager | cat
```

Confirm it's healthy:

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545

export VALIDATOR_RPC_URL="http://127.0.0.1:8545"
./scripts/check_admin.sh
```

---

## 2. Expose RPC to other machines (optional)

Runtime config only — restart, no reset needed.

```bash
sudo systemctl stop evmd
sed -i 's|^address = "127.0.0.1:8545"|address = "0.0.0.0:8545"|' ~/.evmd/config/app.toml
sed -i 's|^ws-address = "127.0.0.1:8546"|ws-address = "0.0.0.0:8546"|' ~/.evmd/config/app.toml
sudo systemctl start evmd

# open the port — prefer scoping to a trusted subnet over a blanket allow
sudo ufw allow from <trusted-subnet-or-IP> to any port 8545 proto tcp
```

Binding to `0.0.0.0` exposes write methods like `eth_sendRawTransaction`
to anyone who can reach the port — don't do a blanket `ufw allow 8545/tcp`
on a box with any public exposure.

---

## 3. Day-2 admin operations

These are live transactions against the running chain — **no reset
required**, unlike section 1a.

Every script prompts for what it needs, so you can just run it:

```bash
./scripts/check_admin.sh        # who is admin?
./scripts/is_whitelisted.sh     # is an address in the group?
./scripts/add_validator.sh      # add to the whitelist (admin-only tx)
./scripts/remove_validator.sh   # remove from the whitelist (admin-only tx)
```

For example:

```
$ ./scripts/add_validator.sh
? RPC URL [http://127.0.0.1:8545]: http://10.2.12.177:8545
? Validator EVM address to ADD to the whitelist: 0x0466...aD33D
? Admin private key (hidden):
tx_hash: 0x...
```

Private key input is hidden — never echoed to the screen and never left
in shell history. EVM addresses are validated as you type.

`add_validator.sh` and `remove_validator.sh` guard against the ways this
precompile fails quietly:

- **No-op writes are refused.** `RemoveValidator` calls `store.Delete`
  unconditionally and the precompile returns `true` either way, so
  removing a non-whitelisted address (or adding an already-whitelisted
  one) *succeeds on-chain while changing nothing* — costing gas and
  reporting a misleading success. Both scripts check current state first
  and exit without sending a transaction.
- **Non-admin callers are caught before broadcasting.** Only the admin
  can modify the whitelist; anyone else gets a reverted transaction that
  still costs gas. The scripts compare the signer against `admin()` and
  refuse up front, naming both addresses.
- **The receipt is checked.** A mined transaction can still have
  reverted, so a printed `tx_hash` alone means nothing. Both scripts wait
  for the receipt, verify `status == 1`, then re-read the whitelist to
  confirm the state actually changed, ending with e.g.
  `confirmed: 0x... is now whitelisted (block 5523)`.

Anything supplied as an argument or environment variable skips its
prompt, so the old scripted form still works unchanged:

```bash
export VALIDATOR_RPC_URL="http://<node-ip>:8545"
export VALIDATOR_PRIVATE_KEY="<admin's EVM private key>"
./scripts/add_validator.sh 0xValidatorEvmAddress
./scripts/is_whitelisted.sh 0xValidatorEvmAddress
./scripts/remove_validator.sh 0xValidatorEvmAddress
```

When stdin isn't a terminal (CI, cron, piped input), a missing required
value is a clear error with exit code 2 rather than a hung prompt.

Note: `remove_validator.sh` only clears the whitelist entry. It does
**not** unbond or jail an already-active validator — the ante handler
only blocks *new* `MsgCreateValidator` calls. An already-bonded validator
keeps producing blocks and earning rewards after removal unless it's
separately unbonded.

---

## 4. Automated smoke test

`test_validatorgroup.sh` runs the whole cycle with real pass/fail
assertions: check admin → confirm target isn't already whitelisted → add →
confirm whitelisted → remove → confirm removed.

Run it with no arguments — it prompts for everything it needs:

```bash
./scripts/test_validatorgroup.sh
```

```
? RPC URL [http://127.0.0.1:8545]:
? Admin EVM address: 0x...
? Admin private key (hidden):
? Test validator EVM address (will be added, then removed): 0x...
```

The private key prompt is hidden (not echoed, not saved in shell
history). EVM addresses are validated as you type them.

The test address must **not** already be a real whitelisted validator —
the script aborts before touching anything if the pre-condition check
finds it's already in the group, since the test removes it at the end.

It also offers an optional set-admin step (`setup_admin.sh`). That one
runs `evmd comet unsafe-reset-all` and **wipes all chain history**, so
it's off unless you opt in and then type `RESET` to confirm. Only use it
against a fresh/disposable chain.

Setting the matching env vars (`VALIDATOR_RPC_URL`, `ADMIN_ADDR`,
`ADMIN_PRIVATE_KEY`, `TEST_VALIDATOR_ADDR`) pre-fills the prompts, and
lets the script run unattended in CI where stdin isn't a terminal.

---

## 5. Troubleshooting checklist

If `evmd start` exits with `status=1`, check `journalctl -u evmd -n 60
--no-pager | cat` for one of these, roughly in the order they tend to
surface on a fresh setup:

| Symptom | Fix |
|---|---|
| `comet-bft has invalid config.toml:mempool.type` | `config.toml` `[mempool] type` must be `"app"` |
| `invalid chain-id on InitChain; expected: ` | `--chain-id` missing from both the flag and `client.toml`; pin it in the systemd unit |
| `open .../priv_validator_state.json: no such file` | data dir was raw-deleted instead of reset; run `evmd comet unsafe-reset-all` |
| `error initializing evm coin info: denom metadata X could not be found` | missing `app_state.bank.denom_metadata` entry for `evm_denom` — see 1a |
| `validator address is not authorized in organization whitelist` (during gentx replay) | gentx validator address missing from `app_state.validatorgroup.validators` — see 1a |
| `check_admin.sh` → `Connection refused` | JSON-RPC `enable = false` in `app.toml` (the default) |
| `check_admin.sh` → `Could not transact with/call contract function` | precompile address missing from `app_state.evm.params.active_static_precompiles` — see 1a |

Any genesis-related fix from that table needs `evmd comet unsafe-reset-all`
+ restart to take effect. Runtime config fixes (mempool type, JSON-RPC
enable) just need a restart.

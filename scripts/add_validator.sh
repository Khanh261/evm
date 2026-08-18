#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_prompt.sh
source "$SCRIPT_DIR/_prompt.sh"

require_web3

ABI_PATH="$SCRIPT_DIR/../x/validatorgroup/precompile/abi.json"

TARGET="${1:-}"
prompt_value  VALIDATOR_RPC_URL     "RPC URL" "http://127.0.0.1:8545"
prompt_addr   TARGET                "Validator EVM address to ADD to the whitelist"
prompt_secret VALIDATOR_PRIVATE_KEY "Admin private key (hidden)"
RPC_URL="$VALIDATOR_RPC_URL"
export VALIDATOR_PRIVATE_KEY

if [[ ! -f "$ABI_PATH" ]]; then
  echo "ERROR: ABI not found at $ABI_PATH" >&2
  exit 2
fi

# try to run embedded Python that uses web3
python3 - <<PY
import os, sys, json
from web3 import Web3
rpc = "${RPC_URL}"
w3 = Web3(Web3.HTTPProvider(rpc))
abi = json.load(open('${ABI_PATH}'))
contract = w3.eth.contract(address=w3.to_checksum_address('0x0000000000000000000000000000000000000808'), abi=abi)
acct = w3.eth.account.from_key(os.environ['VALIDATOR_PRIVATE_KEY'])
target = w3.to_checksum_address('${TARGET}')

# Don't spend gas on a no-op: adding an already-whitelisted address
# succeeds on-chain but changes nothing.
if contract.functions.isWhitelisted(target).call():
    print(f"{target} is already whitelisted - nothing to do.")
    sys.exit(0)

# Only the admin can modify the whitelist; anyone else gets a reverted tx
# that still costs gas, so fail before broadcasting.
admin = contract.functions.admin().call()
if admin.lower() != acct.address.lower():
    print(f"ERROR: signer {acct.address} is not the validatorgroup admin ({admin}).", file=sys.stderr)
    print("The transaction would revert - not sending it.", file=sys.stderr)
    sys.exit(1)

nonce = w3.eth.get_transaction_count(acct.address)
tx = contract.functions.addValidatorAddress(target).build_transaction({
  'from': acct.address,
  'value': 0,
  'gas': 200000,
  'gasPrice': w3.eth.gas_price,
  'nonce': nonce,
})
signed = acct.sign_transaction(tx)
raw_tx = getattr(signed, 'raw_transaction', None) or signed.rawTransaction
tx_hash = w3.eth.send_raw_transaction(raw_tx)
h = tx_hash.hex()
print("tx_hash:", h if h.startswith('0x') else '0x' + h)

# A mined tx can still have reverted - check status, then verify the
# state actually changed.
receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
if receipt.status != 1:
    print(f"ERROR: transaction REVERTED (status {receipt.status}) in block {receipt.blockNumber}", file=sys.stderr)
    sys.exit(1)
if not contract.functions.isWhitelisted(target).call():
    print("ERROR: tx succeeded but the address is still not whitelisted", file=sys.stderr)
    sys.exit(1)
print(f"confirmed: {target} is now whitelisted (block {receipt.blockNumber})")
PY

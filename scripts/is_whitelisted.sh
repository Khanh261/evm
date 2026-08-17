#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${VALIDATOR_RPC_URL:-http://127.0.0.1:8545}"
ABI_PATH="$(dirname "$0")/../x/validatorgroup/precompile/abi.json"
PRE_ADDR="0x0000000000000000000000000000000000000808"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <validator_evm_address>" >&2
    exit 2
fi
TARGET="$1"

if [[ ! -f "$ABI_PATH" ]]; then
    echo "ERROR: ABI not found at $ABI_PATH" >&2
    exit 1
fi

python3 - <<PY
import sys, json
from web3 import Web3

rpc = "$RPC_URL"
w3 = Web3(Web3.HTTPProvider(rpc))

abi = json.load(open("$ABI_PATH"))
contract = w3.eth.contract(address=w3.to_checksum_address("$PRE_ADDR"), abi=abi)
target = w3.to_checksum_address("$TARGET")

try:
    whitelisted = contract.functions.isWhitelisted(target).call()
    print(f"{target}: {'whitelisted' if whitelisted else 'not whitelisted'}")
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PY

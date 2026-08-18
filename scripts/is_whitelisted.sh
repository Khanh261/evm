#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_prompt.sh
source "$SCRIPT_DIR/_prompt.sh"

require_web3

ABI_PATH="$SCRIPT_DIR/../x/validatorgroup/precompile/abi.json"
PRE_ADDR="0x0000000000000000000000000000000000000808"

TARGET="${1:-}"
prompt_value VALIDATOR_RPC_URL "RPC URL" "http://127.0.0.1:8545"
prompt_addr  TARGET            "Validator EVM address to check"
RPC_URL="$VALIDATOR_RPC_URL"

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

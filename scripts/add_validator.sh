#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${VALIDATOR_RPC_URL:-http://127.0.0.1:8545}"
PRIVATE_KEY="${VALIDATOR_PRIVATE_KEY:-}"
if [[ -z "$PRIVATE_KEY" ]]; then
  echo "ERROR: set VALIDATOR_PRIVATE_KEY env var" >&2
  exit 2
fi
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <validator_evm_address>" >&2
  exit 2
fi
TARGET="$1"
ABI_PATH="$(dirname "$0")/../x/validatorgroup/precompile/abi.json"
if [[ ! -f "$ABI_PATH" ]]; then
  echo "ERROR: ABI not found at $ABI_PATH" >&2
  exit 2
fi

# try to run embedded Python that uses web3
python3 - <<PY
import os, json
from web3 import Web3
rpc = os.environ.get('VALIDATOR_RPC_URL', '${RPC_URL}')
w3 = Web3(Web3.HTTPProvider(rpc))
abi = json.load(open('${ABI_PATH}'))
contract = w3.eth.contract(address=w3.to_checksum_address('0x0000000000000000000000000000000000000808'), abi=abi)
acct = w3.eth.account.from_key(os.environ['VALIDATOR_PRIVATE_KEY'])
target = '${TARGET}'
nonce = w3.eth.get_transaction_count(acct.address)
tx = contract.functions.addValidatorAddress(w3.to_checksum_address(target)).build_transaction({
  'from': acct.address,
  'value': 0,
  'gas': 200000,
  'gasPrice': w3.eth.gas_price,
  'nonce': nonce,
})
signed = acct.sign_transaction(tx)
raw_tx = getattr(signed, 'raw_transaction', None) or signed.rawTransaction
tx_hash = w3.eth.send_raw_transaction(raw_tx)
print("tx_hash:", tx_hash.hex())
PY

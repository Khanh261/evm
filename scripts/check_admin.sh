#!/usr/bin/env bash
set -euo pipefail
RPC_URL="${VALIDATOR_RPC_URL:-http://127.0.0.1:8545}"
PRE_ADDR="0x0000000000000000000000000000000000000808"
# selector for admin()
SELECTOR="0x18160ddd"

resp=$(curl -s -X POST "$RPC_URL" -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$PRE_ADDR\",\"data\":\"$SELECTOR\"},\"latest\"],\"id\":1}")

result=$(echo "$resp" | jq -r '.result // empty')
if [[ -z "$result" || "$result" == "0x" ]]; then
  echo "admin: <none>"
else
  # result is 32-byte padded return; last 20 bytes are address
  # strip 0x, take last 40 chars, prefix 0x, checksum
  hex=$(echo "$result" | sed 's/^0x//')
  addr="0x${hex: -40}"
  # try to checksum (optional, if 'xxd' & 'sha3sum' not available we print raw)
  echo "admin: $addr"
fi

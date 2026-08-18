#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_prompt.sh
source "$SCRIPT_DIR/_prompt.sh"

ADMIN_ADDR="${1:-${ADMIN_ADDR:-}}"

echo -e "${P_YELLOW}Admin Setup Script${P_NC}"
echo "================================"

prompt_value GENESIS    "Path to genesis.json" "${HOME}/.evmd/config/genesis.json"
prompt_addr  ADMIN_ADDR "Admin EVM address"

# Step 1: Verify genesis exists
if [[ ! -f "$GENESIS" ]]; then
    echo -e "${P_RED}✗ Genesis file not found: $GENESIS${P_NC}"
    exit 1
fi
echo -e "${P_GREEN}✓ Found genesis.json${P_NC}"

# Step 2: Backup genesis
BACKUP="${GENESIS}.bak.$(date +%s)"
cp "$GENESIS" "$BACKUP"
echo -e "${P_GREEN}✓ Backed up genesis to $BACKUP${P_NC}"

# Step 3: Set admin
echo "Setting admin to: $ADMIN_ADDR"
jq ".app_state.validatorgroup.admin = \"$ADMIN_ADDR\"" "$GENESIS" > "${GENESIS}.tmp" && mv "${GENESIS}.tmp" "$GENESIS"
echo -e "${P_GREEN}✓ Updated admin in genesis${P_NC}"

# Step 4: Verify genesis was updated
ADMIN_CHECK=$(jq -r '.app_state.validatorgroup.admin' "$GENESIS")
if [[ "$ADMIN_CHECK" == "$ADMIN_ADDR" ]]; then
    echo -e "${P_GREEN}✓ Admin verified in genesis: $ADMIN_CHECK${P_NC}"
else
    echo -e "${P_RED}✗ Admin mismatch. Expected: $ADMIN_ADDR, Got: $ADMIN_CHECK${P_NC}"
    exit 1
fi

# Step 5: Show current state
echo ""
echo -e "${P_YELLOW}Current validatorgroup state:${P_NC}"
jq '.app_state.validatorgroup' "$GENESIS"

echo ""
echo -e "${P_YELLOW}Next steps:${P_NC}"
echo "1. Stop the node: sudo systemctl stop evmd (or Ctrl+C if running in foreground)"
echo "2. Reset blockchain: evmd comet unsafe-reset-all"
echo "3. Restart the node: sudo systemctl start evmd (or ./local_node.sh)"
echo "4. Verify with: ./scripts/check_admin.sh"

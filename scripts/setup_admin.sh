#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

GENESIS="${HOME}/.evmd/config/genesis.json"
ADMIN_ADDR="${1:-0xF1E2D7A916A69b6B3b689d8F7C4f969994f6aD04}"

echo -e "${YELLOW}Admin Setup Script${NC}"
echo "================================"

# Step 1: Verify genesis exists
if [[ ! -f "$GENESIS" ]]; then
    echo -e "${RED}✗ Genesis file not found: $GENESIS${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Found genesis.json${NC}"

# Step 2: Backup genesis
BACKUP="${GENESIS}.bak.$(date +%s)"
cp "$GENESIS" "$BACKUP"
echo -e "${GREEN}✓ Backed up genesis to $BACKUP${NC}"

# Step 3: Set admin
echo "Setting admin to: $ADMIN_ADDR"
jq ".app_state.validatorgroup.admin = \"$ADMIN_ADDR\"" "$GENESIS" > "${GENESIS}.tmp" && mv "${GENESIS}.tmp" "$GENESIS"
echo -e "${GREEN}✓ Updated admin in genesis${NC}"

# Step 4: Verify genesis was updated
ADMIN_CHECK=$(jq -r '.app_state.validatorgroup.admin' "$GENESIS")
if [[ "$ADMIN_CHECK" == "$ADMIN_ADDR" ]]; then
    echo -e "${GREEN}✓ Admin verified in genesis: $ADMIN_CHECK${NC}"
else
    echo -e "${RED}✗ Admin mismatch. Expected: $ADMIN_ADDR, Got: $ADMIN_CHECK${NC}"
    exit 1
fi

# Step 5: Show current state
echo ""
echo -e "${YELLOW}Current validatorgroup state:${NC}"
jq '.app_state.validatorgroup' "$GENESIS"

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Stop the node: sudo systemctl stop evmd (or Ctrl+C if running in foreground)"
echo "2. Reset blockchain: evmd comet unsafe-reset-all"
echo "3. Restart the node: sudo systemctl start evmd (or ./local_node.sh)"
echo "4. Verify with: ./scripts/check_admin.sh"

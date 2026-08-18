#!/usr/bin/env bash
# Interactive end-to-end smoke test for the validatorgroup precompile:
# check admin -> add validator -> check whitelist -> remove validator ->
# check whitelist. Optionally also sets the admin via genesis (destructive).
#
# Just run it with no arguments — it will prompt for everything it needs:
#   ./scripts/test_validatorgroup.sh
#
# Env vars of the same name are used as defaults for the prompts, so this
# still works non-interactively (e.g. in CI) when stdin is not a terminal.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_prompt.sh
source "$SCRIPT_DIR/_prompt.sh"

RED="$P_RED"; GREEN="$P_GREEN"; YELLOW="$P_YELLOW"; BLUE="$P_BLUE"; NC="$P_NC"
FAILURES=0

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILURES=$((FAILURES + 1)); }
info() { echo -e "${YELLOW}==>${NC} $1"; }

echo "=========================================="
echo " validatorgroup precompile — smoke test"
echo "=========================================="
echo

prompt_value VALIDATOR_RPC_URL   "RPC URL" "http://127.0.0.1:8545"
prompt_addr  ADMIN_ADDR          "Admin EVM address"
prompt_secret ADMIN_PRIVATE_KEY  "Admin private key (hidden)"
prompt_addr  TEST_VALIDATOR_ADDR "Test validator EVM address (will be added, then removed)"

# Optional destructive step: set admin via genesis + full chain reset.
WITH_RESET=0
if [[ -t 0 ]]; then
    echo
    echo -e "${YELLOW}Optional:${NC} also test setup_admin.sh (sets admin in genesis)."
    echo -e "${RED}This requires 'evmd comet unsafe-reset-all' and DESTROYS all chain history.${NC}"
    read -r -p "$(echo -e "${BLUE}?${NC} Include the set-admin step? [y/N]: ")" ANSWER
    if [[ "$ANSWER" =~ ^[Yy] ]]; then
        echo -e "${RED}This will erase all blocks, balances, and state on this chain.${NC}"
        read -r -p "$(echo -e "${BLUE}?${NC} Type RESET to confirm: ")" CONFIRM
        if [[ "$CONFIRM" == "RESET" ]]; then
            WITH_RESET=1
            prompt_value EVMD_HOME    "evmd home directory" "$HOME/.evmd"
            prompt_value EVMD_SERVICE "systemd service name" "evmd"
        else
            echo "  Skipping set-admin step."
        fi
    fi
fi

export VALIDATOR_RPC_URL
export VALIDATOR_PRIVATE_KEY="$ADMIN_PRIVATE_KEY"

echo
echo "------------------------------------------"
echo " RPC:            $VALIDATOR_RPC_URL"
echo " Admin:          $ADMIN_ADDR"
echo " Test validator: $TEST_VALIDATOR_ADDR"
echo " Set admin step: $([[ "$WITH_RESET" -eq 1 ]] && echo "YES (destructive)" || echo "no")"
echo "------------------------------------------"
echo

if [[ "$WITH_RESET" -eq 1 ]]; then
    info "Setting admin via setup_admin.sh (genesis edit)"
    "$SCRIPT_DIR/setup_admin.sh" "$ADMIN_ADDR" || { fail "setup_admin.sh failed"; exit 1; }

    info "Resetting chain and restarting $EVMD_SERVICE"
    sudo systemctl stop "$EVMD_SERVICE"
    evmd comet unsafe-reset-all --home "$EVMD_HOME"
    sudo systemctl start "$EVMD_SERVICE"

    info "Waiting for node to come back up..."
    UP=0
    for _ in $(seq 1 30); do
        if curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "$VALIDATOR_RPC_URL" | grep -q result; then
            UP=1
            break
        fi
        sleep 2
    done
    if [[ "$UP" -eq 0 ]]; then
        fail "node did not come back up (check: journalctl -u $EVMD_SERVICE -n 60 --no-pager)"
        exit 1
    fi
fi

# 1. check admin
info "Checking admin address"
OUT=$("$SCRIPT_DIR/check_admin.sh" 2>&1)
echo "$OUT"
if echo "$OUT" | grep -qi "admin: ${ADMIN_ADDR}"; then
    pass "admin is set to $ADMIN_ADDR"
else
    fail "expected admin $ADMIN_ADDR, got: $OUT"
fi

# 2. pre-condition — target must not already be whitelisted
info "Checking $TEST_VALIDATOR_ADDR is not already whitelisted"
OUT=$("$SCRIPT_DIR/is_whitelisted.sh" "$TEST_VALIDATOR_ADDR" 2>&1)
echo "$OUT"
if echo "$OUT" | grep -qi "not whitelisted"; then
    pass "$TEST_VALIDATOR_ADDR starts out not whitelisted"
else
    echo -e "${RED}ABORT${NC}: $TEST_VALIDATOR_ADDR is already whitelisted (or the check failed)."
    echo "Refusing to continue — this test removes it at the end, which could" >&2
    echo "deregister a real validator. Pick a different test address." >&2
    exit 1
fi

# 3. add validator
info "Adding $TEST_VALIDATOR_ADDR to the whitelist"
OUT=$("$SCRIPT_DIR/add_validator.sh" "$TEST_VALIDATOR_ADDR" 2>&1)
echo "$OUT"
if echo "$OUT" | grep -q "tx_hash:"; then
    pass "add_validator.sh submitted a tx"
else
    fail "add_validator.sh did not return a tx_hash: $OUT"
fi
sleep 3

# 4. confirm whitelisted
info "Checking $TEST_VALIDATOR_ADDR is now whitelisted"
OUT=$("$SCRIPT_DIR/is_whitelisted.sh" "$TEST_VALIDATOR_ADDR" 2>&1)
echo "$OUT"
if echo "$OUT" | grep -qi ": whitelisted"; then
    pass "$TEST_VALIDATOR_ADDR is whitelisted after add"
else
    fail "expected 'whitelisted' after add, got: $OUT"
fi

# 5. remove validator
info "Removing $TEST_VALIDATOR_ADDR from the whitelist"
OUT=$("$SCRIPT_DIR/remove_validator.sh" "$TEST_VALIDATOR_ADDR" 2>&1)
echo "$OUT"
if echo "$OUT" | grep -q "tx_hash:"; then
    pass "remove_validator.sh submitted a tx"
else
    fail "remove_validator.sh did not return a tx_hash: $OUT"
fi
sleep 3

# 6. confirm no longer whitelisted
info "Checking $TEST_VALIDATOR_ADDR is no longer whitelisted"
OUT=$("$SCRIPT_DIR/is_whitelisted.sh" "$TEST_VALIDATOR_ADDR" 2>&1)
echo "$OUT"
if echo "$OUT" | grep -qi "not whitelisted"; then
    pass "$TEST_VALIDATOR_ADDR is not whitelisted after removal"
else
    fail "expected 'not whitelisted' after removal, got: $OUT"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
    echo -e "${GREEN}All checks passed.${NC}"
    exit 0
else
    echo -e "${RED}${FAILURES} check(s) failed.${NC}"
    exit 1
fi

#!/usr/bin/env bash
# Shared interactive prompt helpers for the validatorgroup admin scripts.
# Source this file; it is not meant to be executed directly.
#
# Every helper is a no-op when the target variable already holds a value
# (supplied via a CLI argument or an environment variable), so all the
# scripts stay fully usable non-interactively and in CI. Prompts are
# written to stderr, so a script's stdout stays clean for capture.

if [[ -t 1 ]]; then
    P_RED='\033[0;31m'; P_GREEN='\033[0;32m'; P_YELLOW='\033[1;33m'
    P_BLUE='\033[0;34m'; P_NC='\033[0m'
else
    P_RED=''; P_GREEN=''; P_YELLOW=''; P_BLUE=''; P_NC=''
fi

is_evm_addr() { [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]; }

# Fail early with an actionable message instead of a raw Python traceback
# when the web3 dependency is missing.
require_web3() {
    if ! python3 -c "import web3" >/dev/null 2>&1; then
        echo -e "${P_RED}ERROR${P_NC}: the 'web3' Python package is not installed." >&2
        echo "  Install it with:  python3 -m pip install web3" >&2
        echo "  (on a system-managed Python you may need a venv, or --break-system-packages)" >&2
        exit 3
    fi
}

# Called when a read hits EOF (Ctrl-D, or stdin closed mid-prompt), so the
# script reports why it stopped instead of dying silently under `set -e`.
_prompt_eof() {
    echo >&2
    echo -e "${P_RED}ERROR${P_NC}: input closed while waiting for $1 — aborting." >&2
    exit 2
}

# prompt_value <varname> <prompt text> [default]
# Prompts only if $<varname> is empty. Empty input accepts the default.
prompt_value() {
    local __var="$1" __text="$2" __default="${3:-}" __input
    [[ -n "${!__var:-}" ]] && return 0

    if [[ ! -t 0 ]]; then
        if [[ -n "$__default" ]]; then
            printf -v "$__var" '%s' "$__default"
            return 0
        fi
        echo -e "${P_RED}ERROR${P_NC}: $__var is unset and stdin is not a terminal." >&2
        exit 2
    fi

    while true; do
        if [[ -n "$__default" ]]; then
            read -r -p "$(echo -e "${P_BLUE}?${P_NC} ${__text} [${__default}]: ")" __input || _prompt_eof "$__var"
            __input="${__input:-$__default}"
        else
            read -r -p "$(echo -e "${P_BLUE}?${P_NC} ${__text}: ")" __input || _prompt_eof "$__var"
        fi
        [[ -n "$__input" ]] && break
        echo "  (required)" >&2
    done
    printf -v "$__var" '%s' "$__input"
}

# prompt_addr <varname> <prompt text>
# Like prompt_value, but re-asks until the value is a valid EVM address.
# A value supplied via argument/env that is invalid is a hard error.
prompt_addr() {
    local __var="$1" __text="$2"
    while true; do
        prompt_value "$__var" "$__text"
        is_evm_addr "${!__var}" && return 0
        echo -e "  ${P_RED}Not a valid EVM address${P_NC} (expected 0x + 40 hex chars): ${!__var}" >&2
        [[ ! -t 0 ]] && exit 2
        printf -v "$__var" '%s' ""
    done
}

# prompt_secret <varname> <prompt text>
# Like prompt_value, but input is not echoed to the terminal.
prompt_secret() {
    local __var="$1" __text="$2" __input
    [[ -n "${!__var:-}" ]] && return 0

    if [[ ! -t 0 ]]; then
        echo -e "${P_RED}ERROR${P_NC}: $__var is unset and stdin is not a terminal." >&2
        exit 2
    fi
    while true; do
        read -r -s -p "$(echo -e "${P_BLUE}?${P_NC} ${__text}: ")" __input || _prompt_eof "$__var"
        echo >&2
        [[ -n "$__input" ]] && break
        echo "  (required)" >&2
    done
    printf -v "$__var" '%s' "$__input"
}

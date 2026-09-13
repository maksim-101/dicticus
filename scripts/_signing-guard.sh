#!/bin/bash
# Signing guard: ensure the Developer ID key is present before codesign.
# Source this file; do not run it directly.
# Requires: op (1Password CLI), security, interactive terminal for Touch ID.
#
# Env vars (set in the untracked .env.build, then `source .env.build` or
# invoke via `op run --env-file=.env.build -- <script>` before running):
#   OP_DEVID_P12_REF - 1Password item ID/reference (AI vault, since 2026-09-13
#                       migration off TrueNAS) for the Developer ID Application
#                       "Certificates.p12" file.

_SIGNING_HASH="B9CA1FF8209D9B1BD4940F2D39C327EF836FD3C0"
_KEYCHAIN="$HOME/Library/Keychains/Apple Development.keychain-db"
_TMP_P12="/tmp/devid-guard-$$.p12"

_ensure_signing_key() {
    if security find-identity -v -p codesigning \
        "$_KEYCHAIN" 2>/dev/null | grep -q "$_SIGNING_HASH"; then
        return 0   # key present — no-op
    fi

    echo "  Developer ID key missing from keychain. Attempting auto-restore via 1Password..."

    if [ -z "$OP_DEVID_P12_REF" ]; then
        echo "ERROR: OP_DEVID_P12_REF is not set."
        echo "  Add it to .env.build (see this script's header) and either"
        echo "  'source .env.build' or invoke via"
        echo "  'op run --env-file=.env.build -- $0' before running."
        exit 1
    fi

    # Fail loud if 1Password is unreachable — never continue silently (D-03 step 4).
    # NOTE: do NOT use `op whoami` here — under the 1Password desktop-app /
    # system-auth (biometric) integration it reports "account is not signed in"
    # even when `op read`/`op item get` work. `op account get` is the reliable
    # liveness check across both classic-session and system-auth setups.
    if ! op account get >/dev/null 2>&1; then
        echo "ERROR: 1Password CLI cannot reach an account (locked or not integrated)."
        echo "  Unlock 1Password (Touch ID) or run: eval \$(op signin), then re-run."
        exit 1
    fi

    # Trap ensures .p12 is removed even if an error occurs mid-restore (T-36.2-01)
    trap 'rm -f "$_TMP_P12"' EXIT

    op read "op://AI/$OP_DEVID_P12_REF/Certificates.p12" --out-file "$_TMP_P12"
    # Password captured into a function-local variable only; never echoed or written to disk (T-36.2-02)
    local _PW
    _PW="$(op item get "$OP_DEVID_P12_REF" --fields password --reveal)"
    # Import into the custom keychain — NOT login (iCloud-synced and therefore pruned) (D-04, T-36.2-03)
    security import "$_TMP_P12" \
        -k "$_KEYCHAIN" \
        -P "$_PW" \
        -T /usr/bin/codesign
    rm -f "$_TMP_P12"

    # Re-verify the expected identity is now present
    if ! security find-identity -v -p codesigning \
        "$_KEYCHAIN" 2>/dev/null | grep -q "$_SIGNING_HASH"; then
        echo "ERROR: Key restore did not produce the expected identity ($_SIGNING_HASH)."
        exit 1
    fi
    echo "  Developer ID key restored successfully."
}

_ensure_signing_key

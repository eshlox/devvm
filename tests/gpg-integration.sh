#!/usr/bin/env bash
set -euo pipefail

if [ "${DEVVM_RUN_GPG_INTEGRATION:-0}" != "1" ]; then
	echo "skipping real GPG integration test; set DEVVM_RUN_GPG_INTEGRATION=1 to run it"
	exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

command -v gpg >/dev/null 2>&1 || {
	echo "gpg is required for the integration test" >&2
	exit 1
}

export HOME="$TMP_ROOT/home"
export GNUPGHOME="$TMP_ROOT/gnupg"

mkdir -p "$HOME" "$GNUPGHOME"
chmod 0700 "$GNUPGHOME"

gpg --batch --pinentry-mode loopback --passphrase '' \
	--quick-generate-key "DevVM Test <devvm-test@example.invalid>" ed25519 cert 1d >/dev/null

primary="$(
	gpg --with-colons --fingerprint --list-secret-keys "devvm-test@example.invalid" |
		awk -F: '$1 == "fpr" { print $10; exit }'
)"
[ -n "$primary" ]

gpg --batch --pinentry-mode loopback --passphrase '' \
	--quick-add-key "$primary" ed25519 sign 1d >/dev/null

source "$ROOT/lib/util.sh"
source "$ROOT/lib/gpg.sh"

parsed_primary="$(devvm_gpg_primary_fingerprint "$primary")"
[ "$parsed_primary" = "$primary" ]

subkey="$(devvm_gpg_secret_subkey_fingerprints "$primary" | tail -n 1)"
[ -n "$subkey" ]

bundle="$TMP_ROOT/secret-subkey.asc"
gpg --armor --export-secret-subkeys "${subkey}!" >"$bundle"
parsed_subkey="$(devvm_gpg_bundle_subkey_fingerprint "$bundle")"
[ "$parsed_subkey" = "$subkey" ]

echo "real GPG integration test passed"

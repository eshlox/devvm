#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local/bin}"
CONFIG_DIR="${DEVVM_CONFIG:-$HOME/.config/devvm}"

mkdir -p "$PREFIX" "$CONFIG_DIR/vms"
ln -sf "$REPO_DIR/bin/devvm" "$PREFIX/devvm"

if [ ! -f "$CONFIG_DIR/config.env" ]; then
	cp "$REPO_DIR/defaults/config.env" "$CONFIG_DIR/config.env"
fi

for cmd in limactl ansible-playbook; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "Warning: required command not found in PATH: $cmd" >&2
	fi
done

echo "Installed devvm at $PREFIX/devvm"
echo "Ensure $PREFIX is in PATH."

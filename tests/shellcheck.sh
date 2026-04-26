#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
	echo "shellcheck is required to run this test" >&2
	exit 127
fi

shellcheck -x \
	"$ROOT/install.sh" \
	"$ROOT/bin/devvm" \
	"$ROOT"/lib/*.sh \
	"$ROOT"/scripts/*.sh \
	"$ROOT"/tests/*.sh

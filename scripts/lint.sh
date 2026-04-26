#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash "$ROOT/tests/shellcheck.sh"

if [ -d "$ROOT/.github/workflows" ]; then
	actionlint "$ROOT"/.github/workflows/*.yml
fi

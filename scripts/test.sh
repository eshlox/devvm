#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

for file in install.sh bin/devvm lib/*.sh scripts/*.sh tests/*.sh; do
	bash -n "$file"
done

bash "$ROOT/tests/smoke.sh"

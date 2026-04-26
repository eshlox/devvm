#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/files.sh
source "$ROOT/scripts/files.sh"

mapfile -t shell_files < <(devvm_shell_files)

prettier . --write
shfmt -w "${shell_files[@]}"

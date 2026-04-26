#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/files.sh
source "$ROOT/scripts/files.sh"

mapfile -t shell_files < <(devvm_shell_files)

shfmt -d "${shell_files[@]}"

if git grep -nI '[[:blank:]]$' -- .; then
	echo "Trailing whitespace found." >&2
	exit 1
fi

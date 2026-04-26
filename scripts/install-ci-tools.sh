#!/usr/bin/env bash
set -euo pipefail

GOBIN="${GOBIN:-$HOME/go/bin}"
mkdir -p "$GOBIN"
export GOBIN

go install "mvdan.cc/sh/v3/cmd/shfmt@${SHFMT_VERSION:-latest}"
go install "github.com/rhysd/actionlint/cmd/actionlint@${ACTIONLINT_VERSION:-latest}"

if [ -n "${GITHUB_PATH:-}" ]; then
	printf '%s\n' "$GOBIN" >>"$GITHUB_PATH"
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

devvm_release_die() {
	echo "$*" >&2
	exit 1
}

command -v gh >/dev/null 2>&1 || devvm_release_die "gh is required to create GitHub releases"

TAG="${1:-${GITHUB_REF_NAME:-}}"
if [ -z "$TAG" ]; then
	TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
fi

case "$TAG" in
v[0-9]*) ;;
*)
	devvm_release_die "release tag must look like v0.1.0; got: ${TAG:-<empty>}"
	;;
esac

VERSION="${TAG#v}"
NOTES_FILE="$(mktemp)"
trap 'rm -f "$NOTES_FILE"' EXIT

if gh release view "$TAG" >/dev/null 2>&1; then
	echo "GitHub release already exists: $TAG"
	exit 0
fi

awk -v version="$VERSION" '
  BEGIN { capture = 0; seen = 0 }
  /^## / {
    if (capture) {
      exit
    }
    if ($0 == "## " version || $0 == "## [" version "]") {
      capture = 1
      seen = 1
      print
      next
    }
  }
  capture { print }
  END {
    if (!seen) {
      exit 2
    }
  }
' CHANGELOG.md >"$NOTES_FILE" || {
	{
		printf '## %s\n\n' "$VERSION"
		printf 'See CHANGELOG.md for release details.\n'
	} >"$NOTES_FILE"
}

gh release create "$TAG" \
	--title "$TAG" \
	--notes-file "$NOTES_FILE" \
	--verify-tag

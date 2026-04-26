#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(node -p "require('./package.json').version")"
TAG="v$VERSION"
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
	--target "${GITHUB_SHA:-HEAD}"

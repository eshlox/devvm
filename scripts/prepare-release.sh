#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
	cat <<'HELP'
Usage:
  scripts/prepare-release.sh <version|vversion> [--push]

Examples:
  scripts/prepare-release.sh 0.1.0
  scripts/prepare-release.sh v0.1.0 --push

The script expects CHANGELOG.md to contain a matching "## <version>" section.
It runs local checks, creates an annotated git tag, and optionally pushes the
current branch plus the tag to origin.
HELP
}

die() {
	echo "$*" >&2
	exit 1
}

version="${1:-}"
case "$version" in
-h | --help)
	usage
	exit 0
	;;
esac

[ -n "$version" ] || {
	usage >&2
	exit 1
}
shift

push_release="0"
while [ "$#" -gt 0 ]; do
	case "$1" in
	--push)
		push_release="1"
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die "unknown option: $1"
		;;
	esac
	shift
done

version="${version#v}"
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$'; then
	die "version must look like 0.1.0 or v0.1.0"
fi

tag="v$version"
branch="$(git branch --show-current)"

[ -z "$(git status --porcelain)" ] || die "working tree is not clean; commit or stash changes first"
git rev-parse --verify "$tag" >/dev/null 2>&1 && die "tag already exists: $tag"

awk -v version="$version" '
  /^## / {
    if ($0 == "## " version || $0 == "## [" version "]") {
      found = 1
    }
  }
  END {
    exit found ? 0 : 1
  }
' CHANGELOG.md || die "CHANGELOG.md is missing a ## $version section"

bash scripts/check.sh
git tag -a "$tag" -m "$tag"

echo "Created tag $tag"

if [ "$push_release" = "1" ]; then
	[ -n "$branch" ] || die "could not detect current branch for push"
	git push origin "$branch" "$tag"
	echo "Pushed $branch and $tag to origin"
else
	echo "Push with: git push origin ${branch:-HEAD} $tag"
fi

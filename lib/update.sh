#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034

devvm_update_help() {
	cat <<'HELP'
Usage:
  devvm self-update
  devvm self-update --version v0.1.0 [--source <git-url>] [--no-verify-tag] [--force]
  devvm self-update --rollback

Source checkout installs run `git pull --ff-only`.

Copied installs use:
  ~/.local/share/devvm/versions/<version>/
  ~/.local/share/devvm/current -> versions/<version>

For copied installs, pass --version to install a specific release tag. Release tags are
verified with `git tag -v` by default.
HELP
}

devvm_install_root_from_core() {
	local parent
	parent="$(dirname "$DEVVM_CORE")"
	if [ "$(basename "$parent")" = "versions" ]; then
		dirname "$parent"
		return 0
	fi
	printf '%s\n' "${DEVVM_INSTALL_ROOT:-$HOME/.local/share/devvm}"
}

devvm_install_env_path() {
	local root
	root="$(devvm_install_root_from_core)"
	printf '%s/install.env\n' "$root"
}

devvm_load_install_metadata() {
	local install_env root
	install_env="$(devvm_install_env_path)"
	root="$(devvm_install_root_from_core)"

	DEVVM_INSTALL_MODE=""
	DEVVM_INSTALL_VERSION=""
	DEVVM_INSTALL_ROOT="$root"
	DEVVM_INSTALL_PREFIX="${PREFIX:-$HOME/.local/bin}"
	DEVVM_INSTALL_CORE="$DEVVM_CORE"
	DEVVM_INSTALL_REPO=""
	DEVVM_INSTALL_PREVIOUS_VERSION=""

	if [ -f "$install_env" ]; then
		# shellcheck source=/dev/null
		source "$install_env"
	fi

	if [ -z "$DEVVM_INSTALL_MODE" ]; then
		if [ -d "$DEVVM_CORE/.git" ]; then
			DEVVM_INSTALL_MODE="source"
		else
			DEVVM_INSTALL_MODE="copy"
		fi
	fi
}

devvm_update_safe_version() {
	local version
	version="$1"
	case "$version" in
	'' | *[!A-Za-z0-9._+-]* | .* | *..*) devvm_die "unsafe install version: $version" ;;
	esac
}

devvm_update_normalize_version() {
	local version
	version="$1"
	case "$version" in
	v*) printf '%s\n' "$version" ;;
	*) printf 'v%s\n' "$version" ;;
	esac
}

devvm_update_write_metadata() {
	local mode version root prefix core repo previous metadata
	mode="$1"
	version="$2"
	root="$3"
	prefix="$4"
	core="$5"
	repo="$6"
	previous="$7"
	metadata="$root/install.env"

	cat >"$metadata" <<METADATA
DEVVM_INSTALL_MODE=$(devvm_shell_quote "$mode")
DEVVM_INSTALL_VERSION=$(devvm_shell_quote "$version")
DEVVM_INSTALL_ROOT=$(devvm_shell_quote "$root")
DEVVM_INSTALL_PREFIX=$(devvm_shell_quote "$prefix")
DEVVM_INSTALL_CORE=$(devvm_shell_quote "$core")
DEVVM_INSTALL_REPO=$(devvm_shell_quote "$repo")
DEVVM_INSTALL_PREVIOUS_VERSION=$(devvm_shell_quote "$previous")
METADATA
}

devvm_update_copy_tree() {
	local source target item
	source="$1"
	target="$2"

	rm -rf "$target"
	mkdir -p "$target"
	for item in bin defaults docs lib scripts templates tests install.sh README.md CHANGELOG.md LICENSE; do
		[ -e "$source/$item" ] || continue
		cp -R "$source/$item" "$target/"
	done
	chmod +x "$target/bin/devvm"
	chmod +x "$target/install.sh"
}

devvm_update_syntax_check() {
	local core file
	core="$1"
	while IFS= read -r file; do
		[ -n "$file" ] || continue
		[ -f "$core/$file" ] || continue
		bash -n "$core/$file"
	done < <("$core/scripts/files.sh")
}

devvm_update_switch_current() {
	local root version_dir
	root="$1"
	version_dir="$2"

	ln -sfn "$version_dir" "$root/current.tmp.$$"
	rm -f "$root/current"
	mv -f "$root/current.tmp.$$" "$root/current"
}

devvm_self_update_source() {
	devvm_require_command git
	if [ ! -d "$DEVVM_CORE/.git" ]; then
		devvm_die "source install is not a git checkout: $DEVVM_CORE"
	fi
	git -C "$DEVVM_CORE" pull --ff-only
}

devvm_self_update_copy() {
	local requested_version source verify_tag force tmp checkout version target previous current_target root prefix repo
	requested_version=""
	source=""
	verify_tag="1"
	force="0"

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--version)
			[ "$#" -gt 1 ] || devvm_die "--version requires a value"
			requested_version="$2"
			shift
			;;
		--source)
			[ "$#" -gt 1 ] || devvm_die "--source requires a value"
			source="$2"
			shift
			;;
		--verify-tag)
			verify_tag="1"
			;;
		--no-verify-tag)
			verify_tag="0"
			;;
		--force)
			force="1"
			;;
		-h | --help)
			devvm_update_help
			return 0
			;;
		*)
			devvm_die "unknown self-update option: $1"
			;;
		esac
		shift
	done

	devvm_load_install_metadata
	root="$DEVVM_INSTALL_ROOT"
	prefix="$DEVVM_INSTALL_PREFIX"
	repo="${source:-$DEVVM_INSTALL_REPO}"
	[ -n "$requested_version" ] || devvm_die "copied installs require: devvm self-update --version v0.1.0"
	[ -n "$repo" ] || devvm_die "missing release source; pass --source <git-url>"
	version="$(devvm_update_normalize_version "$requested_version")"
	devvm_update_safe_version "$version"

	target="$root/versions/$version"
	if [ -e "$target" ] && [ "$force" != "1" ]; then
		devvm_die "install version already exists: $target; use --force to replace it"
	fi

	devvm_require_command git
	if [ "$verify_tag" = "1" ]; then
		devvm_require_command gpg
	fi

	tmp="$(mktemp -d)"
	checkout="$tmp/repo"

	git init -q "$checkout"
	git -C "$checkout" remote add origin "$repo"
	git -C "$checkout" fetch --depth 1 origin "refs/tags/$version:refs/tags/$version"
	if [ "$verify_tag" = "1" ]; then
		git -C "$checkout" tag -v "$version"
	else
		devvm_warn "skipping release tag verification for $version"
	fi
	git -C "$checkout" checkout -q --detach "$version"

	devvm_update_copy_tree "$checkout" "$target"
	devvm_update_syntax_check "$target"

	previous=""
	if [ -L "$root/current" ]; then
		current_target="$(readlink "$root/current")"
		previous="${current_target##*/}"
	fi
	devvm_update_switch_current "$root" "$target"
	devvm_update_write_metadata "copy" "$version" "$root" "$prefix" "$target" "$repo" "$previous"
	rm -rf "$tmp"
	devvm_log "installed DevVM $version"
	devvm_log "restart your shell or run devvm again to use the updated version"
}

devvm_self_update_rollback() {
	local root prefix repo current previous target current_target
	devvm_load_install_metadata
	[ "$DEVVM_INSTALL_MODE" = "copy" ] || devvm_die "rollback is only available for copied installs"
	root="$DEVVM_INSTALL_ROOT"
	prefix="$DEVVM_INSTALL_PREFIX"
	repo="$DEVVM_INSTALL_REPO"
	previous="$DEVVM_INSTALL_PREVIOUS_VERSION"
	[ -n "$previous" ] || devvm_die "no previous DevVM version recorded"
	target="$root/versions/$previous"
	[ -d "$target" ] || devvm_die "previous DevVM version is missing: $target"

	current=""
	if [ -L "$root/current" ]; then
		current_target="$(readlink "$root/current")"
		current="${current_target##*/}"
	fi
	devvm_update_switch_current "$root" "$target"
	devvm_update_write_metadata "copy" "$previous" "$root" "$prefix" "$target" "$repo" "$current"
	devvm_log "rolled back DevVM to $previous"
}

devvm_self_update() {
	local rollback
	rollback="0"
	case "${1:-}" in
	--rollback)
		rollback="1"
		shift
		;;
	-h | --help)
		devvm_update_help
		return 0
		;;
	esac

	if [ "$rollback" = "1" ]; then
		[ "$#" -eq 0 ] || devvm_die "--rollback does not accept extra arguments"
		devvm_self_update_rollback
		return 0
	fi

	devvm_load_install_metadata
	case "$DEVVM_INSTALL_MODE" in
	source)
		[ "$#" -eq 0 ] || devvm_die "source installs update with git pull; pass no options"
		devvm_self_update_source
		;;
	copy)
		devvm_self_update_copy "$@"
		;;
	*)
		devvm_die "unknown install mode: $DEVVM_INSTALL_MODE"
		;;
	esac
}

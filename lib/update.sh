#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034

devvm_update_help() {
	cat <<'HELP'
Usage:
  devvm self-update
  devvm self-update --version v0.1.0 [--source <git-url>] [--no-verify-tag] [--no-verify-signer] [--force]
  devvm self-update --rollback
  devvm verify-install

Source checkout installs run `git pull --ff-only`.
Homebrew installs update with `brew update && brew upgrade devvm`.

Copied installs use:
  ~/.local/share/devvm/versions/<version>/
  ~/.local/share/devvm/current -> versions/<version>

For copied installs, pass --version to install a specific release tag. Release tags are
verified with `git verify-tag` by default. The signing fingerprint must match
DEVVM_RELEASE_SIGNER_FINGERPRINTS unless --no-verify-signer is passed.
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
	local install_env root brew_version
	install_env="$(devvm_install_env_path)"
	root="$(devvm_install_root_from_core)"

	DEVVM_INSTALL_MODE=""
	DEVVM_INSTALL_VERSION=""
	DEVVM_INSTALL_ROOT="$root"
	DEVVM_INSTALL_PREFIX="${PREFIX:-$HOME/.local/bin}"
	DEVVM_INSTALL_CORE="$DEVVM_CORE"
	DEVVM_INSTALL_REPO=""
	DEVVM_INSTALL_PREVIOUS_VERSION=""
	DEVVM_INSTALL_SIGNER_FINGERPRINT=""
	DEVVM_INSTALL_COMMAND=""
	DEVVM_INSTALL_CONFIG=""
	DEVVM_INSTALL_STATE=""

	if [ -f "$install_env" ]; then
		devvm_load_env_file "$install_env"
	fi

	if [ -z "$DEVVM_INSTALL_MODE" ]; then
		if brew_version="$(devvm_homebrew_version_from_core "$DEVVM_CORE")"; then
			DEVVM_INSTALL_MODE="homebrew"
			DEVVM_INSTALL_VERSION="$brew_version"
			DEVVM_INSTALL_PREFIX="$(devvm_homebrew_prefix_from_core "$DEVVM_CORE")"
			DEVVM_INSTALL_ROOT="$(dirname "$DEVVM_CORE")"
		elif [ -d "$DEVVM_CORE/.git" ]; then
			DEVVM_INSTALL_MODE="source"
		else
			DEVVM_INSTALL_MODE="copy"
		fi
	fi
}

devvm_homebrew_version_from_core() {
	local core parent version_dir formula_dir cellar_dir
	core="$1"
	[ "$(basename "$core")" = "libexec" ] || return 1
	parent="$(dirname "$core")"
	version_dir="$(basename "$parent")"
	formula_dir="$(dirname "$parent")"
	cellar_dir="$(dirname "$formula_dir")"
	[ "$(basename "$formula_dir")" = "devvm" ] || return 1
	[ "$(basename "$cellar_dir")" = "Cellar" ] || return 1
	[ -n "$version_dir" ] || return 1
	printf '%s\n' "$version_dir"
}

devvm_homebrew_prefix_from_core() {
	local core parent formula_dir cellar_dir
	core="$1"
	parent="$(dirname "$core")"
	formula_dir="$(dirname "$parent")"
	cellar_dir="$(dirname "$formula_dir")"
	dirname "$cellar_dir"
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
	local mode version root prefix core repo previous signer metadata
	mode="$1"
	version="$2"
	root="$3"
	prefix="$4"
	core="$5"
	repo="$6"
	previous="$7"
	signer="${8:-}"
	metadata="$root/install.env"

	cat >"$metadata" <<METADATA
DEVVM_INSTALL_MODE=$(devvm_shell_quote "$mode")
DEVVM_INSTALL_VERSION=$(devvm_shell_quote "$version")
DEVVM_INSTALL_ROOT=$(devvm_shell_quote "$root")
DEVVM_INSTALL_PREFIX=$(devvm_shell_quote "$prefix")
DEVVM_INSTALL_CORE=$(devvm_shell_quote "$core")
DEVVM_INSTALL_REPO=$(devvm_shell_quote "$repo")
DEVVM_INSTALL_PREVIOUS_VERSION=$(devvm_shell_quote "$previous")
DEVVM_INSTALL_SIGNER_FINGERPRINT=$(devvm_shell_quote "$signer")
METADATA
}

devvm_sha256_file() {
	local file
	file="$1"
	if devvm_command_exists shasum; then
		shasum -a 256 "$file" | awk '{print $1}'
	elif devvm_command_exists sha256sum; then
		sha256sum "$file" | awk '{print $1}'
	else
		devvm_die "required command not found: shasum or sha256sum"
	fi
}

devvm_install_manifest_generate() {
	local core path hash manifest
	core="$1"
	manifest="$core/.devvm-manifest.sha256"
	(
		cd "$core" || exit
		find . -type f ! -name '.devvm-manifest.sha256' -print | LC_ALL=C sort |
			while IFS= read -r path; do
				hash="$(devvm_sha256_file "$path")"
				printf '%s  %s\n' "$hash" "$path"
			done >"$manifest"
	)
}

devvm_install_manifest_check() {
	local core manifest
	core="$1"
	manifest="$core/.devvm-manifest.sha256"
	[ -f "$manifest" ] || {
		devvm_warn "install manifest missing: $manifest"
		return 1
	}
	if devvm_command_exists shasum; then
		(cd "$core" && shasum -a 256 -c "$manifest")
	elif devvm_command_exists sha256sum; then
		(cd "$core" && sha256sum -c "$manifest")
	else
		devvm_warn "cannot verify install manifest; shasum or sha256sum is required"
		return 1
	fi
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
	devvm_install_manifest_generate "$target"
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
	local requested_version source verify_tag verify_signer force tmp checkout version target previous current_target root prefix repo signer
	requested_version=""
	source=""
	verify_tag="1"
	verify_signer="1"
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
			verify_signer="0"
			;;
		--verify-signer)
			verify_signer="1"
			;;
		--no-verify-signer)
			verify_signer="0"
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
	devvm_load_config
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
		signer="$(devvm_update_verify_tag "$checkout" "$version" "$verify_signer")"
	else
		devvm_warn "skipping release tag verification for $version"
		signer=""
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
	devvm_update_write_metadata "copy" "$version" "$root" "$prefix" "$target" "$repo" "$previous" "$signer"
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
	devvm_update_write_metadata "copy" "$previous" "$root" "$prefix" "$target" "$repo" "$current" ""
	devvm_log "rolled back DevVM to $previous"
}

devvm_update_verify_tag() {
	local checkout version verify_signer output fingerprint fingerprint_upper allowed allowed_upper ok
	checkout="$1"
	version="$2"
	verify_signer="$3"

	output="$(git -C "$checkout" verify-tag --raw "$version" 2>&1)" || {
		printf '%s\n' "$output" >&2
		devvm_die "release tag verification failed: $version"
	}
	fingerprint="$(printf '%s\n' "$output" | awk '/^\[GNUPG:\] VALIDSIG / { print $3; exit }')"
	[ -n "$fingerprint" ] || devvm_die "could not read signing fingerprint for tag: $version"
	fingerprint_upper="$(printf '%s' "$fingerprint" | tr '[:lower:]' '[:upper:]')"

	if [ "$verify_signer" = "1" ]; then
		[ -n "$DEVVM_RELEASE_SIGNER_FINGERPRINTS" ] ||
			devvm_die "DEVVM_RELEASE_SIGNER_FINGERPRINTS is empty; set a trusted release signer or pass --no-verify-signer"
		ok="0"
		for allowed in $DEVVM_RELEASE_SIGNER_FINGERPRINTS; do
			allowed_upper="$(printf '%s' "$allowed" | tr '[:lower:]' '[:upper:]')"
			if [ "$allowed_upper" = "$fingerprint_upper" ]; then
				ok="1"
				break
			fi
		done
		[ "$ok" = "1" ] || devvm_die "release tag signer is not trusted: $fingerprint"
	fi

	printf '%s\n' "$fingerprint"
}

devvm_update_stable_version_key() {
	local version major minor patch extra
	version="$1"
	case "$version" in
	v[0-9]*.[0-9]*.[0-9]*) ;;
	*) return 1 ;;
	esac
	version="${version#v}"
	IFS=. read -r major minor patch extra <<EOF
$version
EOF
	[ -z "${extra:-}" ] || return 1
	case "$major$minor$patch" in
	'' | *[!0-9]*) return 1 ;;
	esac
	[ -n "$major" ] && [ -n "$minor" ] && [ -n "$patch" ] || return 1
	printf '%012d.%012d.%012d\n' "$major" "$minor" "$patch"
}

devvm_update_version_is_newer() {
	local latest current latest_key current_key
	latest="$1"
	current="$2"
	latest_key="$(devvm_update_stable_version_key "$latest")" || return 1
	if current_key="$(devvm_update_stable_version_key "$current")"; then
		[[ "$latest_key" > "$current_key" ]]
	else
		[ "$latest" != "$current" ]
	fi
}

devvm_update_check_state_path() {
	printf '%s/update-check.env\n' "$DEVVM_STATE"
}

devvm_update_check_write_state() {
	local state tmp checked_at latest
	checked_at="$1"
	latest="$2"
	state="$(devvm_update_check_state_path)"
	devvm_ensure_dir "$(dirname "$state")"
	tmp="$state.tmp.$$"
	{
		printf 'DEVVM_UPDATE_CHECK_LAST_EPOCH=%s\n' "$(devvm_shell_quote "$checked_at")"
		printf 'DEVVM_UPDATE_CHECK_LATEST_VERSION=%s\n' "$(devvm_shell_quote "$latest")"
	} >"$tmp"
	chmod 0600 "$tmp"
	mv -f "$tmp" "$state"
}

devvm_update_check_latest_release() {
	local repo output latest
	repo="$1"
	devvm_command_exists git || return 1
	output="$(
		GIT_TERMINAL_PROMPT=0 \
			GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}" \
			git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=5 \
			ls-remote --tags --refs "$repo" 'v*' 2>/dev/null
	)" || return 1
	latest="$(
		printf '%s\n' "$output" |
			awk '
				{
					tag = $2
					sub(/^refs\/tags\//, "", tag)
					if (tag ~ /^v[0-9]+[.][0-9]+[.][0-9]+$/) {
						version = substr(tag, 2)
						split(version, parts, ".")
						printf "%012d.%012d.%012d %s\n", parts[1], parts[2], parts[3], tag
					}
				}
			' |
			LC_ALL=C sort |
			tail -n 1 |
			awk '{ print $2 }'
	)"
	[ -n "$latest" ] || return 1
	printf '%s\n' "$latest"
}

devvm_update_check_notice() {
	local cmd now state last latest current elapsed
	cmd="$1"
	case "$cmd" in
	'' | help | -h | --help | completion | init | self-update | verify-install)
		return 0
		;;
	esac
	if [ "${DEVVM_UPDATE_CHECK_FORCE:-0}" != "1" ] && [ ! -t 2 ]; then
		return 0
	fi

	devvm_load_install_metadata
	[ "$DEVVM_INSTALL_MODE" = "copy" ] || return 0
	[ -n "$DEVVM_INSTALL_REPO" ] || return 0
	devvm_load_config
	[ "$DEVVM_UPDATE_CHECK_ENABLED" = "1" ] || return 0

	now="$(date +%s 2>/dev/null || printf '0')"
	case "$now" in
	'' | *[!0-9]*) return 0 ;;
	esac

	DEVVM_UPDATE_CHECK_LAST_EPOCH="0"
	DEVVM_UPDATE_CHECK_LATEST_VERSION=""
	state="$(devvm_update_check_state_path)"
	if [ -f "$state" ]; then
		devvm_load_env_file "$state"
	fi
	last="${DEVVM_UPDATE_CHECK_LAST_EPOCH:-0}"
	case "$last" in
	'' | *[!0-9]*) last="0" ;;
	esac
	if [ "${DEVVM_UPDATE_CHECK_FORCE:-0}" != "1" ]; then
		elapsed=$((now - last))
		if [ "$elapsed" -ge 0 ] && [ "$elapsed" -lt "$DEVVM_UPDATE_CHECK_INTERVAL_SECONDS" ]; then
			return 0
		fi
	fi

	if latest="$(devvm_update_check_latest_release "$DEVVM_INSTALL_REPO")"; then
		devvm_update_check_write_state "$now" "$latest" || return 0
	else
		devvm_update_check_write_state "$now" "" || return 0
		return 0
	fi

	current="${DEVVM_INSTALL_VERSION:-}"
	if devvm_update_version_is_newer "$latest" "$current"; then
		devvm_warn "update available: DevVM $latest (current ${current:-unknown}); run: devvm self-update --version $latest"
	fi
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
	homebrew)
		[ "$#" -eq 0 ] || devvm_die "Homebrew installs update with: brew update && brew upgrade devvm"
		devvm_die "Homebrew installs update with: brew update && brew upgrade devvm"
		;;
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

devvm_verify_install() {
	local status current_target
	status="0"
	devvm_load_install_metadata
	devvm_load_config

	devvm_log "install mode: $DEVVM_INSTALL_MODE"
	devvm_log "install version: ${DEVVM_INSTALL_VERSION:-unknown}"
	devvm_log "install root: $DEVVM_INSTALL_ROOT"
	devvm_log "install core: $DEVVM_INSTALL_CORE"
	devvm_log "install repo: ${DEVVM_INSTALL_REPO:-unknown}"
	devvm_log "trusted release signers: ${DEVVM_RELEASE_SIGNER_FINGERPRINTS:-<unset>}"
	if [ -n "${DEVVM_INSTALL_SIGNER_FINGERPRINT:-}" ]; then
		devvm_log "installed release signer: $DEVVM_INSTALL_SIGNER_FINGERPRINT"
	fi

	case "$DEVVM_INSTALL_MODE" in
	homebrew)
		devvm_log "Homebrew-managed install"
		if devvm_command_exists brew; then
			brew list --versions devvm 2>/dev/null || true
		fi
		;;
	copy)
		if [ -L "$DEVVM_INSTALL_ROOT/current" ]; then
			current_target="$(readlink "$DEVVM_INSTALL_ROOT/current")"
			devvm_log "current symlink: $current_target"
			if [ "$current_target" != "$DEVVM_INSTALL_CORE" ]; then
				devvm_warn "current symlink does not match install core"
				status="1"
			fi
		else
			devvm_warn "current symlink missing: $DEVVM_INSTALL_ROOT/current"
			status="1"
		fi
		if ! devvm_install_manifest_check "$DEVVM_INSTALL_CORE"; then
			status="1"
		fi
		if [ -z "$DEVVM_RELEASE_SIGNER_FINGERPRINTS" ]; then
			devvm_warn "no trusted release signer fingerprints configured"
			status="1"
		fi
		;;
	source)
		devvm_log "source checkout installs are mutable and update with git pull"
		if [ ! -d "$DEVVM_INSTALL_CORE/.git" ]; then
			devvm_warn "source install is not a git checkout: $DEVVM_INSTALL_CORE"
			status="1"
		fi
		;;
	*)
		devvm_warn "unknown install mode: $DEVVM_INSTALL_MODE"
		status="1"
		;;
	esac

	return "$status"
}

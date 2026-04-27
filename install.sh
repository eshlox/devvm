#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local/bin}"
INSTALL_ROOT="${DEVVM_INSTALL_ROOT:-$HOME/.local/share/devvm}"
CONFIG_DIR="${DEVVM_CONFIG:-$HOME/.config/devvm}"
STATE_DIR="${DEVVM_STATE:-$HOME/.local/share/devvm-state}"
MODE="copy"
FORCE="0"
DRY_RUN="0"
VERSION="${DEVVM_INSTALL_VERSION:-}"
REPO_URL="${DEVVM_INSTALL_REPO:-}"
COMMAND_NAME="devvm"
VM_PREFIX_OVERRIDE=""

install_usage() {
	cat <<'HELP'
Usage:
  ./install.sh [--copy|--symlink] [--name COMMAND] [--prefix DIR] [--install-dir DIR]
    [--config-dir DIR] [--state-dir DIR] [--vm-prefix PREFIX]
    [--version VERSION] [--repo URL] [--force] [--dry-run]

Defaults:
  --copy
  --name devvm
  --prefix ~/.local/bin
  --install-dir ~/.local/share/devvm
  --config-dir ~/.config/devvm
  --state-dir ~/.local/share/devvm-state

The default copied layout is:
  ~/.local/share/devvm/versions/<version>/
  ~/.local/share/devvm/current -> versions/<version>
  ~/.local/bin/devvm -> ~/.local/share/devvm/current/bin/devvm

Use --symlink for a development checkout install.
Use --name, --config-dir, --state-dir, and --vm-prefix to create an isolated
development command such as devvm-dev.
HELP
}

install_die() {
	printf 'install.sh: error: %s\n' "$*" >&2
	exit 1
}

install_warn() {
	printf 'install.sh: warning: %s\n' "$*" >&2
}

install_log() {
	printf '%s\n' "$*"
}

install_shell_quote() {
	local value
	value="${1:-}"
	printf "'%s'" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
}

install_safe_version() {
	local value
	value="$1"
	case "$value" in
	'' | *[!A-Za-z0-9._+-]* | .* | *..*) install_die "unsafe install version: $value" ;;
	esac
}

install_safe_command_name() {
	local value
	value="$1"
	case "$value" in
	'' | *[!A-Za-z0-9._-]* | .* | *..*) install_die "unsafe command name: $value" ;;
	esac
}

install_repo_url() {
	if [ -n "$REPO_URL" ]; then
		printf '%s\n' "$REPO_URL"
		return 0
	fi
	if command -v git >/dev/null 2>&1 && [ -d "$REPO_DIR/.git" ]; then
		git -C "$REPO_DIR" config --get remote.origin.url 2>/dev/null || true
	fi
}

install_detect_version() {
	local tag short dirty timestamp
	if [ -n "$VERSION" ]; then
		printf '%s\n' "$VERSION"
		return 0
	fi
	if command -v git >/dev/null 2>&1 && [ -d "$REPO_DIR/.git" ]; then
		tag="$(git -C "$REPO_DIR" describe --tags --exact-match 2>/dev/null || true)"
		if [ -n "$tag" ]; then
			printf '%s\n' "$tag"
			return 0
		fi
		short="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || true)"
		if [ -n "$short" ]; then
			dirty=""
			if [ -n "$(git -C "$REPO_DIR" status --porcelain --untracked-files=no 2>/dev/null || true)" ]; then
				dirty="-dirty"
			fi
			printf 'source-%s%s\n' "$short" "$dirty"
			return 0
		fi
	fi
	timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
	printf 'local-%s\n' "$timestamp"
}

install_run() {
	if [ "$DRY_RUN" = "1" ]; then
		printf '+'
		printf ' %q' "$@"
		printf '\n'
	else
		"$@"
	fi
}

install_sha256_file() {
	local file
	file="$1"
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file" | awk '{print $1}'
	elif command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file" | awk '{print $1}'
	else
		install_die "required command not found: shasum or sha256sum"
	fi
}

install_manifest_generate() {
	local core path hash manifest
	core="$1"
	manifest="$core/.devvm-manifest.sha256"
	if [ "$DRY_RUN" = "1" ]; then
		install_log "would write $manifest"
		return 0
	fi
	(
		cd "$core"
		find . -type f ! -name '.devvm-manifest.sha256' -print | LC_ALL=C sort |
			while IFS= read -r path; do
				hash="$(install_sha256_file "$path")"
				printf '%s  %s\n' "$hash" "$path"
			done >"$manifest"
	)
}

install_required_files() {
	local file
	for file in bin/devvm defaults/config.env templates/fedora-vm.yaml.tpl lib/util.sh lib/config.sh lib/update.sh lib/security.sh lib/lima.sh lib/provision.sh lib/vm.sh lib/ai.sh lib/backup.sh lib/gpg.sh lib/completion.sh; do
		[ -f "$REPO_DIR/$file" ] || install_die "missing required repository file: $file"
	done
}

install_syntax_check() {
	local file
	while IFS= read -r file; do
		[ -n "$file" ] || continue
		[ -f "$REPO_DIR/$file" ] || continue
		bash -n "$REPO_DIR/$file"
	done < <("$REPO_DIR/scripts/files.sh")
}

install_copy_tree() {
	local target item
	target="$1"

	install_run rm -rf "$target"
	install_run mkdir -p "$target"
	for item in bin defaults docs lib scripts templates tests install.sh README.md CHANGELOG.md LICENSE; do
		[ -e "$REPO_DIR/$item" ] || continue
		install_run cp -R "$REPO_DIR/$item" "$target/"
	done
	install_run chmod +x "$target/bin/devvm"
	install_run chmod +x "$target/install.sh"
	install_manifest_generate "$target"
}

install_write_metadata() {
	local mode version core previous repo metadata
	mode="$1"
	version="$2"
	core="$3"
	previous="$4"
	repo="$5"
	metadata="$INSTALL_ROOT/install.env"

	if [ "$DRY_RUN" = "1" ]; then
		install_log "would write $metadata"
		return 0
	fi

	cat >"$metadata" <<METADATA
DEVVM_INSTALL_MODE=$(install_shell_quote "$mode")
DEVVM_INSTALL_VERSION=$(install_shell_quote "$version")
DEVVM_INSTALL_ROOT=$(install_shell_quote "$INSTALL_ROOT")
DEVVM_INSTALL_PREFIX=$(install_shell_quote "$PREFIX")
DEVVM_INSTALL_CORE=$(install_shell_quote "$core")
DEVVM_INSTALL_REPO=$(install_shell_quote "$repo")
DEVVM_INSTALL_PREVIOUS_VERSION=$(install_shell_quote "$previous")
DEVVM_INSTALL_SIGNER_FINGERPRINT=''
DEVVM_INSTALL_COMMAND=$(install_shell_quote "$COMMAND_NAME")
DEVVM_INSTALL_CONFIG=$(install_shell_quote "$CONFIG_DIR")
DEVVM_INSTALL_STATE=$(install_shell_quote "$STATE_DIR")
METADATA
}

install_link_bin() {
	local bin_path target current_target
	bin_path="$PREFIX/$COMMAND_NAME"
	target="$1"

	if [ -e "$bin_path" ] || [ -L "$bin_path" ]; then
		if [ -L "$bin_path" ]; then
			current_target="$(readlink "$bin_path")"
			case "$current_target" in
			"$INSTALL_ROOT"/* | "$REPO_DIR/bin/devvm") ;;
			*)
				[ "$FORCE" = "1" ] || install_die "$bin_path already points to $current_target; use --force to replace it"
				;;
			esac
		elif [ -f "$bin_path" ] && grep -Fq '# DEVVM MANAGED LAUNCHER' "$bin_path" 2>/dev/null; then
			:
		else
			[ "$FORCE" = "1" ] || install_die "$bin_path already exists and is not a symlink; use --force to replace it"
		fi
	fi

	install_run mkdir -p "$PREFIX"
	if [ "$DRY_RUN" = "1" ]; then
		install_log "would write launcher $bin_path -> $target"
		return 0
	fi
	rm -f "$bin_path"
	cat >"$bin_path" <<LAUNCHER
#!/usr/bin/env bash
# DEVVM MANAGED LAUNCHER
if [ -z "\${DEVVM_INSTALL_ROOT:-}" ]; then
	DEVVM_INSTALL_ROOT=$(install_shell_quote "$INSTALL_ROOT")
fi
if [ -z "\${DEVVM_CONFIG:-}" ]; then
	DEVVM_CONFIG=$(install_shell_quote "$CONFIG_DIR")
fi
if [ -z "\${DEVVM_STATE:-}" ]; then
	DEVVM_STATE=$(install_shell_quote "$STATE_DIR")
fi
export DEVVM_INSTALL_ROOT DEVVM_CONFIG DEVVM_STATE
exec $(install_shell_quote "$target") "\$@"
LAUNCHER
	chmod 0755 "$bin_path"
}

install_config() {
	install_run mkdir -p "$CONFIG_DIR/vms"
	if [ ! -f "$CONFIG_DIR/config.env" ]; then
		install_run cp "$REPO_DIR/defaults/config.env" "$CONFIG_DIR/config.env"
		if [ -n "$VM_PREFIX_OVERRIDE" ]; then
			if [ "$DRY_RUN" = "1" ]; then
				install_log "would set VM_PREFIX in $CONFIG_DIR/config.env"
			else
				printf '\nVM_PREFIX=%s\n' "$(install_shell_quote "$VM_PREFIX_OVERRIDE")" >>"$CONFIG_DIR/config.env"
			fi
		fi
	fi
}

install_warn_missing_commands() {
	local cmd
	for cmd in limactl ssh; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			install_warn "required command not found in PATH: $cmd"
		fi
	done
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	--copy)
		MODE="copy"
		;;
	--symlink)
		MODE="symlink"
		;;
	--name)
		[ "$#" -gt 1 ] || install_die "--name requires a value"
		COMMAND_NAME="$2"
		shift
		;;
	--prefix)
		[ "$#" -gt 1 ] || install_die "--prefix requires a value"
		PREFIX="$2"
		shift
		;;
	--install-dir)
		[ "$#" -gt 1 ] || install_die "--install-dir requires a value"
		INSTALL_ROOT="$2"
		shift
		;;
	--config-dir)
		[ "$#" -gt 1 ] || install_die "--config-dir requires a value"
		CONFIG_DIR="$2"
		shift
		;;
	--state-dir)
		[ "$#" -gt 1 ] || install_die "--state-dir requires a value"
		STATE_DIR="$2"
		shift
		;;
	--vm-prefix)
		[ "$#" -gt 1 ] || install_die "--vm-prefix requires a value"
		VM_PREFIX_OVERRIDE="$2"
		shift
		;;
	--version)
		[ "$#" -gt 1 ] || install_die "--version requires a value"
		VERSION="$2"
		shift
		;;
	--repo)
		[ "$#" -gt 1 ] || install_die "--repo requires a value"
		REPO_URL="$2"
		shift
		;;
	--force)
		FORCE="1"
		;;
	--dry-run)
		DRY_RUN="1"
		;;
	-h | --help)
		install_usage
		exit 0
		;;
	*)
		install_die "unknown option: $1"
		;;
	esac
	shift
done

install_safe_command_name "$COMMAND_NAME"
case "$PREFIX" in
/*) ;;
*) install_die "--prefix must be an absolute path: $PREFIX" ;;
esac
case "$INSTALL_ROOT" in
/*) ;;
*) install_die "--install-dir must be an absolute path: $INSTALL_ROOT" ;;
esac
case "$CONFIG_DIR" in
/*) ;;
*) install_die "--config-dir must be an absolute path: $CONFIG_DIR" ;;
esac
case "$STATE_DIR" in
/*) ;;
*) install_die "--state-dir must be an absolute path: $STATE_DIR" ;;
esac

install_required_files
install_syntax_check
install_run mkdir -p "$INSTALL_ROOT"
install_config

repo="$(install_repo_url)"
version="$(install_detect_version)"
install_safe_version "$version"

case "$MODE" in
copy)
	version_dir="$INSTALL_ROOT/versions/$version"
	previous=""
	if [ -L "$INSTALL_ROOT/current" ]; then
		previous_target="$(readlink "$INSTALL_ROOT/current")"
		previous="${previous_target##*/}"
	fi
	if [ -e "$version_dir" ] && [ "$FORCE" != "1" ]; then
		install_die "install version already exists: $version_dir; use --force to replace it"
	fi
	install_log "Installing copied DevVM $version into $version_dir"
	install_run mkdir -p "$INSTALL_ROOT/versions"
	install_copy_tree "$version_dir"
	install_run ln -sfn "$version_dir" "$INSTALL_ROOT/current.tmp.$$"
	install_run rm -f "$INSTALL_ROOT/current"
	install_run mv -f "$INSTALL_ROOT/current.tmp.$$" "$INSTALL_ROOT/current"
	install_write_metadata "copy" "$version" "$version_dir" "$previous" "$repo"
	install_link_bin "$INSTALL_ROOT/current/bin/devvm"
	;;
symlink)
	install_log "Installing source DevVM symlink from $REPO_DIR"
	install_write_metadata "source" "$version" "$REPO_DIR" "" "$repo"
	install_link_bin "$REPO_DIR/bin/devvm"
	;;
*)
	install_die "unknown install mode: $MODE"
	;;
esac

install_warn_missing_commands

install_log "Installed $COMMAND_NAME at $PREFIX/$COMMAND_NAME"
install_log "Install root: $INSTALL_ROOT"
install_log "Config dir: $CONFIG_DIR"
install_log "State dir: $STATE_DIR"
install_log "Ensure $PREFIX is in PATH."
install_log "Run '$COMMAND_NAME completion --help' for shell completion setup."

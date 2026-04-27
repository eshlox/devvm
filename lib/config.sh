#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154

DEVVM_CONFIG="${DEVVM_CONFIG:-$HOME/.config/devvm}"
DEVVM_STATE="${DEVVM_STATE:-$HOME/.local/share/devvm-state}"
DEVVM_GENERATED="${DEVVM_GENERATED:-$DEVVM_STATE/generated}"

devvm_load_config() {
	local default_config user_config local_config
	default_config="$DEVVM_CORE/defaults/config.env"
	user_config="$DEVVM_CONFIG/config.env"
	local_config="$DEVVM_CONFIG/local.env"

	devvm_check_required_file "$default_config"
	# shellcheck source=/dev/null
	source "$default_config"

	if [ -f "$user_config" ]; then
		# shellcheck source=/dev/null
		source "$user_config"
	fi

	if [ -f "$local_config" ]; then
		# shellcheck source=/dev/null
		source "$local_config"
	fi

	VM_PREFIX="${VM_PREFIX:-devvm}"
	DEFAULT_DISTRO="${DEFAULT_DISTRO:-fedora}"
	DEFAULT_CPUS="${DEFAULT_CPUS:-4}"
	DEFAULT_MEMORY="${DEFAULT_MEMORY:-8GiB}"
	DEFAULT_DISK="${DEFAULT_DISK:-80GiB}"
	DEFAULT_PORTS="${DEFAULT_PORTS:-}"
	DEFAULT_MOUNTS="${DEFAULT_MOUNTS:-}"
	GLOBAL_PACKAGES="${GLOBAL_PACKAGES:-}"
	GLOBAL_SETUP_SCRIPTS="${GLOBAL_SETUP_SCRIPTS:-}"
	GLOBAL_MOUNTS="${GLOBAL_MOUNTS:-}"
	DEVVM_ALLOW_SENSITIVE_MOUNTS="${DEVVM_ALLOW_SENSITIVE_MOUNTS:-0}"
	LIMA_TEMPLATE="${LIMA_TEMPLATE:-template:fedora}"
	LIMA_ARCH="${LIMA_ARCH:-aarch64}"
	DEVVM_GUEST_USER="${DEVVM_GUEST_USER:-$(devvm_host_user)}"
	DEVVM_GUEST_HOME="${DEVVM_GUEST_HOME:-/home/$DEVVM_GUEST_USER}"
	DEVVM_CODE_DIR="${DEVVM_CODE_DIR:-$DEVVM_GUEST_HOME/code}"
	DEVVM_BACKUP_DIR="${DEVVM_BACKUP_DIR:-$DEVVM_STATE/backups}"
	DEVVM_BACKUP_INCLUDE_SECRETS="${DEVVM_BACKUP_INCLUDE_SECRETS:-1}"
	DEVVM_RESTORE_INCLUDE_SECRETS="${DEVVM_RESTORE_INCLUDE_SECRETS:-1}"
	DEVVM_BACKUP_ENCRYPT="${DEVVM_BACKUP_ENCRYPT:-auto}"
	DEVVM_BACKUP_EXCLUDES="${DEVVM_BACKUP_EXCLUDES:-*/node_modules */.cache */target */.venv}"
	GIT_USER_NAME="${GIT_USER_NAME:-}"
	GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"
	export VM_PREFIX DEFAULT_DISTRO DEFAULT_CPUS DEFAULT_MEMORY DEFAULT_DISK
	export DEFAULT_PORTS DEFAULT_MOUNTS GLOBAL_PACKAGES GLOBAL_SETUP_SCRIPTS
	export GLOBAL_MOUNTS DEVVM_ALLOW_SENSITIVE_MOUNTS
	export LIMA_TEMPLATE LIMA_ARCH DEVVM_CODE_DIR
	export GIT_USER_NAME GIT_USER_EMAIL DEVVM_GUEST_USER
	export DEVVM_GUEST_HOME
	export DEVVM_BACKUP_DIR DEVVM_BACKUP_INCLUDE_SECRETS DEVVM_RESTORE_INCLUDE_SECRETS
	export DEVVM_BACKUP_ENCRYPT DEVVM_BACKUP_EXCLUDES
}

devvm_init() {
	devvm_load_config
	devvm_ensure_dir "$DEVVM_CONFIG/vms"
	devvm_ensure_dir "$DEVVM_STATE"
	devvm_ensure_dir "$DEVVM_GENERATED"

	if [ ! -f "$DEVVM_CONFIG/config.env" ]; then
		cp "$DEVVM_CORE/defaults/config.env" "$DEVVM_CONFIG/config.env"
		devvm_log "created $DEVVM_CONFIG/config.env"
	fi

	if [ ! -f "$DEVVM_CONFIG/local.env" ]; then
		touch "$DEVVM_CONFIG/local.env"
		chmod 0600 "$DEVVM_CONFIG/local.env"
		devvm_log "created $DEVVM_CONFIG/local.env"
	fi

	devvm_log "initialized DevVM config at $DEVVM_CONFIG"
}

devvm_self_update() {
	devvm_require_command git
	if [ ! -d "$DEVVM_CORE/.git" ]; then
		devvm_die "DEVVM_CORE is not a git checkout: $DEVVM_CORE"
	fi
	git -C "$DEVVM_CORE" pull --ff-only
}

#!/usr/bin/env bash
# shellcheck shell=bash

devvm_log() {
	printf '%s\n' "$*"
}

devvm_warn() {
	printf 'devvm: warning: %s\n' "$*" >&2
}

devvm_die() {
	printf 'devvm: error: %s\n' "$*" >&2
	exit 1
}

devvm_command_exists() {
	command -v "$1" >/dev/null 2>&1
}

devvm_require_command() {
	local cmd
	cmd="$1"
	devvm_command_exists "$cmd" || devvm_die "required command not found: $cmd"
}

devvm_validate_name() {
	local name
	name="$1"
	case "$name" in
	'' | *[^a-z0-9-]* | [-]*)
		devvm_die "invalid VM name '$name'; use lowercase letters, numbers, and hyphens"
		;;
	esac
}

devvm_shell_quote() {
	local value
	value="${1:-}"
	printf "'%s'" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
}

devvm_ini_quote() {
	local value
	value="${1:-}"
	value="${value//\\/\\\\}"
	value="${value//\"/\\\"}"
	printf '"%s"' "$value"
}

devvm_json_string() {
	local value
	value="${1:-}"
	value="${value//\\/\\\\}"
	value="${value//\"/\\\"}"
	value="${value//$'\n'/\\n}"
	printf '"%s"' "$value"
}

devvm_ensure_dir() {
	mkdir -p "$1"
}

devvm_yes_requested() {
	[ "${DEVVM_YES:-}" = "1" ] || [ "${DEVVM_ASSUME_YES:-}" = "1" ]
}

devvm_confirm() {
	local prompt answer
	prompt="$1"
	if devvm_yes_requested; then
		return 0
	fi
	printf '%s [y/N] ' "$prompt" >&2
	read -r answer
	case "$answer" in
	y | Y | yes | YES) return 0 ;;
	*) return 1 ;;
	esac
}

devvm_check_required_file() {
	[ -f "$1" ] || devvm_die "missing required file: $1"
}

devvm_host_user() {
	id -un
}

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

devvm_bool() {
	local value name
	value="$1"
	name="$2"
	case "$value" in
	1 | true | yes | on) printf '1\n' ;;
	0 | false | no | off | '') printf '0\n' ;;
	*) devvm_die "$name must be 1 or 0" ;;
	esac
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

devvm_config_quote() {
	local value
	value="${1:-}"
	value="${value//\\/\\\\}"
	value="${value//\"/\\\"}"
	value="${value//$'\n'/\\n}"
	printf '"%s"' "$value"
}

devvm_trim() {
	local value
	value="$1"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s\n' "$value"
}

devvm_expand_config_vars() {
	local value output i char next name rest
	value="$1"
	output=""
	i="0"
	while [ "$i" -lt "${#value}" ]; do
		char="${value:$i:1}"
		if [ "$char" != '$' ]; then
			output="$output$char"
			i=$((i + 1))
			continue
		fi

		next="${value:$((i + 1)):1}"
		if [ "$next" = "{" ]; then
			rest="${value:$((i + 2))}"
			name="${rest%%\}*}"
			[ "${rest#*\}}" != "$rest" ] || devvm_die "unterminated variable expansion in config value: $value"
			case "$name" in
			'' | *[!A-Za-z0-9_]* | [0-9]*) devvm_die "invalid variable name in config value: $name" ;;
			esac
			output="$output${!name-}"
			i=$((i + 3 + ${#name}))
			continue
		fi

		case "$next" in
		[A-Za-z_])
			rest="${value:$((i + 1))}"
			name="$rest"
			name="${name%%[!A-Za-z0-9_]*}"
			output="$output${!name-}"
			i=$((i + 1 + ${#name}))
			;;
		*)
			output="$output$char"
			i=$((i + 1))
			;;
		esac
	done
	printf '%s\n' "$output"
}

devvm_unquote_config_value() {
	local value quote inner
	value="$(devvm_trim "$1")"

	# shellcheck disable=SC2016
	case "$value" in
	*'$('* | *'`'*)
		devvm_die "unsupported shell syntax in config value: $value"
		;;
	esac

	quote="${value:0:1}"
	case "$quote" in
	"'")
		[ "${value: -1}" = "'" ] || devvm_die "unterminated single-quoted config value: $value"
		inner="${value:1:${#value}-2}"
		case "$inner" in
		*"'"*) devvm_die "embedded single quotes are not supported in config values: $value" ;;
		esac
		printf '%s\n' "$inner"
		;;
	'"')
		[ "${value: -1}" = '"' ] || devvm_die "unterminated double-quoted config value: $value"
		inner="${value:1:${#value}-2}"
		inner="${inner//\\n/$'\n'}"
		inner="${inner//\\\"/\"}"
		inner="${inner//\\\\/\\}"
		devvm_expand_config_vars "$inner"
		;;
	*)
		case "$value" in
		*[[:space:]]*) devvm_die "unquoted config values must not contain whitespace: $value" ;;
		esac
		devvm_expand_config_vars "$value"
		;;
	esac
}

devvm_load_env_file() {
	local file line_number line trimmed key value
	file="$1"
	[ -f "$file" ] || devvm_die "missing config file: $file"

	line_number="0"
	while IFS= read -r line || [ -n "$line" ]; do
		line_number=$((line_number + 1))
		trimmed="$(devvm_trim "$line")"
		case "$trimmed" in
		'' | \#*) continue ;;
		export\ *) devvm_die "$file:$line_number: export is not supported; use KEY=value" ;;
		*=*) ;;
		*) devvm_die "$file:$line_number: expected KEY=value" ;;
		esac

		key="${trimmed%%=*}"
		value="${trimmed#*=}"
		key="$(devvm_trim "$key")"
		case "$key" in
		'' | *[!A-Za-z0-9_]* | [0-9]*) devvm_die "$file:$line_number: invalid key: $key" ;;
		esac
		value="$(devvm_unquote_config_value "$value")"
		printf -v "$key" '%s' "$value"
	done <"$file"
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

devvm_file_mode() {
	local path mode
	path="$1"
	if mode="$(stat -f '%Lp' "$path" 2>/dev/null)"; then
		printf '%s\n' "$mode"
	elif mode="$(stat -c '%a' "$path" 2>/dev/null)"; then
		printf '%s\n' "$mode"
	else
		return 1
	fi
}

devvm_mode_has_group_or_world_write() {
	local mode perm
	mode="$1"
	perm=$((8#$mode))
	[ $((perm & 022)) -ne 0 ]
}

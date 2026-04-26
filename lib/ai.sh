#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154

devvm_ai_help() {
	cat <<'HELP'
Usage:
  devvm ai create
  devvm ai update
  devvm ai enter
  devvm ai key
HELP
}

devvm_ai_config_path() {
	devvm_load_config
	printf '%s/vms/%s.env\n' "$DEVVM_CONFIG" "$AI_VM_NAME"
}

devvm_ai_write_config_if_missing() {
	local path
	devvm_load_config
	devvm_validate_name "$AI_VM_NAME"
	devvm_ensure_dir "$DEVVM_CONFIG/vms"
	path="$(devvm_ai_config_path)"

	if [ -f "$path" ]; then
		if ! grep -Eq "^DEVVM_ROLE=['\"]?ai['\"]?$" "$path"; then
			devvm_die "$path exists but is not an AI VM config"
		fi
		return 0
	fi

	{
		printf 'NAME=%s\n' "$(devvm_shell_quote "$AI_VM_NAME")"
		printf 'VM_NAME=%s\n' "$(devvm_shell_quote "${VM_PREFIX}-${AI_VM_NAME}")"
		printf 'DISTRO=%s\n' "$(devvm_shell_quote "$DEFAULT_DISTRO")"
		printf 'DEVVM_ROLE=%s\n' "$(devvm_shell_quote "ai")"
		printf 'CODE_DIR=%s\n' "$(devvm_shell_quote "$AI_VM_CODE_DIR")"
		printf 'CPUS=%s\n' "$(devvm_shell_quote "$AI_VM_CPUS")"
		printf 'MEMORY=%s\n' "$(devvm_shell_quote "$AI_VM_MEMORY")"
		printf 'DISK=%s\n' "$(devvm_shell_quote "$AI_VM_DISK")"
		printf 'NODE_VERSION=%s\n' "$(devvm_shell_quote "$DEFAULT_NODE_VERSION")"
		printf 'PORTS=%s\n' "$(devvm_shell_quote "$AI_LLAMA_SERVER_PORT:$AI_LLAMA_HOST_PORT")"
		printf 'MOUNTS=%s\n' "$(devvm_shell_quote "")"
	} >"$path"

	devvm_log "created $path"
}

devvm_ai_create() {
	devvm_ai_write_config_if_missing
	devvm_create "$AI_VM_NAME"
	devvm_log "llama.cpp API should be reachable from other DevVMs at $AI_LLAMA_BASE_URL"
}

devvm_ai_update() {
	devvm_ai_write_config_if_missing
	devvm_update "$AI_VM_NAME"
}

devvm_ai_enter() {
	devvm_ai_write_config_if_missing
	devvm_enter "$AI_VM_NAME"
}

devvm_ai_key() {
	devvm_ai_write_config_if_missing
	devvm_key "$AI_VM_NAME"
}

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
  devvm ai endpoint
  devvm ai status
  devvm ai logs [--lines N] [--follow]

The AI VM runs llama.cpp as an OpenAI-compatible local API. It does not install
Claude, Codex, Node.js, or editor tooling into development VMs.
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
		devvm_load_vm "$AI_VM_NAME"
		[ "$DEVVM_ROLE" = "ai" ] || devvm_die "$path exists but is not an AI VM config"
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
		printf 'PACKAGES=%s\n' "$(devvm_shell_quote "$AI_LLAMA_PACKAGES")"
		printf 'SETUP_SCRIPTS=%s\n' "$(devvm_shell_quote "")"
		printf 'PORTS=%s\n' "$(devvm_shell_quote "$AI_LLAMA_SERVER_PORT:$AI_LLAMA_HOST_PORT")"
		printf 'MOUNTS=%s\n' "$(devvm_shell_quote "$AI_LLAMA_MOUNTS")"
	} >"$path"

	devvm_log "created $path"
}

devvm_ai_remote_command() {
	cat <<'REMOTE'
set -euo pipefail
models_dir="$1"
model_downloads="$2"
model="$3"
allow_http_model_urls="$4"
server_port="$5"
listen_host="$6"
ctx_size="$7"
extra_args="$8"

die() {
	echo "devvm llama: $*" >&2
	exit 1
}

case "$models_dir" in
	/*) ;;
	*) die "AI_LLAMA_MODELS_DIR must be absolute: $models_dir" ;;
esac
case "$models_dir" in
	*[!A-Za-z0-9._/@+:-]*) die "AI_LLAMA_MODELS_DIR contains unsupported characters: $models_dir" ;;
esac
case "$server_port" in
	'' | *[!0-9]*) die "AI_LLAMA_SERVER_PORT must be numeric: $server_port" ;;
esac
case "$listen_host" in
	'' | *[!A-Za-z0-9.:-]*) die "AI_LLAMA_LISTEN_HOST contains unsupported characters: $listen_host" ;;
esac
case "$ctx_size" in
	'' | *[!0-9]*) die "AI_LLAMA_CTX_SIZE must be numeric: $ctx_size" ;;
esac
service_user="$(id -un)"
service_group="$(id -gn)"
case "$service_user" in
	'' | *[!A-Za-z0-9._-]*) die "unsupported service user name: $service_user" ;;
esac
case "$service_group" in
	'' | *[!A-Za-z0-9._-]*) die "unsupported service group name: $service_group" ;;
esac
case "$extra_args" in
	*$'\n'* | *$'\r'*) die "AI_LLAMA_EXTRA_ARGS must not contain newlines" ;;
esac

if [ ! -d "$models_dir" ]; then
	sudo install -d -o "$service_user" -g "$service_group" -m 0755 "$models_dir"
fi

if ! command -v llama-server >/dev/null 2>&1; then
	die "llama-server is not installed; keep llama-cpp in PACKAGES for the AI VM"
fi

first_model=""
if [ -n "$model_downloads" ]; then
	if ! command -v curl >/dev/null 2>&1; then
		die "curl is not installed; it is required for AI_LLAMA_MODELS downloads"
	fi
	if ! command -v sha256sum >/dev/null 2>&1; then
		die "sha256sum is not installed; it is required for AI_LLAMA_MODELS downloads"
	fi

	for entry in $model_downloads; do
		case "$entry" in
			'' | \#*) continue ;;
		esac

		name=""
		url=""
		checksum=""
		extra=""
		IFS='|' read -r name url checksum extra <<ENTRY
$entry
ENTRY

		[ -n "$name" ] || die "invalid AI_LLAMA_MODELS entry; missing file name: $entry"
		[ -n "$url" ] || die "invalid AI_LLAMA_MODELS entry; missing URL: $entry"
		[ -n "$checksum" ] || die "AI_LLAMA_MODELS entries must include sha256:<hex>: $entry"
		[ -z "$extra" ] || die "invalid AI_LLAMA_MODELS entry; too many fields: $entry"

		case "$name" in
			*/* | *[!A-Za-z0-9._@+-]*) die "invalid model file name in AI_LLAMA_MODELS entry: $name" ;;
		esac
		case "$url" in
			https://*) ;;
			http://*)
				[ "$allow_http_model_urls" = "1" ] || die "model URLs must use https unless AI_ALLOW_HTTP_MODEL_URLS=1: $url"
				;;
			*) die "model URLs must use https: $url" ;;
		esac
		case "$checksum" in
			sha256:*)
				expected="${checksum#sha256:}"
				[ "${#expected}" -eq 64 ] || die "sha256 checksums must be 64 hex characters: $entry"
				case "$expected" in
					*[!0-9a-fA-F]*) die "invalid sha256 checksum in AI_LLAMA_MODELS entry: $entry" ;;
				esac
				;;
			*) die "unsupported checksum in AI_LLAMA_MODELS entry; use sha256:<hex>: $entry" ;;
		esac

		target="$models_dir/$name"
		if [ ! -f "$target" ]; then
			curl -fL --continue-at - -o "$target" "$url"
		fi
		printf '%s  %s\n' "$expected" "$target" | sha256sum -c -

		if [ -z "$first_model" ]; then
			first_model="$name"
		fi
	done
fi

if [ -z "$model" ]; then
	model="$first_model"
fi

if [ -z "$model" ]; then
	echo "devvm llama: AI_LLAMA_MODEL is not set; llama.cpp is installed but devvm-llama.service was not started" >&2
	sudo systemctl disable --now devvm-llama.service >/dev/null 2>&1 || true
	exit 0
fi

case "$model" in
	/*)
		model_path="$model"
		;;
	*/* | *[!A-Za-z0-9._@+-]*)
		die "AI_LLAMA_MODEL must be an absolute path or a safe file name under AI_LLAMA_MODELS_DIR: $model"
		;;
	*)
		model_path="$models_dir/$model"
		;;
esac

case "$model_path" in
	*[!A-Za-z0-9._/@+:-]*) die "model path contains unsupported characters: $model_path" ;;
esac
[ -f "$model_path" ] || die "model file not found: $model_path"

server="$(command -v llama-server)"
unit="$(mktemp)"
trap 'rm -f "$unit"' EXIT

cat >"$unit" <<UNIT
[Unit]
Description=DevVM llama.cpp OpenAI-compatible server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$service_user
WorkingDirectory=$models_dir
ExecStart=$server --host $listen_host --port $server_port -m $model_path -c $ctx_size $extra_args
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

sudo install -m 0644 "$unit" /etc/systemd/system/devvm-llama.service
sudo systemctl daemon-reload
sudo systemctl enable --now devvm-llama.service
sudo systemctl restart devvm-llama.service
REMOTE
}

devvm_ai_provision_llama() {
	local name remote
	name="$1"
	devvm_load_vm "$name"
	[ "$DEVVM_ROLE" = "ai" ] || return 0

	remote="$(devvm_ai_remote_command)"
	devvm_log "configuring llama.cpp service in $VM_NAME"
	limactl shell "$VM_NAME" bash -c "$remote" devvm-ai \
		"$AI_LLAMA_MODELS_DIR" \
		"$AI_LLAMA_MODELS" \
		"$AI_LLAMA_MODEL" \
		"$AI_ALLOW_HTTP_MODEL_URLS" \
		"$AI_LLAMA_SERVER_PORT" \
		"$AI_LLAMA_LISTEN_HOST" \
		"$AI_LLAMA_CTX_SIZE" \
		"$AI_LLAMA_EXTRA_ARGS"
}

devvm_post_provision() {
	local name
	name="$1"
	devvm_load_vm "$name"
	if [ "$DEVVM_ROLE" = "ai" ]; then
		devvm_ai_provision_llama "$name"
	fi
}

devvm_ai_create() {
	devvm_ai_write_config_if_missing
	devvm_create "$AI_VM_NAME"
	devvm_log "llama.cpp API endpoint: $AI_LLAMA_BASE_URL"
}

devvm_ai_update() {
	devvm_ai_write_config_if_missing
	devvm_update "$AI_VM_NAME"
	devvm_log "llama.cpp API endpoint: $AI_LLAMA_BASE_URL"
}

devvm_ai_enter() {
	devvm_ai_write_config_if_missing
	devvm_enter "$AI_VM_NAME"
}

devvm_ai_key() {
	devvm_ai_write_config_if_missing
	devvm_key "$AI_VM_NAME"
}

devvm_ai_endpoint() {
	devvm_load_config
	printf '%s\n' "$AI_LLAMA_BASE_URL"
}

devvm_ai_status() {
	devvm_ai_write_config_if_missing
	devvm_require_command limactl
	devvm_load_vm "$AI_VM_NAME"
	devvm_lima_require_instance "$VM_NAME"
	limactl shell "$VM_NAME" sudo systemctl status devvm-llama.service --no-pager
}

devvm_ai_logs() {
	local lines follow arg
	lines="100"
	follow="0"
	while [ "$#" -gt 0 ]; do
		arg="$1"
		shift
		case "$arg" in
		--lines)
			[ "$#" -gt 0 ] || devvm_die "--lines requires a value"
			lines="$1"
			shift
			;;
		--follow | -f)
			follow="1"
			;;
		*) devvm_die "unknown option: $arg" ;;
		esac
	done
	case "$lines" in
	'' | *[!0-9]*) devvm_die "--lines must be numeric" ;;
	esac

	devvm_ai_write_config_if_missing
	devvm_require_command limactl
	devvm_load_vm "$AI_VM_NAME"
	devvm_lima_require_instance "$VM_NAME"
	if [ "$follow" = "1" ]; then
		limactl shell "$VM_NAME" sudo journalctl -u devvm-llama.service -n "$lines" -f
	else
		limactl shell "$VM_NAME" sudo journalctl -u devvm-llama.service -n "$lines" --no-pager
	fi
}

devvm_ai() {
	local cmd
	cmd="${1:-help}"
	if [ "$#" -gt 0 ]; then
		shift
	fi

	case "$cmd" in
	create)
		devvm_ai_create "$@"
		;;
	update)
		devvm_ai_update "$@"
		;;
	enter)
		devvm_ai_enter "$@"
		;;
	key)
		devvm_ai_key "$@"
		;;
	endpoint)
		devvm_ai_endpoint "$@"
		;;
	status)
		devvm_ai_status "$@"
		;;
	logs)
		devvm_ai_logs "$@"
		;;
	help | -h | --help)
		devvm_ai_help
		;;
	*)
		devvm_ai_help
		devvm_die "unknown ai command: $cmd"
		;;
	esac
}

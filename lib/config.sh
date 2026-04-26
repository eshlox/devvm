#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154

DEVVM_CONFIG="${DEVVM_CONFIG:-$HOME/.config/devvm}"
DEVVM_STATE="${DEVVM_STATE:-$HOME/.local/share/devvm-state}"
DEVVM_GENERATED="${DEVVM_GENERATED:-$DEVVM_STATE/generated}"

devvm_load_config() {
	local default_config user_config local_config first_model clean_model_url
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
	DEVVM_UPGRADE_PACKAGES="${DEVVM_UPGRADE_PACKAGES:-0}"
	DEFAULT_NODE_VERSION="${DEFAULT_NODE_VERSION:-}"
	DEFAULT_PORTS="${DEFAULT_PORTS:-}"
	DEFAULT_MOUNTS="${DEFAULT_MOUNTS:-}"
	GLOBAL_MOUNTS="${GLOBAL_MOUNTS:-}"
	DEVVM_ALLOW_SENSITIVE_MOUNTS="${DEVVM_ALLOW_SENSITIVE_MOUNTS:-0}"
	LIMA_TEMPLATE="${LIMA_TEMPLATE:-template:fedora}"
	LIMA_ARCH="${LIMA_ARCH:-aarch64}"
	DEVVM_GUEST_USER="${DEVVM_GUEST_USER:-$(devvm_host_user)}"
	DEVVM_GUEST_HOME="${DEVVM_GUEST_HOME:-/home/$DEVVM_GUEST_USER}"
	DEVVM_CODE_DIR="${DEVVM_CODE_DIR:-$DEVVM_GUEST_HOME/code}"
	GIT_USER_NAME="${GIT_USER_NAME:-}"
	GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"
	CHEZMOI_MODE="${CHEZMOI_MODE:-defaults}"
	CHEZMOI_REPO="${CHEZMOI_REPO:-}"
	CHEZMOI_BRANCH="${CHEZMOI_BRANCH:-main}"
	CHEZMOI_APPLY_ARGS="${CHEZMOI_APPLY_ARGS:---force}"
	ANSIBLE_FORKS="${ANSIBLE_FORKS:-5}"
	ANSIBLE_VERBOSITY="${ANSIBLE_VERBOSITY:-}"
	AI_TOOLS="${AI_TOOLS:-}"
	AI_EXTRA_NPM_PACKAGES="${AI_EXTRA_NPM_PACKAGES:-}"
	AI_VM_NAME="${AI_VM_NAME:-ai}"
	AI_VM_CPUS="${AI_VM_CPUS:-6}"
	AI_VM_MEMORY="${AI_VM_MEMORY:-12GiB}"
	AI_VM_DISK="${AI_VM_DISK:-120GiB}"
	AI_VM_CODE_DIR="${AI_VM_CODE_DIR:-/srv/ai}"
	AI_LLAMA_CPP_REPO="${AI_LLAMA_CPP_REPO:-https://github.com/ggml-org/llama.cpp.git}"
	AI_LLAMA_CPP_REF="${AI_LLAMA_CPP_REF:-master}"
	AI_LLAMA_MODELS="${AI_LLAMA_MODELS:-}"
	AI_ALLOW_INSECURE_MODEL_URLS="${AI_ALLOW_INSECURE_MODEL_URLS:-0}"
	AI_LLAMA_MODELS_DIR="${AI_LLAMA_MODELS_DIR:-/models}"
	AI_LLAMA_SERVER_PORT="${AI_LLAMA_SERVER_PORT:-8080}"
	AI_LLAMA_HOST_PORT="${AI_LLAMA_HOST_PORT:-18080}"
	AI_LLAMA_CTX_SIZE="${AI_LLAMA_CTX_SIZE:-4096}"
	AI_LLAMA_EXTRA_ARGS="${AI_LLAMA_EXTRA_ARGS:-}"
	AI_LLAMA_BASE_URL="${AI_LLAMA_BASE_URL:-http://host.lima.internal:$AI_LLAMA_HOST_PORT/v1}"
	AI_COMMIT_MODEL="${AI_COMMIT_MODEL:-}"
	if [ -z "$AI_COMMIT_MODEL" ] && [ -n "$AI_LLAMA_MODELS" ]; then
		first_model="${AI_LLAMA_MODELS%% *}"
		if [ "${first_model#*|}" != "$first_model" ]; then
			AI_COMMIT_MODEL="${first_model%%|*}"
		else
			clean_model_url="${first_model%%\?*}"
			AI_COMMIT_MODEL="$(basename "$clean_model_url")"
		fi
	fi
	export VM_PREFIX DEFAULT_DISTRO DEFAULT_CPUS DEFAULT_MEMORY DEFAULT_DISK
	export DEVVM_UPGRADE_PACKAGES DEFAULT_NODE_VERSION DEFAULT_PORTS DEFAULT_MOUNTS GLOBAL_MOUNTS DEVVM_ALLOW_SENSITIVE_MOUNTS
	export LIMA_TEMPLATE LIMA_ARCH DEVVM_CODE_DIR
	export GIT_USER_NAME GIT_USER_EMAIL CHEZMOI_MODE CHEZMOI_REPO CHEZMOI_BRANCH
	export CHEZMOI_APPLY_ARGS ANSIBLE_FORKS ANSIBLE_VERBOSITY DEVVM_GUEST_USER
	export DEVVM_GUEST_HOME
	export AI_TOOLS AI_EXTRA_NPM_PACKAGES AI_VM_NAME AI_VM_CPUS AI_VM_MEMORY AI_VM_DISK
	export AI_VM_CODE_DIR AI_LLAMA_CPP_REPO AI_LLAMA_CPP_REF AI_LLAMA_MODELS AI_ALLOW_INSECURE_MODEL_URLS
	export AI_LLAMA_MODELS_DIR AI_LLAMA_SERVER_PORT AI_LLAMA_HOST_PORT AI_LLAMA_CTX_SIZE
	export AI_LLAMA_EXTRA_ARGS AI_LLAMA_BASE_URL AI_COMMIT_MODEL
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

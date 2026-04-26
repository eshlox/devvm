#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2153,SC2154

devvm_vm_names() {
	local file base
	devvm_load_config
	if [ ! -d "$DEVVM_CONFIG/vms" ]; then
		return 0
	fi
	for file in "$DEVVM_CONFIG"/vms/*.env; do
		[ -e "$file" ] || continue
		base="$(basename "$file")"
		printf '%s\n' "${base%.env}"
	done
}

devvm_inventory_line() {
	local ssh_config
	ssh_config="$HOME/.lima/$VM_NAME/ssh.config"
	printf '%s ansible_host=%s ansible_ssh_common_args=%s' \
		"$VM_NAME" \
		"lima-$VM_NAME" \
		"$(devvm_ini_quote "-F $ssh_config")"
	printf ' devvm_name=%s' "$(devvm_ini_quote "$NAME")"
	printf ' devvm_role=%s' "$(devvm_ini_quote "$DEVVM_ROLE")"
	printf ' code_dir=%s' "$(devvm_ini_quote "$CODE_DIR")"
	printf ' node_version=%s' "$(devvm_ini_quote "$NODE_VERSION")"
	printf ' git_user_name=%s' "$(devvm_ini_quote "$GIT_USER_NAME")"
	printf ' git_user_email=%s' "$(devvm_ini_quote "$GIT_USER_EMAIL")"
	printf ' chezmoi_mode=%s' "$(devvm_ini_quote "$CHEZMOI_MODE")"
	printf ' chezmoi_repo=%s' "$(devvm_ini_quote "$CHEZMOI_REPO")"
	printf ' chezmoi_branch=%s' "$(devvm_ini_quote "$CHEZMOI_BRANCH")"
	printf ' chezmoi_apply_args=%s' "$(devvm_ini_quote "$CHEZMOI_APPLY_ARGS")"
	printf ' ai_tools=%s' "$(devvm_ini_quote "$AI_TOOLS")"
	printf ' ai_extra_npm_packages=%s' "$(devvm_ini_quote "$AI_EXTRA_NPM_PACKAGES")"
	printf ' ai_llama_cpp_repo=%s' "$(devvm_ini_quote "$AI_LLAMA_CPP_REPO")"
	printf ' ai_llama_cpp_ref=%s' "$(devvm_ini_quote "$AI_LLAMA_CPP_REF")"
	printf ' ai_llama_models=%s' "$(devvm_ini_quote "$AI_LLAMA_MODELS")"
	printf ' ai_llama_models_dir=%s' "$(devvm_ini_quote "$AI_LLAMA_MODELS_DIR")"
	printf ' ai_llama_server_port=%s' "$(devvm_ini_quote "$AI_LLAMA_SERVER_PORT")"
	printf ' ai_llama_ctx_size=%s' "$(devvm_ini_quote "$AI_LLAMA_CTX_SIZE")"
	printf ' ai_llama_extra_args=%s' "$(devvm_ini_quote "$AI_LLAMA_EXTRA_ARGS")"
	printf ' ai_llama_base_url=%s' "$(devvm_ini_quote "$AI_LLAMA_BASE_URL")"
	printf ' ai_commit_model=%s' "$(devvm_ini_quote "$AI_COMMIT_MODEL")"
	printf ' devvm_core=%s' "$(devvm_ini_quote "$DEVVM_CORE")"
	printf '\n'
}

devvm_generate_inventory() {
	local inventory name
	inventory="$DEVVM_GENERATED/inventory.ini"
	devvm_load_config
	devvm_ensure_dir "$DEVVM_GENERATED"

	{
		printf '[devvms]\n'
		if [ "$#" -gt 0 ]; then
			for name in "$@"; do
				devvm_load_vm "$name"
				devvm_inventory_line
			done
		else
			for name in $(devvm_vm_names); do
				devvm_load_vm "$name"
				devvm_inventory_line
			done
		fi
		printf '\n[devvms:vars]\n'
		printf 'ansible_user=%s\n' "$(devvm_ini_quote "$DEVVM_GUEST_USER")"
		printf 'ansible_python_interpreter=/usr/bin/python3\n'
	} >"$inventory"

	printf '%s\n' "$inventory"
}

devvm_run_ansible() {
	local name inventory
	local cmd
	name="$1"
	devvm_require_command ansible-playbook
	devvm_load_vm "$name"
	inventory="$(devvm_generate_inventory "$name")"
	cmd=(
		ansible-playbook
		-i "$inventory"
		"$DEVVM_CORE/ansible/site.yml"
		--limit "$VM_NAME"
		--forks "$ANSIBLE_FORKS"
	)
	if [ -n "${ANSIBLE_VERBOSITY:-}" ]; then
		cmd+=("$ANSIBLE_VERBOSITY")
	fi
	ANSIBLE_CONFIG="$DEVVM_CORE/ansible/ansible.cfg" "${cmd[@]}"
}

devvm_run_ansible_all() {
	local inventory
	local cmd
	devvm_require_command ansible-playbook
	inventory="$(devvm_generate_inventory "$@")"
	cmd=(
		ansible-playbook
		-i "$inventory"
		"$DEVVM_CORE/ansible/site.yml"
		--forks "$ANSIBLE_FORKS"
	)
	if [ -n "${ANSIBLE_VERBOSITY:-}" ]; then
		cmd+=("$ANSIBLE_VERBOSITY")
	fi
	ANSIBLE_CONFIG="$DEVVM_CORE/ansible/ansible.cfg" "${cmd[@]}"
}

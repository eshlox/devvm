#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154

devvm_vm_config_path() {
	local name
	name="$1"
	printf '%s/vms/%s.env\n' "$DEVVM_CONFIG" "$name"
}

devvm_vm_exists() {
	local name config_dir
	name="$1"
	case "$name" in
	'' | *[^a-z0-9-]* | [-]*) return 1 ;;
	esac
	config_dir="${DEVVM_CONFIG:-$HOME/.config/devvm}"
	[ -f "$config_dir/vms/$name.env" ]
}

devvm_load_vm() {
	local name vm_config combined_mounts
	name="$1"
	devvm_validate_name "$name"
	devvm_load_config

	NAME="$name"
	VM_NAME="${VM_PREFIX}-${name}"
	DISTRO="$DEFAULT_DISTRO"
	CODE_DIR="$DEVVM_CODE_DIR"
	CPUS="$DEFAULT_CPUS"
	MEMORY="$DEFAULT_MEMORY"
	DISK="$DEFAULT_DISK"
	NODE_VERSION="$DEFAULT_NODE_VERSION"
	PORTS="$DEFAULT_PORTS"
	MOUNTS="$DEFAULT_MOUNTS"
	DEVVM_ROLE="dev"

	vm_config="$(devvm_vm_config_path "$name")"
	[ -f "$vm_config" ] || devvm_die "missing VM config: $vm_config; create it with 'devvm new $name'"
	# shellcheck source=/dev/null
	source "$vm_config"

	combined_mounts="${GLOBAL_MOUNTS:-} ${MOUNTS:-}"
	EFFECTIVE_MOUNTS="${combined_mounts#"${combined_mounts%%[![:space:]]*}"}"

	export NAME VM_NAME DISTRO CODE_DIR CPUS MEMORY DISK NODE_VERSION PORTS MOUNTS
	export EFFECTIVE_MOUNTS
	export DEVVM_ROLE
}

devvm_new() {
	local name ports cpus memory disk node_version mounts path arg
	[ "$#" -ge 1 ] || devvm_die "usage: devvm new <name> [--ports \"3000 5173\"] [--mount host:guest[:ro|rw]]"

	name="$1"
	shift
	devvm_validate_name "$name"
	devvm_load_config

	ports="$DEFAULT_PORTS"
	cpus="$DEFAULT_CPUS"
	memory="$DEFAULT_MEMORY"
	disk="$DEFAULT_DISK"
	node_version="$DEFAULT_NODE_VERSION"
	mounts="$DEFAULT_MOUNTS"

	while [ "$#" -gt 0 ]; do
		arg="$1"
		shift
		case "$arg" in
		--ports)
			[ "$#" -gt 0 ] || devvm_die "--ports requires a value"
			ports="$1"
			shift
			;;
		--cpus)
			[ "$#" -gt 0 ] || devvm_die "--cpus requires a value"
			cpus="$1"
			shift
			;;
		--memory)
			[ "$#" -gt 0 ] || devvm_die "--memory requires a value"
			memory="$1"
			shift
			;;
		--disk)
			[ "$#" -gt 0 ] || devvm_die "--disk requires a value"
			disk="$1"
			shift
			;;
		--node-version)
			[ "$#" -gt 0 ] || devvm_die "--node-version requires a value"
			node_version="$1"
			shift
			;;
		--mount | --share)
			[ "$#" -gt 0 ] || devvm_die "$arg requires a value"
			devvm_validate_mount_spec "$1"
			mounts="${mounts:+$mounts }$1"
			shift
			;;
		--*)
			devvm_die "unknown option: $arg"
			;;
		*)
			devvm_die "unexpected argument: $arg"
			;;
		esac
	done

	devvm_ensure_dir "$DEVVM_CONFIG/vms"
	path="$(devvm_vm_config_path "$name")"
	[ ! -e "$path" ] || devvm_die "VM config already exists: $path"

	{
		printf 'NAME=%s\n' "$(devvm_shell_quote "$name")"
		printf 'VM_NAME=%s\n' "$(devvm_shell_quote "${VM_PREFIX}-${name}")"
		printf 'DISTRO=%s\n' "$(devvm_shell_quote "$DEFAULT_DISTRO")"
		printf 'DEVVM_ROLE=%s\n' "$(devvm_shell_quote "dev")"
		# shellcheck disable=SC2016
		printf 'CODE_DIR="$DEVVM_CODE_DIR"\n'
		printf 'CPUS=%s\n' "$(devvm_shell_quote "$cpus")"
		printf 'MEMORY=%s\n' "$(devvm_shell_quote "$memory")"
		printf 'DISK=%s\n' "$(devvm_shell_quote "$disk")"
		printf 'NODE_VERSION=%s\n' "$(devvm_shell_quote "$node_version")"
		printf 'PORTS=%s\n' "$(devvm_shell_quote "$ports")"
		printf 'MOUNTS=%s\n' "$(devvm_shell_quote "$mounts")"
	} >"$path"

	devvm_log "created $path"
}

devvm_create() {
	local name yaml arg
	[ "$#" -ge 1 ] || devvm_die "usage: devvm create <name>"
	name="$1"
	shift

	while [ "$#" -gt 0 ]; do
		arg="$1"
		shift
		case "$arg" in
		*) devvm_die "unknown option: $arg" ;;
		esac
	done

	devvm_require_command limactl
	devvm_load_vm "$name"
	devvm_lima_validate_template

	if devvm_lima_instance_exists "$VM_NAME"; then
		devvm_log "Lima instance already exists: $VM_NAME"
	else
		yaml="$(devvm_render_project_yaml)"
		devvm_log "creating $VM_NAME from $LIMA_TEMPLATE (audit: $yaml)"
		devvm_lima_create_instance
	fi

	limactl start "$VM_NAME"
	devvm_run_ansible "$name"
	devvm_log "VM ready: $VM_NAME"
	if [ "$DEVVM_ROLE" = "ai" ]; then
		devvm_log "AI service VM is managed by Ansible; enter with 'devvm enter $name' for maintenance."
	else
		devvm_log "Enter with 'devvm enter $name', then clone repositories under $CODE_DIR inside the VM."
	fi
}

devvm_start() {
	local name
	[ "$#" -eq 1 ] || devvm_die "usage: devvm start <name>"
	name="$1"
	devvm_require_command limactl
	devvm_load_vm "$name"
	limactl start "$VM_NAME"
}

devvm_stop() {
	local name vm
	[ "$#" -eq 1 ] || devvm_die "usage: devvm stop <name|all>"
	name="$1"
	devvm_require_command limactl

	if [ "$name" = "all" ]; then
		for vm in $(devvm_vm_names); do
			devvm_load_vm "$vm"
			if devvm_lima_instance_exists "$VM_NAME"; then
				limactl stop "$VM_NAME"
			fi
		done
		return 0
	fi

	devvm_load_vm "$name"
	devvm_lima_require_instance "$VM_NAME"
	limactl stop "$VM_NAME"
}

devvm_delete() {
	local name yes backup include_secrets encrypt_mode prompt
	[ "$#" -ge 1 ] || devvm_die "usage: devvm delete <name> [--yes] [--backup|--no-backup] [--include-secrets|--no-secrets] [--encrypt|--no-encrypt]"
	name="$1"
	shift
	yes="0"
	backup="1"
	include_secrets=""
	encrypt_mode=""

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--yes | -y) yes="1" ;;
		--backup) backup="1" ;;
		--no-backup) backup="0" ;;
		--include-secrets) include_secrets="1" ;;
		--no-secrets) include_secrets="0" ;;
		--encrypt) encrypt_mode="1" ;;
		--no-encrypt) encrypt_mode="0" ;;
		*) devvm_die "unknown option: $1" ;;
		esac
		shift
	done

	devvm_require_command limactl
	devvm_load_vm "$name"

	if ! devvm_lima_instance_exists "$VM_NAME"; then
		devvm_log "Lima instance does not exist: $VM_NAME"
		return 0
	fi

	if [ "$backup" = "1" ]; then
		prompt="Back up and delete Lima instance $VM_NAME?"
	else
		prompt="Delete Lima instance $VM_NAME without backup? VM-local repos, keys, shell history, and GPG data will be lost."
	fi

	if [ "$yes" = "1" ] || devvm_confirm "$prompt"; then
		if [ "$backup" = "1" ]; then
			devvm_backup_create "$name" "$include_secrets" "$encrypt_mode" ""
		fi
		limactl delete --force "$VM_NAME"
	else
		devvm_die "delete cancelled"
	fi
}

devvm_ssh() {
	local name
	[ "$#" -ge 1 ] || devvm_die "usage: devvm ssh <name> [command...]"
	name="$1"
	shift
	devvm_require_command limactl
	devvm_load_vm "$name"
	devvm_lima_require_instance "$VM_NAME"

	if [ "$#" -gt 0 ]; then
		limactl shell "$VM_NAME" "$@"
	else
		limactl shell "$VM_NAME"
	fi
}

devvm_enter() {
	local name quoted_path remote_cmd
	[ "$#" -ge 1 ] || devvm_die "usage: devvm enter <name>"
	name="$1"
	shift
	devvm_require_command limactl
	devvm_load_vm "$name"
	devvm_lima_require_instance "$VM_NAME"

	quoted_path="$(devvm_shell_quote "$CODE_DIR")"
	remote_cmd="mkdir -p $quoted_path; cd $quoted_path 2>/dev/null || cd; exec \${SHELL:-/bin/bash} -l"
	limactl shell "$VM_NAME" bash -lc "$remote_cmd"
}

devvm_update() {
	local name
	[ "$#" -eq 1 ] || devvm_die "usage: devvm update <name>"
	name="$1"
	devvm_require_command limactl
	devvm_load_vm "$name"
	devvm_lima_require_instance "$VM_NAME"
	limactl start "$VM_NAME"
	devvm_run_ansible "$name"
}

devvm_update_all() {
	local vm found
	local -a vms
	found="0"
	vms=()
	devvm_require_command limactl
	for vm in $(devvm_vm_names); do
		devvm_load_vm "$vm"
		if devvm_lima_instance_exists "$VM_NAME"; then
			found="1"
			vms+=("$vm")
			limactl start "$VM_NAME"
		fi
	done
	[ "$found" = "1" ] || devvm_die "no existing DevVM Lima instances found for configs in $DEVVM_CONFIG/vms"
	devvm_run_ansible_all "${vms[@]}"
}

devvm_rebuild() {
	local name yes backup restore include_secrets encrypt_mode backup_file prompt
	[ "$#" -ge 1 ] || devvm_die "usage: devvm rebuild <name> [--yes] [--backup|--no-backup] [--restore|--no-restore] [--include-secrets|--no-secrets] [--encrypt|--no-encrypt]"
	name="$1"
	shift
	yes="0"
	backup="1"
	restore="1"
	include_secrets=""
	encrypt_mode=""
	backup_file=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--yes | -y) yes="1" ;;
		--backup) backup="1" ;;
		--no-backup) backup="0" ;;
		--restore) restore="1" ;;
		--no-restore) restore="0" ;;
		--include-secrets) include_secrets="1" ;;
		--no-secrets) include_secrets="0" ;;
		--encrypt) encrypt_mode="1" ;;
		--no-encrypt) encrypt_mode="0" ;;
		*) devvm_die "unknown option: $1" ;;
		esac
		shift
	done

	devvm_require_command limactl
	devvm_load_vm "$name"
	if devvm_lima_instance_exists "$VM_NAME"; then
		if [ "$backup" = "1" ]; then
			prompt="Back up, rebuild, and restore Lima instance $VM_NAME?"
		else
			prompt="Rebuild Lima instance $VM_NAME without backup? VM-local repos, keys, shell history, and GPG data will be lost."
		fi
		if [ "$yes" = "1" ] || devvm_confirm "$prompt"; then
			if [ "$backup" = "1" ]; then
				devvm_backup_create "$name" "$include_secrets" "$encrypt_mode" ""
				backup_file="$DEVVM_LAST_BACKUP_FILE"
			fi
			devvm_delete "$name" --yes --no-backup
		else
			devvm_die "rebuild cancelled"
		fi
	else
		devvm_log "Lima instance does not exist: $VM_NAME"
	fi

	devvm_create "$name"
	if [ "$restore" = "1" ] && [ -n "$backup_file" ]; then
		devvm_restore_file "$name" "$backup_file" "$include_secrets"
	fi
}

devvm_rebuild_all() {
	local vm yes found backup restore include_secrets encrypt_mode
	local -a rebuild_args
	yes="0"
	found="0"
	backup="1"
	restore="1"
	include_secrets=""
	encrypt_mode=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--yes | -y) yes="1" ;;
		--backup) backup="1" ;;
		--no-backup) backup="0" ;;
		--restore) restore="1" ;;
		--no-restore) restore="0" ;;
		--include-secrets) include_secrets="1" ;;
		--no-secrets) include_secrets="0" ;;
		--encrypt) encrypt_mode="1" ;;
		--no-encrypt) encrypt_mode="0" ;;
		*) devvm_die "unknown option: $1" ;;
		esac
		shift
	done

	for vm in $(devvm_vm_names); do
		found="1"
		rebuild_args=()
		if [ "$yes" = "1" ]; then
			rebuild_args+=(--yes)
		fi
		if [ "$backup" = "1" ]; then
			rebuild_args+=(--backup)
		else
			rebuild_args+=(--no-backup)
		fi
		if [ "$restore" = "1" ]; then
			rebuild_args+=(--restore)
		else
			rebuild_args+=(--no-restore)
		fi
		if [ "$include_secrets" = "1" ]; then
			rebuild_args+=(--include-secrets)
		elif [ "$include_secrets" = "0" ]; then
			rebuild_args+=(--no-secrets)
		fi
		if [ "$encrypt_mode" = "1" ]; then
			rebuild_args+=(--encrypt)
		elif [ "$encrypt_mode" = "0" ]; then
			rebuild_args+=(--no-encrypt)
		fi
		devvm_rebuild "$vm" "${rebuild_args[@]}"
	done
	[ "$found" = "1" ] || devvm_die "no VM configs found in $DEVVM_CONFIG/vms"
}

devvm_key() {
	local name key_path quoted_name remote_cmd
	[ "$#" -eq 1 ] || devvm_die "usage: devvm key <name>"
	name="$1"
	devvm_require_command limactl
	devvm_load_vm "$name"
	devvm_lima_require_instance "$VM_NAME"

	key_path="\$HOME/.ssh/id_ed25519_$NAME"
	quoted_name="$(devvm_shell_quote "$NAME")"
	remote_cmd="set -e; mkdir -p \"\$HOME/.ssh\"; chmod 700 \"\$HOME/.ssh\"; if [ ! -f \"\$HOME/.ssh/id_ed25519_$NAME\" ]; then ssh-keygen -t ed25519 -C ${quoted_name}-devvm -f \"\$HOME/.ssh/id_ed25519_$NAME\" -N ''; fi; cat \"\$HOME/.ssh/id_ed25519_$NAME.pub\""
	devvm_log "public key for $NAME ($key_path inside VM):"
	limactl shell "$VM_NAME" bash -lc "$remote_cmd"
}

devvm_doctor() {
	local missing system machine lima_major
	missing="0"
	system="$(uname -s)"
	machine="$(uname -m)"
	devvm_load_config
	devvm_log "host: $system $machine"

	for cmd in limactl ansible-playbook ssh git; do
		if devvm_command_exists "$cmd"; then
			devvm_log "ok: $cmd"
		else
			devvm_warn "missing: $cmd"
			missing="1"
		fi
	done

	if devvm_command_exists limactl; then
		if lima_major="$(devvm_lima_version_major)"; then
			if [ "$lima_major" -lt 2 ]; then
				devvm_warn "Lima 2.x or newer is required; found major version $lima_major"
				missing="1"
			fi
		else
			devvm_warn "could not parse limactl version"
		fi

		if limactl template yq "$LIMA_TEMPLATE" '.images | length' >/dev/null 2>&1; then
			devvm_log "ok: Lima template $LIMA_TEMPLATE"
		else
			devvm_warn "could not inspect Lima template: $LIMA_TEMPLATE"
			missing="1"
		fi
	fi

	if devvm_command_exists shellcheck; then
		devvm_log "ok: shellcheck"
	else
		devvm_warn "missing optional: shellcheck"
	fi
	if devvm_command_exists gpg; then
		devvm_log "ok: gpg"
	else
		devvm_warn "missing optional: gpg (needed for devvm gpg commands)"
	fi

	if [ "$system" != "Darwin" ]; then
		devvm_warn "DevVM is designed primarily for macOS"
	fi
	if [ "$machine" != "arm64" ] && [ "$machine" != "aarch64" ]; then
		devvm_warn "default config targets Apple Silicon/aarch64"
	fi

	devvm_log "config: $DEVVM_CONFIG"
	devvm_log "state: $DEVVM_STATE"
	devvm_log "VM configs: $DEVVM_CONFIG/vms"

	[ "$missing" = "0" ] || return 1
}

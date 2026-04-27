#!/usr/bin/env bash
# shellcheck shell=bash

devvm_completion_help() {
	cat <<'HELP'
Usage:
  devvm completion bash
  devvm completion zsh

Examples:
  source <(devvm completion bash)
  source <(devvm completion zsh)
HELP
}

devvm_completion_bash() {
	cat <<'BASH'
# bash completion for devvm

_devvm_completion_vm_names_raw() {
	local config_dir file base
	config_dir="${DEVVM_CONFIG:-$HOME/.config/devvm}"

	[ -d "$config_dir/vms" ] || return 0
	for file in "$config_dir"/vms/*.env; do
		[ -e "$file" ] || continue
		base="${file##*/}"
		printf '%s\n' "${base%.env}"
	done
}

_devvm_completion_reply_words() {
	local current words
	current="$1"
	shift
	words="$*"
	COMPREPLY=($(compgen -W "$words" -- "$current"))
}

_devvm_completion_reply_vms() {
	local current include_all words
	current="$1"
	include_all="${2:-0}"
	words="$(_devvm_completion_vm_names_raw)"
	if [ "$include_all" = "1" ]; then
		words="all $words"
	fi
	COMPREPLY=($(compgen -W "$words" -- "$current"))
}

_devvm_completion() {
	local cur prev cmd commands new_options yes_options delete_options rebuild_options backup_options restore_options completion_shells
	local ai_commands ai_logs_options
	local gpg_commands gpg_create_options gpg_install_options gpg_export_public_options
	COMPREPLY=()

	cur="${COMP_WORDS[$COMP_CWORD]}"
	prev="${COMP_WORDS[$((COMP_CWORD - 1))]}"
	cmd="${COMP_WORDS[1]:-}"

	commands="help init new create enter ssh start stop delete rm update update-all rebuild rebuild-all backup backups restore key status list doctor ai gpg completion self-update"
	new_options="--ports --cpus --memory --disk --packages --setup --mount --share"
	yes_options="--yes -y"
	delete_options="$yes_options --backup --no-backup --include-secrets --no-secrets --encrypt --no-encrypt"
	rebuild_options="$delete_options --restore --no-restore"
	backup_options="--include-secrets --no-secrets --encrypt --no-encrypt --output"
	restore_options="--include-secrets --no-secrets"
	ai_commands="create update enter key endpoint status logs help -h --help"
	ai_logs_options="--lines --follow -f"
	gpg_commands="create-subkey install list export-public help -h --help"
	gpg_create_options="--label --expire --algo --output --force"
	gpg_install_options="--public --signing-key"
	gpg_export_public_options="--output"
	completion_shells="bash zsh"

	if [ "$COMP_CWORD" -eq 1 ]; then
		_devvm_completion_reply_words "$cur" "$commands $(_devvm_completion_vm_names_raw)"
		return 0
	fi

	case "$cmd" in
	new)
		case "$prev" in
		--ports | --cpus | --memory | --disk | --packages | --setup | --mount | --share)
			return 0
			;;
		esac
		if [[ "$cur" == -* ]] || [ "$COMP_CWORD" -gt 2 ]; then
			_devvm_completion_reply_words "$cur" "$new_options"
		fi
		;;
	create | enter | start | update | key)
		if [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_vms "$cur"
		fi
		;;
	ssh)
		if [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_vms "$cur"
		fi
		;;
	stop)
		if [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_vms "$cur" "1"
		fi
		;;
	delete | rm)
		if [[ "$cur" == -* ]] || [ "$COMP_CWORD" -gt 2 ]; then
			_devvm_completion_reply_words "$cur" "$delete_options"
		elif [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_vms "$cur"
		fi
		;;
	rebuild)
		if [[ "$cur" == -* ]] || [ "$COMP_CWORD" -gt 2 ]; then
			_devvm_completion_reply_words "$cur" "$rebuild_options"
		elif [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_vms "$cur"
		fi
		;;
	rebuild-all)
		if [[ "$cur" == -* ]] || [ "$COMP_CWORD" -gt 1 ]; then
			_devvm_completion_reply_words "$cur" "$rebuild_options"
		fi
		;;
	backup)
		case "$prev" in
		--output)
			return 0
			;;
		esac
		if [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_vms "$cur"
		elif [[ "$cur" == -* ]] || [ "$COMP_CWORD" -gt 2 ]; then
			_devvm_completion_reply_words "$cur" "$backup_options"
		fi
		;;
	backups)
		if [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_vms "$cur"
		fi
		;;
	restore)
		if [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_vms "$cur"
		elif [[ "$cur" == -* ]] || [ "$COMP_CWORD" -gt 3 ]; then
			_devvm_completion_reply_words "$cur" "$restore_options"
		fi
		;;
	ai)
		if [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_words "$cur" "$ai_commands"
			return 0
		fi
		case "${COMP_WORDS[2]:-}" in
		logs)
			case "$prev" in
			--lines)
				return 0
				;;
			esac
			if [[ "$cur" == -* ]] || [ "$COMP_CWORD" -gt 3 ]; then
				_devvm_completion_reply_words "$cur" "$ai_logs_options"
			fi
			;;
		esac
		;;
	gpg)
		if [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_words "$cur" "$gpg_commands"
			return 0
		fi
		case "${COMP_WORDS[2]:-}" in
		create-subkey)
			case "$prev" in
			--label | --expire | --algo | --output)
				return 0
				;;
			esac
			if [[ "$cur" == -* ]] || [ "$COMP_CWORD" -gt 3 ]; then
				_devvm_completion_reply_words "$cur" "$gpg_create_options"
			fi
			;;
		install)
			case "$prev" in
			--public | --signing-key)
				return 0
				;;
			esac
			if [ "$COMP_CWORD" -eq 3 ]; then
				_devvm_completion_reply_vms "$cur"
			elif [[ "$cur" == -* ]] || [ "$COMP_CWORD" -gt 4 ]; then
				_devvm_completion_reply_words "$cur" "$gpg_install_options"
			fi
			;;
		export-public)
			case "$prev" in
			--output)
				return 0
				;;
			esac
			if [[ "$cur" == -* ]] || [ "$COMP_CWORD" -gt 3 ]; then
				_devvm_completion_reply_words "$cur" "$gpg_export_public_options"
			fi
			;;
		esac
		;;
	completion)
		if [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_words "$cur" "$completion_shells"
		fi
		;;
	esac
}

complete -o default -F _devvm_completion devvm
BASH
}

devvm_completion_zsh() {
	cat <<'ZSH'
#compdef devvm
# zsh completion for devvm

_devvm_vm_names() {
	local config_dir file
	local -a names
	config_dir="${DEVVM_CONFIG:-$HOME/.config/devvm}"

	for file in "$config_dir"/vms/*.env(N); do
		names+=("${file:t:r}:DevVM VM")
	done

	_describe -t devvm-vms "DevVM VM" names
}

_devvm_vm_names_or_all() {
	local -a special
	special=("all:all configured VMs")
	_describe -t devvm-targets "target" special
	_devvm_vm_names
}

_devvm_top_level() {
	local config_dir file
	local -a commands
	commands=(
		"help:show help"
		"init:initialize config"
		"new:create a VM config"
		"create:create and provision a VM"
		"enter:enter a VM shell"
		"ssh:run a command in a VM"
		"start:start a VM"
		"stop:stop a VM"
		"delete:delete a VM"
		"rm:delete a VM"
		"update:run provisioning on a VM"
		"update-all:run provisioning on all VMs"
		"rebuild:delete and recreate a VM"
		"rebuild-all:delete and recreate all VMs"
		"backup:create a VM backup archive"
		"backups:list VM backup archives"
		"restore:restore a VM backup archive"
		"key:print a VM public SSH key"
		"status:show Lima VM status"
		"list:show Lima VM status"
		"doctor:check host setup"
		"ai:manage the llama.cpp service VM"
		"gpg:manage GPG signing subkeys"
		"completion:print shell completion"
		"self-update:update the DevVM checkout"
	)

	_describe -t devvm-commands "command" commands
	_devvm_vm_names
}

_devvm() {
	local cmd
	cmd="${words[2]:-}"

	if ((CURRENT == 2)); then
		_devvm_top_level
		return
	fi

	case "$cmd" in
	new)
		_arguments \
			"--ports[set guest or guest:host port forwards]:ports:" \
			"--cpus[set VM CPU count]:cpus:" \
			"--memory[set VM memory, e.g. 8GiB]:memory:" \
			"--disk[set VM disk size, e.g. 80GiB]:disk:" \
			"--packages[set per-VM DNF package list]:packages:" \
			"--setup[add a per-VM setup script path]:script:_files" \
			"--mount[add a host:guest[:ro|rw] mount]:mount:" \
			"--share[alias for --mount]:mount:"
		;;
	create | enter | start | update | key)
		_arguments "2:VM name:_devvm_vm_names"
		;;
	ssh)
		_arguments "2:VM name:_devvm_vm_names" "*::command:_normal"
		;;
	stop)
		_arguments "2:VM name:_devvm_vm_names_or_all"
		;;
	delete | rm)
		_arguments \
			"(-y --yes)"{-y,--yes}"[skip confirmation]" \
			"--backup[create a backup before deleting]" \
			"--no-backup[delete without creating a backup]" \
			"--include-secrets[include VM secrets in backup]" \
			"--no-secrets[exclude VM secrets from backup]" \
			"--encrypt[encrypt backup with GPG]" \
			"--no-encrypt[write plaintext backup]" \
			"2:VM name:_devvm_vm_names"
		;;
	rebuild)
		_arguments \
			"(-y --yes)"{-y,--yes}"[skip confirmation]" \
			"--backup[create a backup before deleting]" \
			"--no-backup[delete without creating a backup]" \
			"--include-secrets[include VM secrets in backup]" \
			"--no-secrets[exclude VM secrets from backup]" \
			"--encrypt[encrypt backup with GPG]" \
			"--no-encrypt[write plaintext backup]" \
			"--restore[restore backup after rebuild]" \
			"--no-restore[do not restore after rebuild]" \
			"2:VM name:_devvm_vm_names"
		;;
	rebuild-all)
		_arguments \
			"(-y --yes)"{-y,--yes}"[skip confirmation]" \
			"--backup[create backups before deleting]" \
			"--no-backup[rebuild without backups]" \
			"--include-secrets[include VM secrets in backups]" \
			"--no-secrets[exclude VM secrets from backups]" \
			"--encrypt[encrypt backups with GPG]" \
			"--no-encrypt[write plaintext backups]" \
			"--restore[restore backups after rebuild]" \
			"--no-restore[do not restore after rebuild]"
		;;
	backup)
		_arguments \
			"2:VM name:_devvm_vm_names" \
			"--include-secrets[include VM secrets]" \
			"--no-secrets[exclude VM secrets]" \
			"--encrypt[encrypt with GPG]" \
			"--no-encrypt[write plaintext archive]" \
			"--output[set output file or directory]:path:_files"
		;;
	backups)
		_arguments "2:VM name:_devvm_vm_names"
		;;
	restore)
		_arguments \
			"2:VM name:_devvm_vm_names" \
			"3:backup archive:_files" \
			"--include-secrets[restore VM secrets]" \
			"--no-secrets[restore only code]"
		;;
	ai)
		case "${words[3]:-}" in
		logs)
			_arguments \
				"--lines[set number of journal lines]:lines:" \
				"(-f --follow)"{-f,--follow}"[follow logs]"
			;;
		*)
			_arguments "2:AI command:((create\\:create-llama-vm update\\:update-llama-vm enter\\:enter-llama-vm key\\:print-ai-vm-key endpoint\\:print-api-endpoint status\\:show-service-status logs\\:show-service-logs help\\:help))"
			;;
		esac
		;;
	gpg)
		case "${words[3]:-}" in
		create-subkey)
			_arguments \
				"--label[set export file label]:label:" \
				"--expire[set subkey expiration, e.g. 1y]:expiration:" \
				"--algo[set GPG subkey algorithm]:algorithm:" \
				"--output[set export directory]:directory:_files -/" \
				"--force[overwrite existing export files]"
			;;
		install)
			_arguments \
				"3:VM name:_devvm_vm_names" \
				"4:secret subkey bundle:_files" \
				"--public[public key bundle to import first]:public key:_files" \
				"--signing-key[signing subkey fingerprint]:fingerprint:"
			;;
		export-public)
			_arguments "--output[set output file]:file:_files"
			;;
		*)
			_arguments "2:GPG command:((create-subkey\\:create-signing-subkey install\\:install-subkey list\\:list-subkeys export-public\\:export-public-key help\\:help))"
			;;
		esac
		;;
	completion)
		_arguments "2:shell:((bash\\:Bash zsh\\:Zsh))"
		;;
	esac
}

if ! whence -w compdef >/dev/null 2>&1; then
	autoload -Uz compinit
	compinit
fi
compdef _devvm devvm
ZSH
}

devvm_completion() {
	local shell
	shell="${1:-}"

	case "$shell" in
	bash)
		devvm_completion_bash
		;;
	zsh)
		devvm_completion_zsh
		;;
	'' | help | -h | --help)
		devvm_completion_help
		;;
	*)
		devvm_die "unknown completion shell: $shell"
		;;
	esac
}

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
	local cur prev cmd commands new_options yes_options ai_commands completion_shells
	COMPREPLY=()

	cur="${COMP_WORDS[$COMP_CWORD]}"
	prev="${COMP_WORDS[$((COMP_CWORD - 1))]}"
	cmd="${COMP_WORDS[1]:-}"

	commands="help init new create enter ssh start stop delete rm update update-all rebuild rebuild-all key status list doctor ai completion self-update"
	new_options="--ports --cpus --memory --disk --node-version --mount --share"
	yes_options="--yes -y"
	ai_commands="create update enter key help -h --help"
	completion_shells="bash zsh"

	if [ "$COMP_CWORD" -eq 1 ]; then
		_devvm_completion_reply_words "$cur" "$commands $(_devvm_completion_vm_names_raw)"
		return 0
	fi

	case "$cmd" in
	new)
		case "$prev" in
		--ports | --cpus | --memory | --disk | --node-version | --mount | --share)
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
	delete | rm | rebuild)
		if [[ "$cur" == -* ]] || [ "$COMP_CWORD" -gt 2 ]; then
			_devvm_completion_reply_words "$cur" "$yes_options"
		elif [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_vms "$cur"
		fi
		;;
	rebuild-all)
		if [[ "$cur" == -* ]] || [ "$COMP_CWORD" -gt 1 ]; then
			_devvm_completion_reply_words "$cur" "$yes_options"
		fi
		;;
	ai)
		if [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_words "$cur" "$ai_commands"
		fi
		;;
	completion)
		if [ "$COMP_CWORD" -eq 2 ]; then
			_devvm_completion_reply_words "$cur" "$completion_shells"
		fi
		;;
	esac
}

complete -F _devvm_completion devvm
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
		"key:print a VM public SSH key"
		"status:show Lima VM status"
		"list:show Lima VM status"
		"doctor:check host setup"
		"ai:manage the AI VM"
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
			"--node-version[install a Node version in the VM]:version:" \
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
	delete | rm | rebuild)
		_arguments \
			"(-y --yes)"{-y,--yes}"[skip confirmation]" \
			"2:VM name:_devvm_vm_names"
		;;
	rebuild-all)
		_arguments "(-y --yes)"{-y,--yes}"[skip confirmation]"
		;;
	ai)
		_arguments "2:AI command:((create\\:create update\\:update enter\\:enter key\\:key help\\:help))"
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

#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154

devvm_backup_help() {
	cat <<'HELP'
Usage:
  devvm backup <name> [--include-secrets|--no-secrets] [--encrypt|--no-encrypt] [--output <file-or-dir>]
  devvm backups [name]
  devvm restore <name> [backup-file] [--include-secrets|--no-secrets]

Examples:
  devvm backup myapp
  devvm restore myapp
  devvm restore myapp ~/.local/share/devvm-state/backups/myapp/myapp-20260101T120000Z.tar.gz.gpg
HELP
}

devvm_backup_bool() {
	local value name
	value="$1"
	name="$2"
	case "$value" in
	1 | true | yes | on) printf '1\n' ;;
	0 | false | no | off) printf '0\n' ;;
	*) devvm_die "$name must be 1 or 0" ;;
	esac
}

devvm_backup_resolve_encrypt() {
	local mode include_secrets
	mode="$1"
	include_secrets="$2"

	case "$mode" in
	auto)
		if devvm_command_exists gpg; then
			printf '1\n'
		else
			if [ "$include_secrets" = "1" ]; then
				devvm_warn "gpg not found; creating an unencrypted backup that includes secrets"
			fi
			printf '0\n'
		fi
		;;
	1 | true | yes | on)
		devvm_require_command gpg
		printf '1\n'
		;;
	0 | false | no | off)
		printf '0\n'
		;;
	*) devvm_die "DEVVM_BACKUP_ENCRYPT must be auto, 1, or 0" ;;
	esac
}

devvm_backup_default_file() {
	local name encrypted timestamp suffix
	name="$1"
	encrypted="$2"
	timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
	suffix=".tar.gz"
	[ "$encrypted" = "0" ] || suffix="$suffix.gpg"
	printf '%s/%s/%s-%s-%s%s\n' "$DEVVM_BACKUP_DIR" "$name" "$name" "$timestamp" "$$" "$suffix"
}

devvm_backup_output_file() {
	local name encrypted output filename
	name="$1"
	encrypted="$2"
	output="$3"

	if [ -z "$output" ]; then
		devvm_backup_default_file "$name" "$encrypted"
		return 0
	fi

	if [ -d "$output" ] || [ "${output%/}" != "$output" ]; then
		filename="$(basename "$(devvm_backup_default_file "$name" "$encrypted")")"
		output="${output%/}/$filename"
	fi

	if [ "$encrypted" = "1" ]; then
		case "$output" in
		*.gpg) ;;
		*) output="$output.gpg" ;;
		esac
	fi

	printf '%s\n' "$output"
}

devvm_backup_prepare_ssh() {
	devvm_lima_require_instance "$VM_NAME"
	limactl start "$VM_NAME"
	DEVVM_BACKUP_SSH_CONFIG="$HOME/.lima/$VM_NAME/ssh.config"
	[ -f "$DEVVM_BACKUP_SSH_CONFIG" ] || devvm_die "missing Lima SSH config: $DEVVM_BACKUP_SSH_CONFIG"
}

devvm_backup_remote_command() {
	cat <<'REMOTE'
set -euo pipefail
code_dir="$1"
include_secrets="$2"
exclude_words="$3"
declare -a paths exclude_args

if [ -e "$code_dir" ]; then
	paths+=("${code_dir#/}")
fi

if [ "$include_secrets" = "1" ]; then
	for path in \
		"$HOME/.ssh" \
		"$HOME/.gnupg" \
		"$HOME/.gitconfig" \
		"$HOME/.config/git" \
		"$HOME/.config/gh" \
		"$HOME/.config/claude" \
		"$HOME/.codex" \
		"$HOME/.claude" \
		"$HOME/.bash_history" \
		"$HOME/.zsh_history" \
		"$HOME/.profile" \
		"$HOME/.bashrc"; do
		if [ -e "$path" ]; then
			paths+=("${path#/}")
		fi
	done
fi

if [ "${#paths[@]}" -eq 0 ]; then
	echo "nothing to back up" >&2
	exit 1
fi

for pattern in $exclude_words; do
	exclude_args+=("--exclude=$pattern")
done

tar -C / --ignore-failed-read --warning=no-file-changed "${exclude_args[@]}" -czf - "${paths[@]}"
REMOTE
}

devvm_restore_remote_command() {
	cat <<'REMOTE'
set -euo pipefail
include_secrets="$1"
code_dir="$2"
code_rel="${code_dir#/}"

if [ "$include_secrets" = "1" ]; then
	tar -C / -xzf -
else
	tar -C / -xzf - "$code_rel"
fi
REMOTE
}

devvm_backup_create() {
	local name include_secrets encrypt_mode encrypted output output_file output_dir tmp_output
	local remote ssh_command status
	name="$1"
	include_secrets="${2:-}"
	encrypt_mode="${3:-}"
	output="${4:-}"

	devvm_require_command limactl
	devvm_require_command ssh
	devvm_load_vm "$name"

	include_secrets="$(devvm_backup_bool "${include_secrets:-$DEVVM_BACKUP_INCLUDE_SECRETS}" "DEVVM_BACKUP_INCLUDE_SECRETS")"
	encrypt_mode="${encrypt_mode:-$DEVVM_BACKUP_ENCRYPT}"
	encrypted="$(devvm_backup_resolve_encrypt "$encrypt_mode" "$include_secrets")"
	output_file="$(devvm_backup_output_file "$name" "$encrypted" "$output")"
	output_dir="$(dirname "$output_file")"

	[ ! -e "$output_file" ] || devvm_die "backup already exists: $output_file"
	devvm_ensure_dir "$DEVVM_BACKUP_DIR"
	chmod 0700 "$DEVVM_BACKUP_DIR"
	if [ "$output_dir" != "." ]; then
		devvm_ensure_dir "$output_dir"
		chmod 0700 "$output_dir"
	fi
	devvm_backup_prepare_ssh

	remote="$(devvm_backup_remote_command)"
	ssh_command="bash -c $(devvm_shell_quote "$remote") devvm-backup $(devvm_shell_quote "$CODE_DIR") $(devvm_shell_quote "$include_secrets") $(devvm_shell_quote "$DEVVM_BACKUP_EXCLUDES")"
	tmp_output="$output_file.tmp.$$"
	rm -f "$tmp_output"

	devvm_log "creating backup: $output_file"
	if [ "$include_secrets" = "1" ]; then
		devvm_log "backup includes VM secrets"
	fi
	if [ "$encrypted" = "1" ]; then
		devvm_log "encrypting backup with GPG symmetric encryption"
		status="0"
		ssh -F "$DEVVM_BACKUP_SSH_CONFIG" "lima-$VM_NAME" "$ssh_command" |
			gpg --symmetric --cipher-algo AES256 --output "$tmp_output" || status="$?"
	else
		if [ "$include_secrets" = "1" ]; then
			devvm_warn "backup includes secrets and is not encrypted"
		fi
		status="0"
		ssh -F "$DEVVM_BACKUP_SSH_CONFIG" "lima-$VM_NAME" "$ssh_command" >"$tmp_output" || status="$?"
	fi

	if [ "$status" -ne 0 ]; then
		rm -f "$tmp_output"
		return "$status"
	fi

	[ -s "$tmp_output" ] || {
		rm -f "$tmp_output"
		devvm_die "backup command produced an empty archive"
	}
	chmod 0600 "$tmp_output"
	mv "$tmp_output" "$output_file"
	# Used by devvm_rebuild to restore the exact archive it just created.
	# shellcheck disable=SC2034
	DEVVM_LAST_BACKUP_FILE="$output_file"
	devvm_log "backup ready: $output_file"
}

devvm_backup_latest() {
	local name dir latest
	name="$1"
	dir="$DEVVM_BACKUP_DIR/$name"
	[ -d "$dir" ] || devvm_die "no backups found for $name"
	latest="$(
		find "$dir" -type f \( -name '*.tar.gz' -o -name '*.tar.gz.gpg' \) -print |
			sort |
			tail -n 1
	)"
	[ -n "$latest" ] || devvm_die "no backups found for $name"
	printf '%s\n' "$latest"
}

devvm_backup() {
	local name include_secrets encrypt_mode output
	case "${1:-}" in
	help | -h | --help)
		devvm_backup_help
		return 0
		;;
	esac
	[ "$#" -ge 1 ] || devvm_die "usage: devvm backup <name> [--include-secrets|--no-secrets] [--encrypt|--no-encrypt] [--output <file-or-dir>]"
	name="$1"
	shift
	include_secrets=""
	encrypt_mode=""
	output=""

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--include-secrets)
			include_secrets="1"
			shift
			;;
		--no-secrets)
			include_secrets="0"
			shift
			;;
		--encrypt)
			encrypt_mode="1"
			shift
			;;
		--no-encrypt)
			encrypt_mode="0"
			shift
			;;
		--output)
			[ "$#" -gt 1 ] || devvm_die "--output requires a value"
			output="$2"
			shift 2
			;;
		*) devvm_die "unknown option: $1" ;;
		esac
	done

	devvm_backup_create "$name" "$include_secrets" "$encrypt_mode" "$output"
}

devvm_backups() {
	local name dir
	case "${1:-}" in
	help | -h | --help)
		devvm_backup_help
		return 0
		;;
	esac
	devvm_load_config
	name="${1:-}"
	[ "$#" -le 1 ] || devvm_die "usage: devvm backups [name]"

	if [ -n "$name" ]; then
		devvm_validate_name "$name"
		dir="$DEVVM_BACKUP_DIR/$name"
	else
		dir="$DEVVM_BACKUP_DIR"
	fi

	if [ ! -d "$dir" ]; then
		devvm_log "no backups found"
		return 0
	fi

	find "$dir" -type f \( -name '*.tar.gz' -o -name '*.tar.gz.gpg' \) -print | sort
}

devvm_restore_file() {
	local name backup_file include_secrets encrypted remote ssh_command status
	name="$1"
	backup_file="$2"
	include_secrets="${3:-}"

	devvm_require_command limactl
	devvm_require_command ssh
	[ -f "$backup_file" ] || devvm_die "backup file not found: $backup_file"
	devvm_load_vm "$name"
	include_secrets="$(devvm_backup_bool "${include_secrets:-$DEVVM_RESTORE_INCLUDE_SECRETS}" "DEVVM_RESTORE_INCLUDE_SECRETS")"

	if ! devvm_lima_instance_exists "$VM_NAME"; then
		devvm_log "Lima instance missing; creating $VM_NAME before restore"
		devvm_create "$name"
	else
		limactl start "$VM_NAME"
	fi
	devvm_backup_prepare_ssh

	case "$backup_file" in
	*.gpg)
		encrypted="1"
		devvm_require_command gpg
		;;
	*)
		encrypted="0"
		;;
	esac

	remote="$(devvm_restore_remote_command)"
	ssh_command="bash -c $(devvm_shell_quote "$remote") devvm-restore $(devvm_shell_quote "$include_secrets") $(devvm_shell_quote "$CODE_DIR")"
	devvm_log "restoring backup: $backup_file"
	if [ "$include_secrets" = "1" ]; then
		devvm_log "restore includes VM secrets"
	fi

	status="0"
	if [ "$encrypted" = "1" ]; then
		gpg --decrypt "$backup_file" |
			ssh -F "$DEVVM_BACKUP_SSH_CONFIG" "lima-$VM_NAME" "$ssh_command" || status="$?"
	else
		ssh -F "$DEVVM_BACKUP_SSH_CONFIG" "lima-$VM_NAME" "$ssh_command" <"$backup_file" || status="$?"
	fi

	[ "$status" -eq 0 ] || return "$status"
	devvm_log "restore complete: $VM_NAME"
}

devvm_restore() {
	local name backup_file include_secrets
	case "${1:-}" in
	help | -h | --help)
		devvm_backup_help
		return 0
		;;
	esac
	[ "$#" -ge 1 ] || devvm_die "usage: devvm restore <name> [backup-file] [--include-secrets|--no-secrets]"
	name="$1"
	shift
	backup_file=""
	include_secrets=""

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--include-secrets)
			include_secrets="1"
			shift
			;;
		--no-secrets)
			include_secrets="0"
			shift
			;;
		--*)
			devvm_die "unknown option: $1"
			;;
		*)
			[ -z "$backup_file" ] || devvm_die "unexpected argument: $1"
			backup_file="$1"
			shift
			;;
		esac
	done

	devvm_load_config
	backup_file="${backup_file:-$(devvm_backup_latest "$name")}"
	devvm_restore_file "$name" "$backup_file" "$include_secrets"
}

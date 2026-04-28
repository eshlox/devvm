#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154

devvm_gpg_help() {
	cat <<'HELP'
Usage:
  devvm gpg create-subkey <primary-key> [--label <name>] [--expire <time>] [--algo <algo>] [--output <dir>] [--force]
  devvm gpg install <vm> <secret-subkey.asc> [--public <public-key.asc>] [--signing-key <fingerprint>]
  devvm gpg list <primary-key>
  devvm gpg export-public <primary-key> [--output <file>]

Examples:
  devvm gpg create-subkey ABCDEF1234567890 --label eshlox-net --expire 1y
  devvm gpg install eshlox-net ~/.local/share/devvm-state/gpg/eshlox-net-secret-subkey.asc
HELP
}

devvm_gpg_safe_label() {
	local label
	label="$1"
	case "$label" in
	'' | *[!A-Za-z0-9._-]*)
		devvm_die "invalid GPG label '$label'; use letters, numbers, dots, underscores, and hyphens"
		;;
	esac
}

devvm_gpg_primary_fingerprint() {
	local key output fpr
	key="$1"
	output="$(gpg --with-colons --fingerprint --list-secret-keys "$key" 2>&1)" ||
		devvm_die "failed to inspect GPG secret key '$key': $output"
	fpr="$(printf '%s\n' "$output" | awk -F: '$1 == "fpr" { print $10; exit }')"
	[ -n "$fpr" ] || devvm_die "secret primary key not found on host: $key"
	printf '%s\n' "$fpr"
}

devvm_gpg_secret_subkey_fingerprints() {
	local key
	key="${1:-}"
	gpg --with-colons --with-subkey-fingerprint --list-secret-keys ${key:+"$key"} |
		awk -F: '
			$1 == "ssb" {
				want = 1
				next
			}
			$1 == "fpr" && want {
				print $10
				want = 0
				next
			}
			$1 != "fpr" {
				want = 0
			}
		'
}

devvm_gpg_export_public() {
	local key output primary_fpr
	[ "$#" -ge 1 ] || devvm_die "usage: devvm gpg export-public <primary-key> [--output <file>]"
	key="$1"
	shift
	output=""

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--output)
			[ "$#" -gt 1 ] || devvm_die "--output requires a value"
			output="$2"
			shift 2
			;;
		*) devvm_die "unknown option: $1" ;;
		esac
	done

	devvm_require_command gpg
	primary_fpr="$(devvm_gpg_primary_fingerprint "$key")"
	if [ -z "$output" ]; then
		devvm_load_config
		output="$DEVVM_STATE/gpg/$primary_fpr-public.asc"
	fi

	devvm_ensure_dir "$(dirname "$output")"
	gpg --armor --export "$primary_fpr" >"$output"
	chmod 0644 "$output"
	devvm_log "exported public key: $output"
}

devvm_gpg_create_subkey() {
	local primary expire algo output_dir label force before after primary_fpr subkey_fpr
	local public_file secret_file
	[ "$#" -ge 1 ] || devvm_die "usage: devvm gpg create-subkey <primary-key> [--label <name>] [--expire <time>] [--algo <algo>] [--output <dir>] [--force]"

	primary="$1"
	shift
	expire="1y"
	algo="default"
	output_dir=""
	label=""
	force="0"

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--label)
			[ "$#" -gt 1 ] || devvm_die "--label requires a value"
			label="$2"
			devvm_gpg_safe_label "$label"
			shift 2
			;;
		--expire)
			[ "$#" -gt 1 ] || devvm_die "--expire requires a value"
			expire="$2"
			shift 2
			;;
		--algo)
			[ "$#" -gt 1 ] || devvm_die "--algo requires a value"
			algo="$2"
			shift 2
			;;
		--output)
			[ "$#" -gt 1 ] || devvm_die "--output requires a value"
			output_dir="$2"
			shift 2
			;;
		--force)
			force="1"
			shift
			;;
		*) devvm_die "unknown option: $1" ;;
		esac
	done

	devvm_require_command gpg
	devvm_load_config
	output_dir="${output_dir:-$DEVVM_STATE/gpg}"
	devvm_ensure_dir "$output_dir"
	chmod 0700 "$output_dir"

	primary_fpr="$(devvm_gpg_primary_fingerprint "$primary")"
	if [ -n "$label" ]; then
		public_file="$output_dir/$label-public.asc"
		secret_file="$output_dir/$label-secret-subkey.asc"
		if [ "$force" != "1" ]; then
			[ ! -e "$public_file" ] || devvm_die "output file exists: $public_file; use --force to overwrite"
			[ ! -e "$secret_file" ] || devvm_die "output file exists: $secret_file; use --force to overwrite"
		fi
	fi

	before="$(mktemp)"
	after="$(mktemp)"
	# shellcheck disable=SC2064 # Capture paths before RETURN unsets local variables.
	trap "rm -f $(devvm_shell_quote "$before") $(devvm_shell_quote "$after")" RETURN

	devvm_gpg_secret_subkey_fingerprints "$primary_fpr" | sort >"$before"
	gpg --quick-add-key "$primary_fpr" "$algo" sign "$expire"
	devvm_gpg_secret_subkey_fingerprints "$primary_fpr" | sort >"$after"

	subkey_fpr="$(comm -13 "$before" "$after" | tail -n 1)"
	[ -n "$subkey_fpr" ] || devvm_die "could not detect the newly created signing subkey"

	label="${label:-devvm-$subkey_fpr}"
	devvm_gpg_safe_label "$label"
	public_file="${public_file:-$output_dir/$label-public.asc}"
	secret_file="${secret_file:-$output_dir/$label-secret-subkey.asc}"

	if [ "$force" != "1" ]; then
		[ ! -e "$public_file" ] || devvm_die "output file exists: $public_file; use --force to overwrite"
		[ ! -e "$secret_file" ] || devvm_die "output file exists: $secret_file; use --force to overwrite"
	fi

	gpg --armor --export "$primary_fpr" >"$public_file"
	gpg --armor --export-secret-subkeys "${subkey_fpr}!" >"$secret_file"
	chmod 0644 "$public_file"
	chmod 0600 "$secret_file"

	devvm_log "created signing subkey: $subkey_fpr"
	devvm_log "public key for GitHub update: $public_file"
	devvm_log "secret subkey bundle for VM import: $secret_file"
	devvm_log "install into a VM with: devvm gpg install <vm> $(devvm_shell_quote "$secret_file") --signing-key $subkey_fpr"
}

devvm_gpg_bundle_subkey_fingerprint() (
	local bundle tmp import_output fprs count
	bundle="$1"
	tmp="$(mktemp -d)"
	chmod 0700 "$tmp"
	# shellcheck disable=SC2064 # Capture path before EXIT cleanup.
	trap "rm -rf $(devvm_shell_quote "$tmp")" EXIT

	import_output="$(GNUPGHOME="$tmp" gpg --batch --quiet --import "$bundle" 2>&1)" ||
		devvm_die "could not inspect GPG subkey bundle: $bundle: $import_output"

	fprs="$(GNUPGHOME="$tmp" devvm_gpg_secret_subkey_fingerprints)"
	count="$(printf '%s\n' "$fprs" | sed '/^$/d' | wc -l | tr -d ' ')"
	case "$count" in
	1)
		printf '%s\n' "$fprs"
		;;
	0)
		devvm_die "no secret subkey found in bundle: $bundle"
		;;
	*)
		devvm_die "multiple secret subkeys found in bundle; rerun with --signing-key <fingerprint>"
		;;
	esac
)

devvm_gpg_install() {
	local name secret_file public_file signing_key bundle ssh_config remote ssh_command
	[ "$#" -ge 2 ] || devvm_die "usage: devvm gpg install <vm> <secret-subkey.asc> [--public <public-key.asc>] [--signing-key <fingerprint>]"

	name="$1"
	secret_file="$2"
	shift 2
	public_file=""
	signing_key=""

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--public)
			[ "$#" -gt 1 ] || devvm_die "--public requires a value"
			public_file="$2"
			shift 2
			;;
		--signing-key)
			[ "$#" -gt 1 ] || devvm_die "--signing-key requires a value"
			signing_key="${2%!}"
			shift 2
			;;
		*) devvm_die "unknown option: $1" ;;
		esac
	done

	devvm_require_command gpg
	devvm_require_command limactl
	devvm_require_command ssh
	[ -f "$secret_file" ] || devvm_die "secret subkey bundle not found: $secret_file"
	if [ -n "$public_file" ]; then
		[ -f "$public_file" ] || devvm_die "public key file not found: $public_file"
	fi

	bundle="$(mktemp)"
	# shellcheck disable=SC2064 # Capture path before RETURN unsets local variables.
	trap "rm -f $(devvm_shell_quote "$bundle")" RETURN
	if [ -n "$public_file" ]; then
		cat "$public_file" "$secret_file" >"$bundle"
	else
		cat "$secret_file" >"$bundle"
	fi

	if [ -z "$signing_key" ]; then
		signing_key="$(devvm_gpg_bundle_subkey_fingerprint "$bundle")"
	fi

	devvm_load_vm "$name"
	devvm_lima_require_instance "$VM_NAME"
	limactl start "$VM_NAME"
	ssh_config="$HOME/.lima/$VM_NAME/ssh.config"
	[ -f "$ssh_config" ] || devvm_die "missing Lima SSH config: $ssh_config"

	# shellcheck disable=SC2016
	remote='
set -euo pipefail
signing_key="${1%!}"
umask 077
mkdir -p "$HOME/.gnupg"
chmod 700 "$HOME/.gnupg"
tmp="$(mktemp)"
trap '\''rm -f "$tmp"'\'' EXIT
cat >"$tmp"
gpg --batch --import "$tmp"
git config --global gpg.program gpg
git config --global user.signingkey "${signing_key}!"
git config --global commit.gpgsign true
for profile in "$HOME/.profile" "$HOME/.bashrc"; do
	touch "$profile"
	if ! grep -Fq "# BEGIN DEVVM GPG" "$profile"; then
		cat >>"$profile" <<'\''PROFILE'\''
# BEGIN DEVVM GPG
if command -v tty >/dev/null 2>&1; then
	GPG_TTY="$(tty 2>/dev/null || true)"
	export GPG_TTY
fi
if command -v gpg-connect-agent >/dev/null 2>&1; then
	gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true
fi
# END DEVVM GPG
PROFILE
	fi
done
printf "configured git commit signing with GPG subkey %s\n" "$signing_key"
'

	ssh_command="bash -c $(devvm_shell_quote "$remote") devvm-gpg-install $(devvm_shell_quote "$signing_key")"
	ssh -F "$ssh_config" "lima-$VM_NAME" "$ssh_command" <"$bundle"
	devvm_log "GPG signing configured in $VM_NAME with subkey $signing_key"
}

devvm_gpg_list() {
	local primary
	[ "$#" -eq 1 ] || devvm_die "usage: devvm gpg list <primary-key>"
	primary="$1"
	devvm_require_command gpg
	gpg --list-secret-keys --with-subkey-fingerprint --keyid-format LONG "$primary"
}

devvm_gpg() {
	local subcmd
	subcmd="${1:-help}"
	if [ "$#" -gt 0 ]; then
		shift
	fi

	case "$subcmd" in
	create-subkey)
		devvm_gpg_create_subkey "$@"
		;;
	install)
		devvm_gpg_install "$@"
		;;
	list)
		devvm_gpg_list "$@"
		;;
	export-public)
		devvm_gpg_export_public "$@"
		;;
	help | -h | --help)
		devvm_gpg_help
		;;
	*)
		devvm_die "unknown gpg command: $subcmd"
		;;
	esac
}

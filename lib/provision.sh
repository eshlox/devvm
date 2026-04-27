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

devvm_provision_remote_command() {
	cat <<'REMOTE'
set -euo pipefail
name="$1"
code_dir="$2"
git_user_name="$3"
git_user_email="$4"
packages="$5"

mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.cache" "$HOME/.ssh" "$HOME/.gnupg" "$code_dir"
chmod 0700 "$HOME/.ssh" "$HOME/.gnupg"

if [ -n "$packages" ]; then
	for package in $packages; do
		case "$package" in
			-* | *[!A-Za-z0-9._+:@-]*)
				echo "invalid package token: $package" >&2
				exit 1
				;;
		esac
	done
	# shellcheck disable=SC2086 # Package words are intentionally supplied by config.
	sudo dnf5 install -y -- $packages
fi

if [ -n "$git_user_name" ] || [ -n "$git_user_email" ]; then
	git_config="$HOME/.gitconfig"
	tmp_git_config="$(mktemp)"
	touch "$git_config"
	awk '
		$0 == "# BEGIN DEVVM GIT" {
			skip = 1
			next
		}
		$0 == "# END DEVVM GIT" {
			skip = 0
			next
		}
		!skip {
			print
		}
	' "$git_config" >"$tmp_git_config"
	cat >>"$tmp_git_config" <<CONFIG
# BEGIN DEVVM GIT
[user]
	name = $git_user_name
	email = $git_user_email
# END DEVVM GIT
CONFIG
	mv "$tmp_git_config" "$git_config"
	chmod 0644 "$git_config"
fi

key="$HOME/.ssh/id_ed25519_$name"
if [ ! -f "$key" ]; then
	if ! command -v ssh-keygen >/dev/null 2>&1; then
		echo "ssh-keygen is not installed; add openssh-clients to PACKAGES or GLOBAL_PACKAGES" >&2
		exit 1
	fi
	ssh-keygen -t ed25519 -C "$name-devvm" -f "$key" -N ''
fi

ssh_config="$HOME/.ssh/config"
touch "$ssh_config"
chmod 0600 "$ssh_config"
if ! grep -Fq "# BEGIN DEVVM $name GITHUB" "$ssh_config"; then
	cat >>"$ssh_config" <<CONFIG
# BEGIN DEVVM $name GITHUB
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_$name
  IdentitiesOnly yes
# END DEVVM $name GITHUB
CONFIG
fi
REMOTE
}

devvm_provision_script_command() {
	cat <<'REMOTE'
set -euo pipefail
script_name="$1"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat >"$tmp"
chmod 0700 "$tmp"
DEVVM_SETUP_SCRIPT="$script_name" "$tmp"
REMOTE
}

devvm_provision_run_script() {
	local script remote
	script="$1"
	[ -f "$script" ] || devvm_die "setup script not found: $script"
	remote="$(devvm_provision_script_command)"
	devvm_log "running setup script in $VM_NAME: $script"
	# shellcheck disable=SC2094 # The script is read on the host and written to a temp file in the VM.
	limactl shell "$VM_NAME" env \
		"DEVVM_NAME=$NAME" \
		"DEVVM_VM_NAME=$VM_NAME" \
		"DEVVM_ROLE=$DEVVM_ROLE" \
		"DEVVM_CODE_DIR=$CODE_DIR" \
		bash -c "$remote" devvm-setup "$script" <"$script"
}

devvm_provision() {
	local name remote script
	name="$1"
	devvm_load_vm "$name"

	remote="$(devvm_provision_remote_command)"
	devvm_log "provisioning $VM_NAME"
	limactl shell "$VM_NAME" bash -c "$remote" devvm-provision \
		"$NAME" \
		"$CODE_DIR" \
		"$GIT_USER_NAME" \
		"$GIT_USER_EMAIL" \
		"$EFFECTIVE_PACKAGES"

	for script in $EFFECTIVE_SETUP_SCRIPTS; do
		[ -n "$script" ] || continue
		devvm_provision_run_script "$script"
	done
}

devvm_provision_all() {
	local name
	[ "$#" -gt 0 ] || devvm_die "usage: devvm_provision_all <vm>..."
	for name in "$@"; do
		devvm_provision "$name"
	done
}

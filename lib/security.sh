#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154

devvm_security_check_file_permissions() {
	local path mode status
	status="0"
	path="$1"
	[ -e "$path" ] || return 0
	if mode="$(devvm_file_mode "$path")"; then
		if devvm_mode_has_group_or_world_write "$mode"; then
			devvm_warn "group/world writable file or directory: $path ($mode)"
			status="1"
		else
			devvm_log "ok: permissions $path ($mode)"
		fi
	else
		devvm_warn "could not inspect permissions: $path"
		status="1"
	fi
	return "$status"
}

devvm_security_doctor() {
	local status config_file vm_file
	status="0"

	devvm_load_config
	devvm_load_install_metadata

	devvm_log "security checks"
	devvm_log "install mode: $DEVVM_INSTALL_MODE"
	if [ "$DEVVM_INSTALL_MODE" = "homebrew" ]; then
		devvm_log "ok: Homebrew-managed install"
	elif [ "$DEVVM_INSTALL_MODE" = "copy" ]; then
		if devvm_verify_install >/dev/null; then
			devvm_log "ok: copied install manifest"
		else
			devvm_warn "copied install verification failed; run devvm verify-install"
			status="1"
		fi
	else
		devvm_warn "source install is mutable and trusts git pull"
	fi

	if [ "$DEVVM_INSTALL_MODE" = "homebrew" ]; then
		devvm_log "ok: release updates managed by Homebrew"
	elif [ -z "$DEVVM_RELEASE_SIGNER_FINGERPRINTS" ]; then
		devvm_warn "DEVVM_RELEASE_SIGNER_FINGERPRINTS is not configured"
		status="1"
	else
		devvm_log "ok: trusted release signer configured"
	fi
	if [ "$DEVVM_INSTALL_MODE" = "homebrew" ]; then
		devvm_log "ok: use brew outdated devvm or brew upgrade devvm for updates"
	elif [ "$DEVVM_UPDATE_CHECK_ENABLED" = "1" ]; then
		devvm_log "ok: periodic update checks enabled (${DEVVM_UPDATE_CHECK_INTERVAL_SECONDS}s)"
	else
		devvm_warn "periodic update checks disabled; check releases manually"
	fi

	case "$DEVVM_BACKUP_ENCRYPT" in
	1 | true | yes | on)
		devvm_log "ok: backups require encryption by default"
		;;
	auto)
		devvm_warn "DEVVM_BACKUP_ENCRYPT=auto depends on host gpg availability"
		status="1"
		;;
	0 | false | no | off)
		devvm_warn "DEVVM_BACKUP_ENCRYPT disables backup encryption"
		status="1"
		;;
	*)
		devvm_warn "invalid DEVVM_BACKUP_ENCRYPT: $DEVVM_BACKUP_ENCRYPT"
		status="1"
		;;
	esac
	if [ "$DEVVM_BACKUP_ALLOW_PLAINTEXT_SECRETS" = "1" ]; then
		devvm_warn "DEVVM_BACKUP_ALLOW_PLAINTEXT_SECRETS=1 allows plaintext secret backups"
		status="1"
	else
		devvm_log "ok: plaintext secret backups disabled"
	fi

	if [ "$DEVVM_ALLOW_SENSITIVE_MOUNTS" = "1" ]; then
		devvm_warn "DEVVM_ALLOW_SENSITIVE_MOUNTS=1 weakens host isolation"
		status="1"
	else
		devvm_log "ok: sensitive host mounts rejected by default"
	fi

	for config_file in "$DEVVM_CONFIG/config.env" "$DEVVM_CONFIG/local.env" "$DEVVM_STATE/install.env" "$(devvm_install_env_path)"; do
		[ -n "$config_file" ] || continue
		if ! devvm_security_check_file_permissions "$config_file"; then
			status="1"
		fi
	done

	if [ -d "$DEVVM_CONFIG/vms" ]; then
		for vm_file in "$DEVVM_CONFIG"/vms/*.env; do
			[ -e "$vm_file" ] || continue
			if ! devvm_security_check_file_permissions "$vm_file"; then
				status="1"
			fi
		done
	fi

	if [ -n "${GLOBAL_MOUNTS:-}" ]; then
		devvm_warn "GLOBAL_MOUNTS is set; review shared host paths"
	fi
	devvm_log "security docs: docs/security.md"
	return "$status"
}

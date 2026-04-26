#!/usr/bin/env bash
# shellcheck shell=bash

devvm_shell_files() {
	printf '%s\n' \
		install.sh \
		bin/devvm \
		lib/ai.sh \
		lib/ansible.sh \
		lib/config.sh \
		lib/lima.sh \
		lib/util.sh \
		lib/vm.sh \
		scripts/files.sh \
		scripts/format-check.sh \
		scripts/format.sh \
		scripts/install-ci-tools.sh \
		scripts/lint.sh \
		scripts/release-github.sh \
		scripts/test.sh \
		tests/shellcheck.sh \
		tests/smoke.sh
}

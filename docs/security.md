# Security Guide

DevVM's security goal is project isolation with a small, inspectable toolchain. It
reduces host and cross-project blast radius; it does not replace endpoint security.

## Install

Preferred stable install:

```bash
brew install eshlox/devvm/devvm
```

Homebrew installs from a formula with a pinned release archive SHA-256 and manages
updates with:

```bash
brew update
brew upgrade devvm
```

For development on DevVM itself, use a separate source symlink install:

```bash
./install.sh --symlink \
  --name devvm-dev \
  --config-dir "$HOME/.config/devvm-dev" \
  --state-dir "$HOME/.local/share/devvm-dev-state" \
  --vm-prefix devvm-dev
```

This keeps development VMs under `devvm-dev-*` instead of the production `devvm-*`
prefix.

Manual copied installs are a fallback/testing path:

```bash
git clone https://github.com/eshlox/devenv.git
cd devenv
git checkout v0.1.0
git verify-tag v0.1.0
./install.sh --version v0.1.0
```

Source symlink installs are mutable and update with `git pull --ff-only`. Use Homebrew
for normal use.

## Verify

Run:

```bash
devvm verify-install
devvm doctor --security
```

`verify-install` reports Homebrew-managed installs and checks install metadata,
copied-install manifests, and trusted release signer configuration where applicable.
`doctor --security` also checks backup posture, sensitive mount settings, and writable
config files.

## Update

Homebrew installs update through Homebrew:

```bash
brew update
brew upgrade devvm
```

`devvm self-update` is disabled for Homebrew installs.

Manual copied installs update by release tag:

```bash
devvm self-update --version v0.1.0
```

By default this requires:

- a valid signed Git tag
- a signing fingerprint listed in `DEVVM_RELEASE_SIGNER_FINGERPRINTS`
- a clean copied install manifest after extraction

Copied installs also check for newer stable release tags during interactive use. This
periodic check runs `git ls-remote` against the recorded release remote, caches the
result under DevVM state, and prints a notice only when a newer version exists. It does
not install anything.

Disable it or change the interval in seconds:

```bash
DEVVM_UPDATE_CHECK_ENABLED="0"
DEVVM_UPDATE_CHECK_INTERVAL_SECONDS="86400"
```

Rollback:

```bash
devvm self-update --rollback
```

Use `--no-verify-tag` or `--no-verify-signer` only for local testing.

## Configure

Config files are data, not shell scripts. DevVM accepts simple `KEY=value` files with
comments and quoted strings. It rejects command substitution and other shell syntax.

Use config for data:

```bash
GLOBAL_PACKAGES="helix ripgrep"
GLOBAL_SETUP_SCRIPTS="$HOME/.config/devvm/setup/common.sh"
```

Use setup scripts for executable logic:

```bash
SETUP_SCRIPTS="$HOME/.config/devvm/setup/project.sh"
```

Keep `local.env` out of any shared config repo.

## Use VMs

Default workflow:

- clone source code inside the VM under `~/code`
- avoid host project mounts
- use one VM per project
- use one VM-local SSH key per VM
- use one GPG signing subkey per VM/project when practical

Explicit shares should be narrow and temporary. DevVM rejects broad host paths and
sensitive host directories by default.

## Backups

Secret-inclusive backups require encryption by default:

```bash
DEVVM_BACKUP_ENCRYPT="1"
```

Plaintext backups are acceptable only for code-only archives:

```bash
devvm backup myapp --no-secrets --no-encrypt
```

DevVM refuses plaintext secret-inclusive backups unless this is explicitly set:

```bash
DEVVM_BACKUP_ALLOW_PLAINTEXT_SECRETS="1"
```

Keep backup archives out of project repos.

## AI VM

The optional llama.cpp VM is a local service VM. Model downloads must use HTTPS and
include SHA-256 checksums. The default endpoint is local through Lima host forwarding.
Do not expose it to a LAN unless you have added your own access controls.

## Routine Checks

Run periodically:

```bash
devvm doctor --security
devvm verify-install
devvm backups
```

Rotate or revoke VM GPG subkeys when a VM is deleted, a project is retired, or access
should end.

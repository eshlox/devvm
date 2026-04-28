# DevVM

Keep your friends close, your supply chain in a VM.

DevVM creates disposable Fedora development VMs on macOS using Lima and a thin shell
CLI. The opinionated workflow is:

```text
macOS: terminal + Lima + devvm CLI
VM: Fedora + optional user-selected packages/scripts + source code under ~/code
AI VM: optional Fedora VM running llama.cpp from DNF
```

Project source code is not stored on macOS by default. DevVM creates and configures a
VM, prepares `~/code`, configures a VM SSH key for Git, and then you clone repositories
manually from inside the VM.

The default guest is intentionally small. Editors, terminal tools, Git workflow
preferences, language runtimes, and other personal tools belong in your DevVM config or
setup scripts, not in the project defaults.

The optional AI VM is separate from development VMs. It installs Fedora's `llama-cpp`
package and exposes a local OpenAI-compatible endpoint for users who want local models
without installing llama.cpp on macOS.

## Design Intent

DevVM is intentionally small. Its job is to make isolated project VMs easy to create,
enter, update, back up, rebuild, and delete. It brings a simple config layout, VM-local
SSH keys, optional GPG signing subkeys, explicit shares, backups, and an optional local
llama.cpp service VM.

It is not a full development platform, package manager, dotfiles manager, container
workflow, IDE integration, or language runtime installer. Project tools such as
editors, shells, Node.js, Rust, Python, Claude, Codex, and dotfiles belong in user-owned
DNF package lists and setup scripts.

DevVM exists because the adjacent tools are broader than this project needs. Dev
Containers, DevPod, Codespaces, Coder, Gitpod, Nix, Devbox, Vagrant, Docker Desktop,
Colima, and OrbStack are useful, but they ask users to adopt larger workflows, learn
extra concepts, or expose more host/project state. DevVM keeps the contract narrower:
isolate each project from macOS and from other projects, then get out of the way.

## Requirements

- macOS on Apple Silicon
- Lima 2.x or newer
- OpenSSH client

Install with Homebrew; the formula depends on Lima:

```bash
brew install eshlox/devvm/devvm
```

`shellcheck` and `shfmt` are only needed for contributing to this repo, not for daily VM
usage.

## Install

Recommended stable install:

```bash
brew install eshlox/devvm/devvm
```

Homebrew's two-part name is the tap, not the formula. If you want a shorter install
command after tapping:

```bash
brew tap eshlox/devvm
brew install devvm
```

Updates are managed by Homebrew:

```bash
brew update
brew upgrade devvm
```

For development on DevVM itself, clone the repo and install a separate development
command. This keeps test VMs away from your real `devvm-*` VMs:

```bash
git clone https://github.com/eshlox/devenv.git
cd devenv
./install.sh --symlink \
  --name devvm-dev \
  --prefix "$HOME/.local/bin" \
  --install-dir "$HOME/.local/share/devvm-dev-install" \
  --config-dir "$HOME/.config/devvm-dev" \
  --state-dir "$HOME/.local/share/devvm-dev-state" \
  --vm-prefix devvm-dev
```

Then use `devvm-dev` for testing:

```bash
devvm-dev init
devvm-dev new scratch
```

Manual copied installs are kept for local testing and fallback use, but Homebrew is the
normal production install path. See [Homebrew Packaging](docs/homebrew.md).

## Workflow

Create a VM config:

```bash
devvm init
devvm new myapp --ports "3000 5173"
```

Create and configure the VM:

```bash
devvm create myapp
devvm key myapp
```

Add the printed SSH public key to GitHub, then enter the VM and clone code inside the
guest:

```bash
devvm enter myapp
git clone git@github.com:you/myapp.git ~/code/myapp
cd ~/code/myapp
```

## Commands

```text
devvm init
devvm new <name> [--ports "..."] [--packages "..."] [--setup script.sh]
  [--mount host:guest[:ro|rw]]
devvm create <name>
devvm enter <name>
devvm ssh <name> [command...]
devvm start <name>
devvm stop <name|all>
devvm delete <name> [--yes]
devvm update <name>
devvm update-all
devvm rebuild <name> [--yes]
devvm rebuild-all [--yes]
devvm backup <name>
devvm backups [name]
devvm restore <name> [backup-file]
devvm key <name>
devvm status
devvm doctor [--security]
devvm ai create|update|enter|key|endpoint|status|logs
devvm gpg create-subkey|install|list|export-public
devvm completion bash|zsh
devvm verify-install
devvm self-update [--version v0.1.0|--rollback]
```

`devvm <name>` is a shortcut for `devvm enter <name>`.

## Shell Completion

Completion includes commands, command options, GPG subcommands, and existing VM names
from `~/.config/devvm/vms`.

For Zsh:

```bash
source <(devvm completion zsh)
```

For Bash:

```bash
source <(devvm completion bash)
```

Add the matching line to your shell startup file to keep completion enabled.

## Configuration

Global config lives at:

```text
~/.config/devvm/config.env
~/.config/devvm/local.env
```

VM configs live at:

```text
~/.config/devvm/vms/<name>.env
```

This directory is intentionally suitable for a user-owned config repo. Put machine-local
secrets or temporary overrides in `local.env` and gitignore that file in your config
repo.

Config files are parsed as data, not sourced as shell. Use simple `KEY=value` lines,
comments, and quoted strings. Put executable setup logic in `GLOBAL_SETUP_SCRIPTS` or
`SETUP_SCRIPTS`, not in config files.

Set `GIT_USER_NAME` and `GIT_USER_EMAIL` there if you want DevVM to configure Git
identity.

Fedora image selection is delegated to Lima's current built-in template:

```bash
LIMA_TEMPLATE="template:fedora"
```

The default code directory is inside the guest user's home:

```bash
DEVVM_CODE_DIR="$DEVVM_GUEST_HOME/code"
```

Normal project VMs install no packages by default. Install Fedora packages globally for
every VM or per VM:

```bash
GLOBAL_PACKAGES="helix ripgrep"
devvm new myapp --packages "nodejs nodejs-npm pnpm"
```

Run setup scripts globally for every VM or per VM:

```bash
GLOBAL_SETUP_SCRIPTS="$HOME/.config/devvm/setup/common.sh"
devvm new myapp --setup "$HOME/.config/devvm/setup/myapp.sh"
```

Dotfiles are also just setup. Use a setup script for your preferred approach, whether
that is a bare Git repo, rsync, a dotfile manager, or something project-specific.

## Local LLaMA VM

`devvm ai create` creates a separate VM named `ai` by default and installs
`llama-cpp` from Fedora packages. It does not install Claude, Codex, Node.js, or AI
tooling into development VMs.

Configure a model in `~/.config/devvm/config.env`:

```bash
AI_LLAMA_MODELS="model.gguf|https://example.com/model.gguf|sha256:<64 hex chars>"
AI_LLAMA_MODEL="model.gguf"
```

Then create the service VM:

```bash
devvm ai create
devvm ai endpoint
```

The default endpoint for other DevVMs is:

```text
http://host.lima.internal:18080/v1
```

Model downloads must use HTTPS and include a SHA-256 checksum. You can also leave
`AI_LLAMA_MODELS` empty, place or mount a GGUF file under `AI_LLAMA_MODELS_DIR`, set
`AI_LLAMA_MODEL`, and run `devvm ai update`.

See [Local LLaMA](docs/ai.md) for configuration details.

## Explicit Shares

No host directories are mounted by default. If you need file exchange, use an explicit
narrow share:

```bash
devvm new myapp --mount "$HOME/devvm-share:/share:rw"
```

Global shares for every VM can be configured with:

```bash
GLOBAL_MOUNTS="$HOME/devvm-share:/share:rw"
```

Mounts use `host_path:guest_path[:ro|rw]`. DevVM refuses broad host mounts such as
`$HOME` and protected guest paths such as `~/code`.

See [Explicit Shares](docs/shares.md) and the [Threat Model](docs/threat-model.md) for
the host mount boundary and its limits.

Generated Lima YAML lives at:

```text
~/.local/share/devvm-state/generated/
```

## Backups

Project source still lives in the VM by default. To protect against accidental deletion,
DevVM can stream a targeted tar backup from the VM to macOS without mounting the project
directory:

```bash
devvm backup myapp
devvm backups myapp
devvm restore myapp
```

By default, backups include `~/code`, SSH keys, GPG data, Git config, selected tool
state, and shell history. Restores also include secrets by default. Use `--no-secrets`
on either command to limit the operation to code.

Secret-inclusive backups currently add `~/.ssh`, `~/.gnupg`, `~/.gitconfig`,
`~/.config/git`, `~/.config/gh`, `~/.config/claude`, `~/.codex`, `~/.claude`, shell
history, and shell profile files. See the [Threat Model](docs/threat-model.md) for
backup handling risks.

Backups are written under `~/.local/share/devvm-state/backups/<name>/`. With
`DEVVM_BACKUP_ENCRYPT="1"` DevVM requires host GPG symmetric encryption for backups.
Use `--no-secrets` when you intentionally want a plaintext code-only backup. Plaintext
secret-inclusive backups are refused unless you explicitly set
`DEVVM_BACKUP_ALLOW_PLAINTEXT_SECRETS="1"`.

`devvm delete` automatically creates a backup before deleting a VM. `devvm rebuild`
automatically backs up, recreates the VM, and restores that backup. Use `--no-backup` or
`--no-restore` only when you intentionally want disposable state.

## GPG Commit Signing

DevVM can automate signing subkeys without copying your primary GPG key into a VM. The
primary key stays on macOS; each VM receives only the exported signing subkey you choose.
Use one exported subkey bundle for many VMs if you want a shared signer, or create one
subkey per VM/project by changing `--label`.

Create a signing subkey on the host:

```bash
devvm gpg create-subkey <primary-key-id> --label myapp --expire 1y
```

The command writes a public key export and a `*-secret-subkey.asc` bundle under
`~/.local/share/devvm-state/gpg` by default and may open your normal GPG pinentry prompt.
Upload or replace the public key in GitHub, then install the secret subkey bundle into a
VM:

```bash
devvm gpg install myapp ~/.local/share/devvm-state/gpg/myapp-secret-subkey.asc
```

Inside the VM, DevVM imports the subkey and configures Git to sign commits with that
exact subkey. Secret subkey bundles are sensitive; do not commit them to your config
repo.

To revoke access for a VM, revoke or expire that subkey on the host, export the updated
public key with `devvm gpg export-public <primary-key-id>`, and update the GPG key in
GitHub.

## Updating DevVM

Homebrew installs update with Homebrew:

```bash
brew update
brew upgrade devvm
```

Source symlink installs are for development and update the checkout:

```bash
devvm-dev self-update
```

Manual copied installs are updated by installing a specific release tag:

```bash
devvm self-update --version v0.1.0
```

For copied installs, DevVM fetches the tag from the recorded Git remote, verifies it
with `git verify-tag`, checks the signer against `DEVVM_RELEASE_SIGNER_FINGERPRINTS`,
copies it into `~/.local/share/devvm/versions/<version>`, writes an install manifest,
and then switches the `current` symlink. Use signed release tags for normal releases.

Rollback switches back to the previously active copied version:

```bash
devvm self-update --rollback
```

If you intentionally need to test an unsigned local tag, pass `--no-verify-tag`.

During interactive use, copied installs check the release remote periodically and print
a notice when a newer stable `vX.Y.Z` tag exists. The check uses `git ls-remote` only;
it does not execute remote code or install anything. Configure it with:

```bash
DEVVM_UPDATE_CHECK_ENABLED="1"
DEVVM_UPDATE_CHECK_INTERVAL_SECONDS="86400"
```

Verify the active install:

```bash
devvm verify-install
devvm doctor --security
```

See [Security Guide](docs/security.md) and [Release Process](docs/release.md).

## Development

Install repo tooling:

```bash
brew install shellcheck shfmt
```

Run all local checks:

```bash
bash scripts/check.sh
```

The check suite is shell-native:

- `scripts/format-check.sh` verifies `shfmt` output and trailing whitespace.
- `scripts/lint.sh` runs ShellCheck.
- `scripts/test.sh` runs Bash syntax checks and the smoke test.

The smoke test uses mocked GPG commands. To exercise real GPG key and subkey parsing:

```bash
DEVVM_RUN_GPG_INTEGRATION=1 bash tests/gpg-integration.sh
```

Format shell files:

```bash
bash scripts/format.sh
```

Releases are tag-driven. Update `CHANGELOG.md`, commit the release notes, then push a
signed tag:

```bash
git add CHANGELOG.md
git commit -m "chore: release v0.1.0"
bash scripts/prepare-release.sh 0.1.0 --push
```

Pull requests run CI automatically. Pushing a `v*` tag runs the release workflow and
creates a GitHub release from the matching `CHANGELOG.md` section.

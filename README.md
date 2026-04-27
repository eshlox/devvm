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

## Requirements

- macOS on Apple Silicon
- Lima 2.x or newer
- OpenSSH client

Install common host dependencies with Homebrew:

```bash
brew install lima
```

`shellcheck` and `shfmt` are only needed for contributing to this repo, not for daily VM
usage.

## Install

```bash
./install.sh
```

The installer symlinks `bin/devvm` into `~/.local/bin/devvm`, creates `~/.config/devvm`,
and copies the default config only if it does not already exist.

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
devvm doctor
devvm ai create|update|enter|key|endpoint|status|logs
devvm gpg create-subkey|install|list|export-public
devvm completion bash|zsh
devvm self-update
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

No packages are installed by default. Install Fedora packages globally for every VM or
per VM:

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
`DEVVM_BACKUP_ENCRYPT="auto"` DevVM encrypts backups with host GPG symmetric encryption
when `gpg` is available, which may prompt for a backup passphrase; otherwise it writes a
plaintext archive and warns when secrets are included. Use `--encrypt` to require GPG
encryption or `--no-encrypt` to explicitly write plaintext.

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

Format shell files:

```bash
bash scripts/format.sh
```

Releases are tag-driven. Update `CHANGELOG.md`, commit the release notes, then push an
annotated tag:

```bash
git add CHANGELOG.md
git commit -m "chore: release v0.1.0"
bash scripts/prepare-release.sh 0.1.0 --push
```

Pull requests run CI automatically. Pushing a `v*` tag runs the release workflow and
creates a GitHub release from the matching `CHANGELOG.md` section.

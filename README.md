# DevVM

Keep your friends close, your supply chain in a VM.

DevVM creates disposable Fedora development VMs on macOS using Lima, Ansible, and
chezmoi. The opinionated workflow is:

```text
macOS: terminal + Lima + Ansible + devvm CLI
VM: Fedora + required system tools + optional dotfiles + source code under /code
```

Project source code is not stored on macOS by default. DevVM creates and configures a
VM, prepares `/code`, configures Git/SSH/GPG-capable tooling, and then you clone
repositories manually from inside the VM.

The default guest is intentionally small. Editors, terminal tools, Git workflow
preferences, and other personal tools belong in your DevVM config or chezmoi repo, not
in the project defaults.

## Requirements

- macOS on Apple Silicon
- Lima 2.x or newer
- Ansible
- OpenSSH client

Install common host dependencies with Homebrew:

```bash
brew install lima ansible
```

`shellcheck`, `shfmt`, and Node/pnpm are only needed for contributing to this repo, not
for daily VM usage.

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
git clone git@github.com:you/myapp.git /code/myapp
cd /code/myapp
```

## Commands

```text
devvm init
devvm new <name> [--ports "..."] [--mount host:guest[:ro|rw]]
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
devvm key <name>
devvm status
devvm doctor
devvm ai create|update|enter|key
devvm self-update
```

`devvm <name>` is a shortcut for `devvm enter <name>`.

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
identity; leave them empty if chezmoi owns Git config.

Fedora image selection is delegated to Lima's current built-in template:

```bash
LIMA_TEMPLATE="template:fedora"
```

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
`$HOME` and protected guest paths such as `/code`.

Generated Lima YAML and Ansible inventory live at:

```text
~/.local/share/devvm-state/generated/
```

## AI

Create a dedicated llama.cpp VM:

```bash
devvm ai create
```

Configure models in `~/.config/devvm/config.env`:

```bash
AI_LLAMA_MODELS="commit.gguf|https://example.com/commit.gguf|sha256:<hex>"
AI_COMMIT_MODEL="commit.gguf"
```

Development VMs call the AI VM through:

```text
http://host.lima.internal:18080/v1
```

Development VMs also install configured AI CLIs:

```bash
AI_TOOLS="claude@1.2.3 codex@1.2.3"
AI_EXTRA_NPM_PACKAGES=""
```

`AI_TOOLS` is empty by default. When AI npm tools are configured, DevVM installs Node
through `fnm` automatically unless the VM already has it.

They include `devvm-ai-commit`, which sends only `git diff --cached` to the llama.cpp
endpoint and prints a commit message.

## Development

Install repo tooling:

```bash
corepack enable pnpm
corepack pnpm install --frozen-lockfile
brew install shellcheck shfmt
```

Run all local checks:

```bash
corepack pnpm run check
```

Format supported files:

```bash
corepack pnpm run format
```

Release notes are managed with Changesets:

```bash
corepack pnpm run changeset
```

Pull requests run CI automatically. Merges to `main` create or update a Changesets
release PR; merging that release PR creates a GitHub release.

Repo tooling uses pnpm with a frozen lockfile, exact versions, delayed package release
age, trust downgrade protection, and blocked dependency build scripts by default.

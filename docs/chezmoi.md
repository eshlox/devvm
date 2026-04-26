# chezmoi

DevVM supports three chezmoi modes:

- `none`: do not install or apply chezmoi.
- `defaults`: copy `defaults/chezmoi` from this repo into the VM and apply it.
- `user-repo`: initialize chezmoi from `CHEZMOI_REPO` and `CHEZMOI_BRANCH`.

Configure this in `~/.config/devvm/config.env`:

```bash
CHEZMOI_MODE="user-repo"
CHEZMOI_REPO="git@github.com:you/dotfiles.git"
CHEZMOI_BRANCH="linux-vm"
CHEZMOI_APPLY_ARGS="--force"
```

The default source uses `.chezmoiroot` so files live under `home/`.

DevVM writes machine data for templates:

```toml
[data]
    name = "myapp"
    devvm = true
    codeDir = "/home/<user>/code"
```

chezmoi is the right place to configure personal tools such as editors, terminal
multiplexers, file managers, lazygit, and shell preferences. For example, your own
chezmoi repo can wire lazygit to `devvm-ai-commit`.

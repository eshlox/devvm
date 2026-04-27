# chezmoi

chezmoi is optional. DevVM will not install it by default.

To use it, install the Fedora package through global or per-VM package config, then set
your repo:

```bash
GLOBAL_PACKAGES="chezmoi"
CHEZMOI_REPO="git@github.com:you/dotfiles.git"
CHEZMOI_BRANCH="linux-vm"
CHEZMOI_APPLY_ARGS="--force"
```

DevVM writes machine data for templates before applying chezmoi:

```toml
[data]
    name = "myapp"
    devvm = true
    codeDir = "/home/<user>/code"
```

Use your own chezmoi repo for editors, shells, language runtimes, and project tooling.

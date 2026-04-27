# Homebrew Packaging

Homebrew is the recommended stable install and update path for normal users.

DevVM's own `install.sh --symlink` path is for development and testing. Keep it
separate from production config/state so development VMs cannot collide with real VMs.

## User Install

Because DevVM lives in a third-party tap, the one-command install form is:

```bash
brew install eshlox/devvm/devvm
```

Homebrew does not use `brew install eshlox/devvm` as a direct formula install. That
two-part name identifies the tap. If you want the shorter formula install, use two
commands:

```bash
brew tap eshlox/devvm
brew install devvm
```

Updates are managed by Homebrew:

```bash
brew update
brew upgrade devvm
```

`devvm self-update` is disabled for Homebrew installs.

## Tap Repository

Create a public tap repository named:

```text
eshlox/homebrew-devvm
```

The short tap name is `eshlox/devvm`.

Create it locally:

```bash
brew tap-new eshlox/homebrew-devvm
```

Copy the formula template from this repository:

```bash
cp packaging/homebrew/devvm.rb "$(brew --repository eshlox/devvm)/Formula/devvm.rb"
```

For each release, replace the version and SHA-256 in the formula:

```ruby
url "https://github.com/eshlox/devenv/releases/download/v0.1.0/devvm-v0.1.0.tar.gz"
sha256 "<sha256 from SHA256SUMS>"
```

Do not make the formula run `install.sh`. The formula should install release files under
Homebrew `libexec` and link `bin/devvm`.

## Test The Formula

From the tap checkout:

```bash
brew audit --strict --online devvm
brew install --build-from-source devvm
brew test devvm
```

For a local unpublished formula file:

```bash
brew install --build-from-source ./Formula/devvm.rb
brew test devvm
```

## Development Install

Use a separate command, config directory, state directory, and VM prefix:

```bash
./install.sh --symlink \
  --name devvm-dev \
  --prefix "$HOME/.local/bin" \
  --install-dir "$HOME/.local/share/devvm-dev-install" \
  --config-dir "$HOME/.config/devvm-dev" \
  --state-dir "$HOME/.local/share/devvm-dev-state" \
  --vm-prefix devvm-dev
```

Then use:

```bash
devvm-dev init
devvm-dev new scratch
devvm-dev create scratch
```

Those VMs are named `devvm-dev-*` and use separate config/state from the production
`devvm` command.

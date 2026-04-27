# Threat Model

DevVM reduces blast radius for risky development tasks. It does not guarantee malware
containment or replace endpoint security.

Protected by default:

- macOS home directory is not mounted.
- Other projects are not mounted.
- VM SSH keys are generated inside the VM.
- Source code lives only in the VM disk under `~/code`.
- Optional backups are host-side tar archives, not live mounts.
- Optional GPG commit signing imports only selected signing subkeys into VMs; the
  primary GPG key should remain on macOS.

Still in scope for risk:

- Explicit share mounts can be read and, if `rw`, modified by the VM.
- DevVM rejects broad/sensitive host shares by default, but an explicit override can
  still weaken the boundary.
- Forwarded ports expose services on the host.
- The optional llama.cpp VM exposes a forwarded local API port. Other VMs can reach it
  through the macOS host forwarding address.
- A compromised VM can access code, keys, history, and secrets stored inside that VM.
- A compromised VM that has a GPG signing subkey can sign commits until that subkey is
  revoked or expires.
- Reusing one GPG signing subkey across many VMs increases the blast radius compared
  with one subkey per VM/project.
- Backups that include secrets contain VM SSH keys, GPG data, shell history, and tool
  credentials. Keep `DEVVM_BACKUP_ENCRYPT="1"` unless you explicitly intend to create
  code-only plaintext backups with `--no-secrets`.
- Host-side Lima and terminal processes remain trusted.
- `config.env`, `local.env`, and VM config files are parsed as data, not sourced as
  Bash. Treat them as sensitive config because they still decide what VMs install and
  run.
- Setup scripts configured with `GLOBAL_SETUP_SCRIPTS` or `SETUP_SCRIPTS` run inside
  VMs with the same trust level as commands you type manually in that VM.
- Configured AI model downloads trust the configured URL and checksum. DevVM requires
  SHA-256 checksums for model downloads and rejects HTTP by default.
- Homebrew installs trust Homebrew, the `eshlox/devvm` tap, and the release archive
  SHA-256 pinned in the formula. They do not use DevVM's self-updater.
- Source-checkout `devvm self-update` trusts the configured Git remote. A compromised
  upstream can execute host-side code on the next run.
- Copied installs can periodically query the configured release remote with
  `git ls-remote` to discover new tags. This is network metadata only; installation
  still requires the signed-tag self-update path.
- Copied-install `devvm self-update --version <tag>` verifies release tags with
  `git verify-tag` and a trusted signer allowlist by default. Skipping tag or signer
  verification weakens that boundary.

# Architecture

DevVM is a thin lifecycle wrapper around trusted tools:

- Lima owns VM creation, start, stop, delete, networking, mounts, and SSH.
- Fedora is the default guest distribution.
- A small shell provisioner creates VM-local directories and SSH keys.
- User config owns package lists and setup scripts.
- An optional AI VM installs Fedora's llama.cpp package and exposes a local model API.
- The shell CLI coordinates config loading, Lima template overrides, audit rendering,
  and tool calls.

Runtime state is generated under `~/.local/share/devvm-state`. User config lives under
`~/.config/devvm`. The core checkout should be treated as read-only except during
upgrades.

The primary boundary is VM-first isolation. Source code is cloned manually inside the VM
under `~/code`; there is no project folder on macOS by default. Explicit shares are
available only for narrow file exchange paths.

The default guest does not install personal tools such as editors, lazygit, file
managers, shells, language runtimes, or terminal multiplexers. Those belong in
`PACKAGES`, `GLOBAL_PACKAGES`, `SETUP_SCRIPTS`, or `GLOBAL_SETUP_SCRIPTS`.

The AI VM is intentionally narrow: it runs llama.cpp as a shared service. Claude,
Codex, editor integrations, and client CLIs remain user-owned setup choices inside the
VMs where the user wants them.

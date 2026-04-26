# Architecture

DevVM is a thin lifecycle wrapper around trusted tools:

- Lima owns VM creation, start, stop, delete, networking, mounts, and SSH.
- Fedora is the default guest distribution.
- Ansible owns repeatable system provisioning.
- chezmoi owns dotfiles and per-machine shell/editor configuration.
- The shell CLI coordinates config loading, Lima template overrides, audit rendering,
  and tool calls.
- A dedicated optional AI VM runs llama.cpp for local model inference.

Runtime state is generated under `~/.local/share/devvm-state`. User config lives under
`~/.config/devvm`. The core checkout should be treated as read-only except during
upgrades.

The primary boundary is VM-first isolation. Source code is cloned manually inside the VM
under `~/code`; there is no project folder on macOS by default. Explicit shares are
available only for narrow file exchange paths.

Project VMs can call the AI VM through the AI VM's forwarded llama.cpp endpoint. This
gives every project VM access to one model server without installing models inside each
VM.

The default guest does not install personal tools such as editors, lazygit, file
managers, shells, or terminal multiplexers. Those belong in user config and chezmoi.

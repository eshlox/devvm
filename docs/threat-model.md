# Threat Model

DevVM reduces blast radius for risky development tasks. It does not guarantee malware
containment or replace endpoint security.

Protected by default:

- macOS home directory is not mounted.
- Other projects are not mounted.
- VM SSH keys are generated inside the VM.
- Source code lives only in the VM disk under `/code`.

Still in scope for risk:

- Explicit share mounts can be read and, if `rw`, modified by the VM.
- Forwarded ports expose services on the host.
- A compromised VM can access code, keys, history, and secrets stored inside that VM.
- AI requests sent to the llama.cpp VM expose prompt content to that AI VM.
- Host-side Lima, Ansible, and terminal processes remain trusted.

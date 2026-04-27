# AI

DevVM has two AI layers:

- A dedicated `devvm-ai` VM that runs llama.cpp as an OpenAI-compatible API.
- Per-development-VM AI tools such as Claude Code, Codex, and `devvm-ai-commit`.

## llama.cpp VM

Create the AI VM:

```bash
devvm ai create
```

This creates `~/.config/devvm/vms/ai.env` if missing, then provisions a VM with
`DEVVM_ROLE="ai"`. The role installs Fedora's `llama-cpp` package, downloads configured
GGUF models, and starts `llama-server`.

Configure models in `~/.config/devvm/config.env`:

```bash
AI_LLAMA_MODELS="commit.gguf|https://example.com/commit.gguf|sha256:<hex>"
AI_COMMIT_MODEL="commit.gguf"
```

Model entries are space-separated and use:

```text
filename.gguf|https://download-url|sha256:<hex>
```

The checksum is required. Model URLs must use `https` unless
`AI_ALLOW_HTTP_MODEL_URLS=1` is set; HTTP downloads still require a matching SHA-256
checksum.

The server listens inside the AI VM on port `8080`, forwarded to macOS on `18080`. Other
DevVMs reach it at:

```text
http://host.lima.internal:18080/v1
```

## External AI CLIs

DevVM does not install npm-published AI CLIs automatically. Keep `AI_TOOLS` and
`AI_EXTRA_NPM_PACKAGES` empty unless you intentionally want provisioning to fail as a
guardrail:

```bash
AI_TOOLS=""
AI_EXTRA_NPM_PACKAGES=""
```

Install non-DNF tools through your own dotfiles only when you explicitly accept that
source. DevVM-provisioned tools should come from Fedora packages.

## Commit Messages

Development VMs include:

```bash
devvm-ai-commit
```

It reads only staged changes:

```bash
git diff --cached
```

Then it sends that diff to the llama.cpp endpoint and prints a concise commit message.

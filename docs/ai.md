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
`DEVVM_ROLE="ai"`. The role clones and builds llama.cpp, downloads configured GGUF
models, and starts `llama-server`.

Configure models in `~/.config/devvm/config.env`:

```bash
AI_LLAMA_MODELS="commit.gguf|https://example.com/commit.gguf"
AI_COMMIT_MODEL="commit.gguf"
```

Model entries are space-separated and use:

```text
filename.gguf|https://download-url
```

The server listens inside the AI VM on port `8080`, forwarded to macOS on `18080`. Other
DevVMs reach it at:

```text
http://host.lima.internal:18080/v1
```

## AI CLIs

Development VMs install configured AI CLIs automatically when `AI_TOOLS` or
`AI_EXTRA_NPM_PACKAGES` is set:

```bash
AI_TOOLS="claude codex"
AI_EXTRA_NPM_PACKAGES=""
```

Both values are empty by default. Configuring either value causes DevVM to install Node
through `fnm` for that VM.

Supported built-ins:

- `claude` installs `@anthropic-ai/claude-code`.
- `codex` installs `@openai/codex`.

Extra npm packages can be listed in `AI_EXTRA_NPM_PACKAGES`.

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

# Local LLaMA

DevVM has one built-in AI feature: an optional dedicated VM for llama.cpp.

It stays separate from project VMs. DevVM does not install Claude, Codex, Node.js,
Python packages, editor plugins, or other AI tools into development VMs. Users can add
those through their own `PACKAGES` and `SETUP_SCRIPTS`.

## Create The VM

Configure a model in `~/.config/devvm/config.env`:

```bash
AI_LLAMA_MODELS="model.gguf|https://example.com/model.gguf|sha256:<64 hex chars>"
AI_LLAMA_MODEL="model.gguf"
```

Create or update the service VM:

```bash
devvm ai create
devvm ai update
```

The generated VM config lives at:

```text
~/.config/devvm/vms/ai.env
```

By default it installs only Fedora's `llama-cpp` package and forwards guest port `8080`
to macOS port `18080`.

## Models

Downloads are optional. If `AI_LLAMA_MODELS` is set, each entry must use:

```text
filename.gguf|https://download-url|sha256:<64 hex chars>
```

Checksums are mandatory for downloads. HTTP URLs are rejected unless
`AI_ALLOW_HTTP_MODEL_URLS=1` is set.

To manage models yourself, leave `AI_LLAMA_MODELS` empty, put a GGUF file under
`AI_LLAMA_MODELS_DIR` inside the AI VM, set `AI_LLAMA_MODEL`, and run:

```bash
devvm ai update
```

You can also mount a host model directory into the AI VM:

```bash
AI_LLAMA_MOUNTS="$HOME/devvm-models:$DEVVM_GUEST_HOME/models:ro"
AI_LLAMA_MODEL="model.gguf"
```

## Endpoint

Print the endpoint:

```bash
devvm ai endpoint
```

The default value is:

```text
http://host.lima.internal:18080/v1
```

Other DevVMs can use that URL for OpenAI-compatible clients.

## Service

The VM runs a systemd service named `devvm-llama.service` using `llama-server` from the
Fedora package.

Useful commands:

```bash
devvm ai status
devvm ai logs
devvm ai logs --follow
```

Common tuning knobs:

```bash
AI_VM_CPUS="8"
AI_VM_MEMORY="16GiB"
AI_VM_DISK="160GiB"
AI_LLAMA_CTX_SIZE="8192"
AI_LLAMA_EXTRA_ARGS="--parallel 2"
```

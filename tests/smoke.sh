#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

MOCK_BIN="$TMP_ROOT/bin"
CONFIG_DIR="$TMP_ROOT/config"
STATE_DIR="$TMP_ROOT/state"
LOG_FILE="$TMP_ROOT/commands.log"

mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/limactl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  list)
    exit 0
    ;;
  template)
    if [ "${2:-}" = "yq" ]; then
      printf '1\n'
      exit 0
    fi
    printf 'unexpected limactl template command: %s\n' "$*" >&2
    exit 1
    ;;
  create)
    printf 'limactl create' >>"$DEVVM_TEST_LOG"
    shift
    for arg in "$@"; do
      printf ' %q' "$arg" >>"$DEVVM_TEST_LOG"
    done
    printf '\n' >>"$DEVVM_TEST_LOG"
    ;;
  start)
    printf 'limactl start %q\n' "${2:-}" >>"$DEVVM_TEST_LOG"
    ;;
  *)
    printf 'unexpected limactl command: %s\n' "$*" >&2
    exit 1
    ;;
esac
MOCK

cat >"$MOCK_BIN/ansible-playbook" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf 'ansible-playbook' >>"$DEVVM_TEST_LOG"
for arg in "$@"; do
  printf ' %q' "$arg" >>"$DEVVM_TEST_LOG"
done
printf '\n' >>"$DEVVM_TEST_LOG"
MOCK

chmod +x "$MOCK_BIN/limactl" "$MOCK_BIN/ansible-playbook"

export DEVVM_CORE="$ROOT"
export DEVVM_CONFIG="$CONFIG_DIR"
export DEVVM_STATE="$STATE_DIR"
export DEVVM_TEST_LOG="$LOG_FILE"
export USER="dev"
export PATH="$MOCK_BIN:$PATH"

"$ROOT/bin/devvm" init >/dev/null
"$ROOT/bin/devvm" new app --ports "3000 5173" --mount "$TMP_ROOT/share:/share:rw" >/dev/null
"$ROOT/bin/devvm" create app >/dev/null

grep -Fq "NODE_VERSION=''" "$CONFIG_DIR/vms/app.env"
grep -Fq "MOUNTS='$TMP_ROOT/share:/share:rw'" "$CONFIG_DIR/vms/app.env"
if grep -Fq "TMUX_SESSION" "$CONFIG_DIR/vms/app.env"; then
	echo "unexpected TMUX_SESSION in generated VM config" >&2
	exit 1
fi
grep -Fq 'template:fedora' "$LOG_FILE"
grep -Fq -- '--tty=false' "$LOG_FILE"
grep -Fq 'mountPoint: "/share"' "$STATE_DIR/generated/devvm-app.yaml"
grep -Fq 'code_dir="/home/dev/code"' "$STATE_DIR/generated/inventory.ini"
grep -Fq 'git_user_name=""' "$STATE_DIR/generated/inventory.ini"
grep -Fq 'ai_tools=""' "$STATE_DIR/generated/inventory.ini"

cat >>"$CONFIG_DIR/config.env" <<'CONFIG'
AI_LLAMA_MODELS="commit.gguf|https://example.com/commit.gguf"
AI_TOOLS="claude codex"
CONFIG

"$ROOT/bin/devvm" ai create >/dev/null

grep -Fq "DEVVM_ROLE='ai'" "$CONFIG_DIR/vms/ai.env"
grep -Fq "PORTS='8080:18080'" "$CONFIG_DIR/vms/ai.env"
grep -Fq 'devvm_role="ai"' "$STATE_DIR/generated/inventory.ini"
grep -Fq 'ai_commit_model="commit.gguf"' "$STATE_DIR/generated/inventory.ini"
grep -Fq 'guestPort: 8080' "$STATE_DIR/generated/devvm-ai.yaml"
grep -Fq 'hostPort: 18080' "$STATE_DIR/generated/devvm-ai.yaml"

COMPLETION_FILE="$TMP_ROOT/devvm-completion.bash"
"$ROOT/bin/devvm" completion bash >"$COMPLETION_FILE"
grep -Fq 'complete -F _devvm_completion devvm' "$COMPLETION_FILE"
"$ROOT/bin/devvm" completion zsh | grep -Fq 'compdef _devvm devvm'

# shellcheck source=/dev/null
source "$COMPLETION_FILE"

devvm_assert_completion() {
	local expected
	expected="$1"
	shift

	COMP_WORDS=("$@")
	COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
	_devvm_completion

	if ! printf '%s\n' "${COMPREPLY[@]}" | grep -Fxq -- "$expected"; then
		printf 'missing completion %s for words:' "$expected" >&2
		printf ' <%s>' "$@" >&2
		printf '\nactual completions:\n' >&2
		printf '%s\n' "${COMPREPLY[@]}" >&2
		exit 1
	fi
}

devvm_assert_completion "new" devvm ""
devvm_assert_completion "app" devvm ""
devvm_assert_completion "app" devvm enter ""
devvm_assert_completion "all" devvm stop ""
devvm_assert_completion "--ports" devvm new app --
devvm_assert_completion "--yes" devvm delete app ""
devvm_assert_completion "--yes" devvm delete app --
devvm_assert_completion "create" devvm ai ""
devvm_assert_completion "bash" devvm completion ""

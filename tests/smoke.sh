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
    if [ -n "${DEVVM_TEST_LIMA_LIST:-}" ] && [ -f "$DEVVM_TEST_LIMA_LIST" ]; then
      cat "$DEVVM_TEST_LIMA_LIST"
    fi
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
  delete)
    printf 'limactl delete' >>"$DEVVM_TEST_LOG"
    shift
    for arg in "$@"; do
      printf ' %q' "$arg" >>"$DEVVM_TEST_LOG"
    done
    printf '\n' >>"$DEVVM_TEST_LOG"
    ;;
  *)
    printf 'unexpected limactl command: %s\n' "$*" >&2
    exit 1
    ;;
esac
MOCK

cat >"$MOCK_BIN/ssh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf 'ssh' >>"$DEVVM_TEST_LOG"
for arg in "$@"; do
  printf ' %q' "$arg" >>"$DEVVM_TEST_LOG"
done
printf '\n' >>"$DEVVM_TEST_LOG"
if printf '%s\n' "$*" | grep -Fq 'devvm-backup'; then
  printf 'backup-archive'
  exit 0
fi
cat >"$DEVVM_TEST_SSH_STDIN"
MOCK

cat >"$MOCK_BIN/gpg" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

exit 0
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

chmod +x "$MOCK_BIN/limactl" "$MOCK_BIN/ssh" "$MOCK_BIN/gpg" "$MOCK_BIN/ansible-playbook"

export DEVVM_CORE="$ROOT"
export DEVVM_CONFIG="$CONFIG_DIR"
export DEVVM_STATE="$STATE_DIR"
export DEVVM_TEST_LOG="$LOG_FILE"
export DEVVM_TEST_LIMA_LIST="$TMP_ROOT/lima-list"
export DEVVM_TEST_SSH_STDIN="$TMP_ROOT/ssh-stdin"
export USER="dev"
export HOME="$TMP_ROOT/home"
export PATH="$MOCK_BIN:$PATH"
mkdir -p "$HOME"

LEGACY_CONFIG_DIR="$TMP_ROOT/legacy-config"
mkdir -p "$LEGACY_CONFIG_DIR"
cat >"$LEGACY_CONFIG_DIR/config.env" <<'CONFIG'
AI_ALLOW_INSECURE_MODEL_URLS="1"
CONFIG

DEVVM_CORE="$ROOT" DEVVM_CONFIG="$LEGACY_CONFIG_DIR" DEVVM_STATE="$TMP_ROOT/legacy-state" bash -c '
set -euo pipefail
source "$DEVVM_CORE/lib/util.sh"
source "$DEVVM_CORE/lib/config.sh"
devvm_load_config
[ "$AI_ALLOW_HTTP_MODEL_URLS" = "1" ]
'

"$ROOT/bin/devvm" init >/dev/null
"$ROOT/bin/devvm" new nodeapp --node >/dev/null
"$ROOT/bin/devvm" create nodeapp >/dev/null
grep -Fq "INSTALL_NODE='1'" "$CONFIG_DIR/vms/nodeapp.env"
grep -Fq 'devvm-nodeapp' "$STATE_DIR/generated/inventory.ini"
grep -Fq 'install_node="1"' "$STATE_DIR/generated/inventory.ini"

"$ROOT/bin/devvm" new app --ports "3000 5173" --mount "$TMP_ROOT/share:/share:rw" >/dev/null
"$ROOT/bin/devvm" create app >/dev/null
printf 'devvm-app\n' >"$DEVVM_TEST_LIMA_LIST"

grep -Fq "INSTALL_NODE='0'" "$CONFIG_DIR/vms/app.env"
grep -Fq "MOUNTS='$TMP_ROOT/share:/share:rw'" "$CONFIG_DIR/vms/app.env"
if grep -Fq "TMUX_SESSION" "$CONFIG_DIR/vms/app.env"; then
	echo "unexpected TMUX_SESSION in generated VM config" >&2
	exit 1
fi
grep -Fq 'template:fedora' "$LOG_FILE"
grep -Fq -- '--tty=false' "$LOG_FILE"
grep -Fq 'mountPoint: "/share"' "$STATE_DIR/generated/devvm-app.yaml"
grep -Fq 'code_dir="/home/dev/code"' "$STATE_DIR/generated/inventory.ini"
grep -Fq 'devvm-app' "$STATE_DIR/generated/inventory.ini"
grep -Fq 'install_node="0"' "$STATE_DIR/generated/inventory.ini"
grep -Fq 'git_user_name=""' "$STATE_DIR/generated/inventory.ini"
grep -Fq 'ai_tools=""' "$STATE_DIR/generated/inventory.ini"

cat >>"$CONFIG_DIR/config.env" <<'CONFIG'
AI_LLAMA_MODELS="commit.gguf|https://example.com/commit.gguf|sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
AI_ALLOW_HTTP_MODEL_URLS="1"
CONFIG

"$ROOT/bin/devvm" ai create >/dev/null
"$ROOT/bin/devvm" gpg --help | grep -Fq 'devvm gpg create-subkey'
mkdir -p "$HOME/.lima/devvm-app"
touch "$HOME/.lima/devvm-app/ssh.config"
printf 'secret-subkey-bundle' >"$TMP_ROOT/subkey.asc"
"$ROOT/bin/devvm" gpg install app "$TMP_ROOT/subkey.asc" --signing-key ABCDEF >/dev/null
grep -Fq 'secret-subkey-bundle' "$DEVVM_TEST_SSH_STDIN"
"$ROOT/bin/devvm" backup app --no-encrypt --no-secrets >/dev/null
BACKUP_FILE="$(find "$STATE_DIR/backups/app" -type f -name '*.tar.gz' -print | sort | tail -n 1)"
[ -n "$BACKUP_FILE" ]
grep -Fq 'backup-archive' "$BACKUP_FILE"
"$ROOT/bin/devvm" backups app | grep -Fq "$BACKUP_FILE"
"$ROOT/bin/devvm" restore app "$BACKUP_FILE" --no-secrets >/dev/null
"$ROOT/bin/devvm" delete app --yes --no-encrypt --no-secrets >/dev/null

grep -Fq "DEVVM_ROLE='ai'" "$CONFIG_DIR/vms/ai.env"
grep -Fq "PORTS='8080:18080'" "$CONFIG_DIR/vms/ai.env"
grep -Fq 'devvm_role="ai"' "$STATE_DIR/generated/inventory.ini"
grep -Fq 'ai_commit_model="commit.gguf"' "$STATE_DIR/generated/inventory.ini"
grep -Fq 'ai_allow_http_model_urls="1"' "$STATE_DIR/generated/inventory.ini"
grep -Fq 'guestPort: 8080' "$STATE_DIR/generated/devvm-ai.yaml"
grep -Fq 'hostPort: 18080' "$STATE_DIR/generated/devvm-ai.yaml"
grep -Fq 'ssh -F' "$LOG_FILE"
grep -Fq 'lima-devvm-app' "$LOG_FILE"
grep -Fq 'devvm-backup' "$LOG_FILE"
grep -Fq 'devvm-restore' "$LOG_FILE"
grep -Fq 'limactl delete --force devvm-app' "$LOG_FILE"

COMPLETION_FILE="$TMP_ROOT/devvm-completion.bash"
"$ROOT/bin/devvm" completion bash >"$COMPLETION_FILE"
grep -Fq 'complete -o default -F _devvm_completion devvm' "$COMPLETION_FILE"
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
devvm_assert_completion "--node" devvm new app --
devvm_assert_completion "--yes" devvm delete app ""
devvm_assert_completion "--no-backup" devvm delete app --
devvm_assert_completion "--yes" devvm delete app --
devvm_assert_completion "--no-restore" devvm rebuild app --
devvm_assert_completion "app" devvm backup ""
devvm_assert_completion "--no-encrypt" devvm backup app --
devvm_assert_completion "app" devvm restore ""
devvm_assert_completion "--no-secrets" devvm restore app backup.tar.gz --
devvm_assert_completion "create" devvm ai ""
devvm_assert_completion "gpg" devvm ""
devvm_assert_completion "create-subkey" devvm gpg ""
devvm_assert_completion "create-subkey" devvm gpg c
devvm_assert_completion "app" devvm gpg install ""
devvm_assert_completion "--label" devvm gpg create-subkey primary --
devvm_assert_completion "--signing-key" devvm gpg install app subkey.asc ""
devvm_assert_completion "bash" devvm completion ""

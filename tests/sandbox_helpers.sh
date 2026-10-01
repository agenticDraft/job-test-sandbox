# Shared setup for bin/sandbox tests: fake docker first on PATH, a temp work dir.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib.sh"
setup() {
  T="$(mktemp -d "${TMPDIR:-/tmp}/sandbox-test.XXXXXX")"
  export FAKE_DOCKER_LOG="$T/docker.log"; : > "$FAKE_DOCKER_LOG"
  export FAKE_DOCKER_STDIN="$T/stdin"
  export SANDBOX_WORK_DIR="$T/work"
  export FAKE_DOCKER_VOLUMES="" FAKE_DOCKER_RUNNING="" FAKE_DOCKER_STOPPED="" FAKE_DOCKER_EXIT=0
  export FAKE_DOCKER_IMAGES="job-sandbox:base"
  export PATH="$ROOT/tests/fakebin:/usr/bin:/bin"
  # Tests run as if from your own terminal; test_sandbox_guard_required.sh sets CLAUDECODE itself.
  unset CLAUDECODE
  export SANDBOX_SETTINGS="$T/settings.json"
}
# run <args...>: bin/sandbox with stdin from /dev/null; sets OUT (stdout+stderr) and CODE.
run() { OUT="$("$ROOT/bin/sandbox" "$@" </dev/null 2>&1)"; CODE=$?; }
log() { cat "$FAKE_DOCKER_LOG"; }
clear_log() { : > "$FAKE_DOCKER_LOG"; }
verdict() {
  mkdir -p "$SANDBOX_WORK_DIR/$1"
  printf '# Scan %s\n\nVerdict: %s\n' "$1" "$2" > "$SANDBOX_WORK_DIR/$1/scan.md"
}

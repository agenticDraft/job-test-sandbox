# Sandbox UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One `sandbox` command, three guardrail layers and four "where am I" indicators, so a
job test can be run step by step without raw `docker` commands or isolation mistakes.

**Architecture:** `bin/sandbox` (bash) is the only thing that talks to Docker. Claude reaches it
through a PreToolUse hook that allows little else in this repo. The base image carries the
container-side defaults (npm scripts off, orange prompt and code-server colours). A zsh file on
the Mac guards `docker` calls that name sandbox objects and marks the prompt. Everything on the
Mac side is tested now against a fake `docker`; the image is checked in Phase 6 once OrbStack is
installed.

**Tech Stack:** bash 3.2 (macOS `/bin/bash`), zsh 5.9, `jq` (`/usr/bin/jq`), `openssl`
(`/usr/bin/openssl`), Docker via OrbStack, code-server (standalone install), `node:24-bookworm`.

**Spec:** `docs/superpowers/specs/2026-10-01-sandbox-ux-design.md`

## Global Constraints

- `bin/sandbox`, `.claude/hooks/guard.sh`, `.claude/statusline.sh` and all tests run on macOS
  `/bin/bash` 3.2: no associative arrays, no `mapfile`, no `${x,,}`, no empty-array expansion
  under `set -u`.
- No new dependencies on the Mac beyond `docker` (OrbStack), `jq`, `openssl`, `zsh`.
- All code, comments, docs and commit messages in English.
- Plans, docs and commits use `Phase N / Task M` naming; no letter-prefixed codes.
- The repo is public: never commit anything under `work/`.
- Never run, open or `cd` into test code on the Mac; tests use only fake data.
- The Claude hook is activated (settings.json) only in Phase 5 / Task 3, so earlier tasks can
  run their tests freely.

## Review Focus

- Docker not installed or daemon down → `sandbox status --short` still prints one line, so the
  Claude statusline never breaks (test in Phase 1 / Task 1).
- Firm names with uppercase, spaces, slashes or `..` → refused before any `docker` call (Phase 1
  / Task 1).
- Compound or smuggled shell commands sent to the guard (`ls; npm i`, `$(…)`, `PATH=x …`,
  `bash -c`) → denied, not allowed by their first word (Phase 2 / Task 1).
- A test repo's own git config running programs during a scan (`diff.external`, textconv,
  `core.fsmonitor`, hooks) → neutralised on every `sandbox scan … git …` call (Phase 1 / Task 2).
- `scan.md` with a malformed or lowercase verdict (`Verdict: green`) → treated as no verdict,
  so `sandbox up` refuses (Phase 1 / Task 1 and Task 3).

## Deviations from the spec (decided while planning)

- `sandbox build` added: the hook forbids direct `docker`, so building the image needs a
  subcommand.
- `scan.md` verdict format fixed as a line `Verdict: Green|Question|Red` (exact case).
- `sandbox rm` asks for the firm name in a terminal; without a terminal it needs `--yes`, and
  the hook turns any `bin/sandbox rm` from Claude into a permission prompt.
- npm: `NPM_CONFIG_IGNORE_SCRIPTS=true` in the image environment instead of `/etc/npmrc` (the
  global npmrc of the node image lives under `/usr/local/etc`, the env var works regardless).
  The exception becomes `npm rebuild <pkg> --ignore-scripts=false`.
- code-server window title is `🧪 SANDBOX — ${rootName}` (folder name); the firm name is in the
  terminal prompt. VS Code settings have no hostname variable.
- `.vscode` automatic tasks are switched off in code-server settings
  (`task.allowAutomaticTasks: off`), closing the `runOn: folderOpen` route.

---

## Phase 1 — The `sandbox` command

### Task 1: Test harness, fake docker, skeleton and `status`

**Files:**
- Create: `tests/lib.sh`, `tests/run.sh`, `tests/fakebin/docker`, `tests/sandbox_helpers.sh`,
  `tests/test_sandbox_status.sh`
- Create: `bin/sandbox`

**Interfaces:**
- Produces (bin/sandbox functions used by later tasks): `die msg`, `need_docker`, `need_image`,
  `check_firm firm`, `volume_exists firm`, `need_volume firm`,
  `container_state firm` → prints `running|stopped|missing`, `need_running firm`,
  `scan_verdict firm` → prints `Green|Question|Red|none`; globals `IMAGE`, `ROOT`, `WORK`,
  `PROJECT`, `HARDEN` (array).
- Produces (tests): `setup`, `run <args>` → sets `OUT`, `CODE`; `log`; `verdict firm word`;
  `assert_eq`, `assert_contains`, `assert_not_contains`, `finish`. Fake docker reads
  `FAKE_DOCKER_LOG`, `FAKE_DOCKER_STDIN`, `FAKE_DOCKER_VOLUMES`, `FAKE_DOCKER_RUNNING`,
  `FAKE_DOCKER_STOPPED`, `FAKE_DOCKER_IMAGES`, `FAKE_DOCKER_EXIT`.

- [ ] **Step 1: Write the test helpers**

`tests/lib.sh`:

```bash
# Tiny assert helpers for the shell tests; macOS /bin/bash 3.2 compatible.
FAILS=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else
    fail "$1"; printf '       expected: %s\n       actual:   %s\n' "$2" "$3"; fi
}
assert_contains() {
  case "$3" in *"$2"*) pass "$1" ;; *)
    fail "$1"; printf '       missing: %s\n       in:      %s\n' "$2" "$3" ;; esac
}
assert_not_contains() {
  case "$3" in *"$2"*)
    fail "$1"; printf '       unexpected: %s\n       in:         %s\n' "$2" "$3" ;; *) pass "$1" ;; esac
}
finish() { [ "$FAILS" -eq 0 ]; }
```

`tests/run.sh`:

```bash
#!/bin/bash
# Runs tests/test_*.sh (or the files given) with macOS /bin/bash; non-zero exit on any failure.
cd "$(dirname "$0")/.." || exit 1
status=0
if [ $# -gt 0 ]; then files="$*"; else files="$(ls tests/test_*.sh)"; fi
for t in $files; do
  echo "== $t"
  /bin/bash "$t" || status=1
done
if [ $status -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $status
```

`tests/fakebin/docker`:

```bash
#!/bin/bash
# Test double for docker (tests only). Logs every call and answers the queries bin/sandbox makes.
echo "$*" >> "${FAKE_DOCKER_LOG:?FAKE_DOCKER_LOG not set}"
has() { local x; for x in $1; do [ "$x" = "$2" ] && return 0; done; return 1; }
last="${!#}"
case "$1" in
  image) has "$FAKE_DOCKER_IMAGES" "$last"; exit $? ;;
  volume)
    case "$2" in
      inspect) has "$FAKE_DOCKER_VOLUMES" "$last"; exit $? ;;
      ls) for v in $FAKE_DOCKER_VOLUMES; do echo "$v"; done; exit 0 ;;
      *) exit 0 ;;
    esac ;;
  container)
    if has "$FAKE_DOCKER_RUNNING" "$last"; then echo true; exit 0; fi
    if has "$FAKE_DOCKER_STOPPED" "$last"; then echo false; exit 0; fi
    echo "Error: No such container: $last" >&2; exit 1 ;;
esac
case " $* " in *" -i "*) cat > "${FAKE_DOCKER_STDIN:-/dev/null}" ;; esac
case "$*" in *"git bundle"*|*"git archive"*) echo FAKE-OUTPUT ;; esac
exit "${FAKE_DOCKER_EXIT:-0}"
```

`tests/sandbox_helpers.sh`:

```bash
# Shared setup for bin/sandbox tests: fake docker first on PATH, a temp work dir.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib.sh"
setup() {
  T="$(mktemp -d)"
  export FAKE_DOCKER_LOG="$T/docker.log"; : > "$FAKE_DOCKER_LOG"
  export FAKE_DOCKER_STDIN="$T/stdin"
  export SANDBOX_WORK_DIR="$T/work"
  export FAKE_DOCKER_VOLUMES="" FAKE_DOCKER_RUNNING="" FAKE_DOCKER_STOPPED="" FAKE_DOCKER_EXIT=0
  export FAKE_DOCKER_IMAGES="job-sandbox:base"
  export PATH="$ROOT/tests/fakebin:/usr/bin:/bin"
}
# run <args...>: bin/sandbox with stdin from /dev/null; sets OUT (stdout+stderr) and CODE.
run() { OUT="$("$ROOT/bin/sandbox" "$@" </dev/null 2>&1)"; CODE=$?; }
log() { cat "$FAKE_DOCKER_LOG"; }
clear_log() { : > "$FAKE_DOCKER_LOG"; }
verdict() {
  mkdir -p "$SANDBOX_WORK_DIR/$1"
  printf '# Scan %s\n\nVerdict: %s\n' "$1" "$2" > "$SANDBOX_WORK_DIR/$1/scan.md"
}
```

Run: `chmod +x tests/run.sh tests/fakebin/docker`

- [ ] **Step 2: Write the failing status tests**

`tests/test_sandbox_status.sh`:

```bash
. "$(dirname "$0")/sandbox_helpers.sh"
setup

run
assert_eq "no args: exit 0" 0 "$CODE"
assert_contains "no args: usage lists status" "status [firm] [--short]" "$OUT"
run bogus
assert_eq "unknown command: exit 2" 2 "$CODE"

run status Acme
assert_eq "uppercase firm refused" 1 "$CODE"
assert_contains "firm rule explained" "lowercase" "$OUT"
run status '../x'
assert_eq "path-like firm refused" 1 "$CODE"
run status 'a b'
assert_eq "firm with space refused" 1 "$CODE"
assert_eq "bad firms never reach docker" "" "$(log | grep -v '^volume ls')"

run status --short
assert_eq "short, no projects" "🛡 sandbox: none" "$OUT"
run status
assert_contains "long, no projects" "No projects" "$OUT"

OUT="$(PATH=/usr/bin:/bin "$ROOT/bin/sandbox" status --short 2>&1)"
assert_eq "short without docker still prints a line" "🛡 sandbox: docker not installed" "$OUT"
OUT="$(PATH=/usr/bin:/bin "$ROOT/bin/sandbox" status 2>&1)"; CODE=$?
assert_eq "long without docker fails" 1 "$CODE"
assert_contains "long without docker says how to fix" "OrbStack" "$OUT"

export FAKE_DOCKER_VOLUMES="jt-acme jt-beta" FAKE_DOCKER_RUNNING="jt-beta"
verdict acme Question
verdict beta Green
run status
assert_contains "question project line" \
  "acme  scan=Question  container=missing  next: read work/acme/scan.md, then: sandbox up acme --accept-question" "$OUT"
assert_contains "running project line" \
  "beta  scan=Green  container=running  next: work at http://127.0.0.1:8443; when done: sandbox export beta" "$OUT"
run status --short
assert_eq "short picks the running project" "🛡 sandbox: beta · Green · running (+1)" "$OUT"

export FAKE_DOCKER_VOLUMES="jt-acme" FAKE_DOCKER_RUNNING=""
printf 'Verdict: green\n' > "$SANDBOX_WORK_DIR/acme/scan.md"
run status acme
assert_contains "lowercase verdict is no verdict" 'acme  scan=none  container=missing  next: ask Claude "scan acme"' "$OUT"
verdict acme Red
run status acme
assert_contains "red says remove" "next: do not run it: sandbox rm acme" "$OUT"
run status ghost
assert_eq "unknown project fails" 1 "$CODE"
assert_contains "unknown project explained" "sandbox new ghost" "$OUT"

finish
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `tests/run.sh tests/test_sandbox_status.sh`
Expected: FAIL lines (bin/sandbox does not exist: "No such file or directory").

- [ ] **Step 4: Write `bin/sandbox` skeleton with `status`**

```bash
#!/usr/bin/env bash
# sandbox: the single entry point for the job test sandbox (README.md; spec
# docs/superpowers/specs/2026-10-01-sandbox-ux-design.md). Only this script talks to Docker.
# Must run on macOS /bin/bash 3.2: no associative arrays, no mapfile, no ${x,,}.
set -euo pipefail

IMAGE="job-sandbox:base"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${SANDBOX_WORK_DIR:-$ROOT/work}"
PROJECT=/home/dev/project
HARDEN=(--user dev --cap-drop=ALL --security-opt no-new-privileges)

die() { echo "sandbox: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: sandbox <command> [args]

  build                            build the base image job-sandbox:base
  new <firm> <https-git-url|zip>   create volume jt-<firm> and fill it
  scan <firm> <read command>       read the code: no network, read-only
  up <firm> [--accept-question]    start code-server (needs a Green scan)
  exec <firm> <command>            run a command in the running container
  apply <firm> < change.patch      apply a patch inside the container
  export <firm>                    write bundle + zip to work/<firm>/out/
  rm <firm> [--yes]                delete the container and the volume
  status [firm] [--short]          every project, its state and the next step
EOF
}

need_docker() {
  command -v docker >/dev/null 2>&1 || die "docker not found; install OrbStack (README Phase 1 / Task 1)"
}
need_image() {
  docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image $IMAGE is missing; run: sandbox build"
}
check_firm() {
  [[ "${1:-}" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] ||
    die "firm must be lowercase letters, digits or dashes (got '${1:-}')"
}
volume_exists() { docker volume inspect "jt-$1" >/dev/null 2>&1; }
need_volume() { volume_exists "$1" || die "no project jt-$1; create it: sandbox new $1 <url|zip>"; }

# Prints running | stopped | missing.
container_state() {
  local r
  r="$(docker container inspect --format '{{.State.Running}}' "jt-$1" 2>/dev/null)" || { echo missing; return 0; }
  if [ "$r" = true ]; then echo running; else echo stopped; fi
}
need_running() { [ "$(container_state "$1")" = running ] || die "jt-$1 is not running; run: sandbox up $1"; }

# Prints Green | Question | Red | none, from the 'Verdict: X' line in work/<firm>/scan.md.
scan_verdict() {
  local f="$WORK/$1/scan.md" v=""
  if [ -f "$f" ]; then
    v="$(sed -n -E 's/^Verdict: (Green|Question|Red)[[:space:]]*$/\1/p' "$f" | head -n 1)"
  fi
  echo "${v:-none}"
}

next_step() {  # firm verdict state
  case "$2/$3" in
    */running) echo "work at http://127.0.0.1:8443; when done: sandbox export $1" ;;
    none/*) echo "ask Claude \"scan $1\"" ;;
    Red/*) echo "do not run it: sandbox rm $1" ;;
    Question/*) echo "read work/$1/scan.md, then: sandbox up $1 --accept-question" ;;
    Green/*) echo "sandbox up $1" ;;
  esac
}

list_firms() { docker volume ls --format '{{.Name}}' | sed -n 's/^jt-//p'; }

# One line for the Claude statusline: the running project if any, else the first one.
short_status() {
  local f pick="" n=0
  for f in $1; do
    n=$((n + 1))
    if [ -z "$pick" ] || [ "$(container_state "$f")" = running ]; then pick="$f"; fi
  done
  local more=""
  [ "$n" -gt 1 ] && more=" (+$((n - 1)))"
  echo "🛡 sandbox: $pick · $(scan_verdict "$pick") · $(container_state "$pick")$more"
}

cmd_status() {
  local a only="" short=""
  for a in "$@"; do case "$a" in --short) short=1 ;; *) only="$a" ;; esac; done
  if [ -n "$only" ]; then check_firm "$only"; fi
  if ! command -v docker >/dev/null 2>&1; then
    if [ -n "$short" ]; then echo "🛡 sandbox: docker not installed"; return 0; fi
    need_docker
  fi
  local firms
  if [ -n "$only" ]; then need_volume "$only"; firms="$only"; else firms="$(list_firms)"; fi
  if [ -z "$firms" ]; then
    if [ -n "$short" ]; then echo "🛡 sandbox: none"; else echo "No projects. Start one: sandbox new <firm> <url|zip>"; fi
    return 0
  fi
  if [ -n "$short" ]; then short_status "$firms"; return 0; fi
  local f v s
  for f in $firms; do
    v="$(scan_verdict "$f")"; s="$(container_state "$f")"
    printf '%s  scan=%s  container=%s  next: %s\n' "$f" "$v" "$s" "$(next_step "$f" "$v" "$s")"
  done
}

cmd="${1:-}"
if [ $# -gt 0 ]; then shift; fi
case "$cmd" in
  build|new|scan|up|exec|apply|export|rm|status) "cmd_$cmd" "$@" ;;
  ""|-h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
```

Run: `chmod +x bin/sandbox`

- [ ] **Step 5: Run the tests to verify they pass**

Run: `tests/run.sh tests/test_sandbox_status.sh`
Expected: only `ok` lines, then `ALL PASS`.

- [ ] **Step 6: Commit**

```bash
git add bin/sandbox tests/
git commit -m "Add sandbox command skeleton with status, plus shell test harness"
```

### Task 2: `build`, `new` and `scan`

**Files:**
- Modify: `bin/sandbox` (add functions above the dispatch `case`)
- Create: `tests/test_sandbox_new_scan.sh`

**Interfaces:**
- Consumes: from Phase 1 / Task 1 `die`, `need_docker`, `need_image`, `check_firm`,
  `volume_exists`, `need_volume`, `HARDEN`, `IMAGE`, `PROJECT`, `WORK`, `ROOT`; test helpers.
- Produces: `cmd_build`, `cmd_new firm src`, `cmd_scan firm cmd...`, `check_scan_command cmd...`.

- [ ] **Step 1: Write the failing tests**

`tests/test_sandbox_new_scan.sh`:

```bash
. "$(dirname "$0")/sandbox_helpers.sh"

setup
run build
assert_contains "build uses boilerplate/" "build -t job-sandbox:base $ROOT/boilerplate" "$(log)"

setup
run new acme https://github.com/acme/test.git
assert_eq "new from git: exit 0" 0 "$CODE"
assert_contains "volume created" "volume create jt-acme" "$(log)"
assert_contains "hardened clone without submodules" \
  "run --rm --user dev --cap-drop=ALL --security-opt no-new-privileges -v jt-acme:/home/dev/project job-sandbox:base git clone --no-recurse-submodules https://github.com/acme/test.git /home/dev/project" "$(log)"
assert_contains "next step named" "scan acme" "$OUT"
assert_eq "work dir created" yes "$([ -d "$SANDBOX_WORK_DIR/acme" ] && echo yes)"

setup
printf 'PK-fake-zip' > "$T/acme.zip"
run new acme "$T/acme.zip"
assert_eq "new from zip: exit 0" 0 "$CODE"
assert_contains "zip streamed via stdin" "run --rm -i --user dev" "$(log)"
assert_eq "zip bytes reached the container" "PK-fake-zip" "$(cat "$FAKE_DOCKER_STDIN")"

setup
run new acme git@github.com:acme/test.git
assert_eq "ssh url refused" 1 "$CODE"
assert_contains "ssh refusal explained" "https://" "$OUT"
assert_eq "nothing created for ssh url" "" "$(log | grep 'volume create')"

setup
run new acme "$T/missing.zip"
assert_eq "missing zip refused" 1 "$CODE"

setup
export FAKE_DOCKER_VOLUMES="jt-acme"
run new acme https://github.com/acme/test.git
assert_eq "existing project not overwritten" 1 "$CODE"
assert_contains "existing project explained" "sandbox rm acme" "$OUT"

setup
export FAKE_DOCKER_IMAGES=""
run new acme https://github.com/acme/test.git
assert_eq "missing image refused" 1 "$CODE"
assert_contains "missing image explained" "sandbox build" "$OUT"

setup
export FAKE_DOCKER_EXIT=1
run new acme https://github.com/acme/test.git
assert_eq "failed clone fails" 1 "$CODE"
assert_contains "failed clone removes the volume" "volume rm jt-acme" "$(log)"

setup
export FAKE_DOCKER_VOLUMES="jt-acme"
run scan acme grep -rn postinstall .
assert_eq "scan grep: exit 0" 0 "$CODE"
assert_contains "scan is offline, read-only, hardened" \
  "run --rm --network none --read-only --user dev --cap-drop=ALL --security-opt no-new-privileges -v jt-acme:/src:ro -w /src job-sandbox:base grep -rn postinstall ." "$(log)"
run scan acme git log -p
assert_contains "scan git neutralises repo config" \
  "job-sandbox:base git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c diff.external= -c core.pager=cat log --no-ext-diff --no-textconv -p" "$(log)"

clear_log
for bad in "npm ls" "node x.js" "sh -c id" "git config -l" "find . -exec cat {} ;" "find . -delete"; do
  set -f; run scan acme $bad; set +f
  assert_eq "scan refuses: $bad" 1 "$CODE"
done
run scan acme awk 'BEGIN{system("id")}'
assert_eq "scan refuses awk system()" 1 "$CODE"
assert_eq "refused scans never reach docker run" "" "$(log | grep '^run ')"
run scan ghost ls
assert_eq "scan of unknown project fails" 1 "$CODE"

finish
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `tests/run.sh tests/test_sandbox_new_scan.sh`
Expected: FAIL lines ("cmd_build: command not found" and similar).

- [ ] **Step 3: Implement `build`, `new`, `scan`**

Add to `bin/sandbox` above the dispatch `case`:

```bash
cmd_build() { need_docker; docker build -t "$IMAGE" "$ROOT/boilerplate"; }

cmd_new() {
  local firm="${1:-}" src="${2:-}"
  check_firm "$firm"
  [ -n "$src" ] || die "usage: sandbox new <firm> <https-git-url|zip>"
  case "$src" in
    https://*) ;;
    *.zip) [ -f "$src" ] || die "zip not found: $src" ;;
    *) die "source must be an https:// git URL or a .zip file (ssh URLs need keys the container must not have)" ;;
  esac
  need_docker; need_image
  if volume_exists "$firm"; then die "jt-$firm already exists; remove it first: sandbox rm $firm"; fi
  docker volume create "jt-$firm" >/dev/null
  local failed=0
  if [[ "$src" == https://* ]]; then
    # A private repo asks for a read-only token here; only a terminal can answer that.
    local tty=""
    if [ -t 0 ]; then tty="-it"; fi
    docker run --rm $tty "${HARDEN[@]}" -v "jt-$firm:$PROJECT" "$IMAGE" \
      git clone --no-recurse-submodules "$src" "$PROJECT" || failed=1
  else
    # Streamed through stdin so the Mac never unpacks it.
    docker run --rm -i "${HARDEN[@]}" -v "jt-$firm:$PROJECT" "$IMAGE" \
      sh -c "cat > /tmp/t.zip && unzip -q /tmp/t.zip -d $PROJECT" < "$src" || failed=1
  fi
  if [ "$failed" -ne 0 ]; then
    docker volume rm "jt-$firm" >/dev/null
    die "could not fill jt-$firm; the volume was removed"
  fi
  mkdir -p "$WORK/$firm"
  echo "Created jt-$firm. Next: ask Claude \"scan $firm\" (writes work/$firm/scan.md)."
}

# README Phase 3 / Task 2: read commands only, and no way to start a program from the repo.
check_scan_command() {
  case "$1" in
    ls|find|cat|head|tail|grep|awk|wc|file) ;;
    git) case "${2:-}" in log|show) ;; *) die "scan allows only 'git log' and 'git show'" ;; esac ;;
    *) die "scan allows only: ls find cat head tail grep awk wc file, git log, git show (got '$1')" ;;
  esac
  local a
  for a in "$@"; do
    case "$a" in
      -exec|-execdir|-ok|-okdir|-delete) die "scan: find $a is not allowed" ;;
      *system*|*getline*|*'|'*) if [ "$1" = awk ]; then die "scan: awk may not run commands"; fi ;;
    esac
  done
}

cmd_scan() {
  local firm="${1:-}"
  check_firm "$firm"; shift
  [ $# -gt 0 ] || die "usage: sandbox scan <firm> <read command>"
  check_scan_command "$@"
  need_docker; need_image; need_volume "$firm"
  if [ "$1" = git ]; then
    # The repo's own git config could name programs (diff.external, textconv, fsmonitor, hooks).
    local sub="$2"; shift 2
    set -- git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c diff.external= -c core.pager=cat \
      "$sub" --no-ext-diff --no-textconv "$@"
  fi
  docker run --rm --network none --read-only "${HARDEN[@]}" \
    -v "jt-$firm:/src:ro" -w /src "$IMAGE" "$@"
}
```

- [ ] **Step 4: Run all tests**

Run: `tests/run.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add bin/sandbox tests/test_sandbox_new_scan.sh
git commit -m "Add sandbox build, new and scan"
```

### Task 3: `up` (with the scan gate), `exec`, `apply`

**Files:**
- Modify: `bin/sandbox`
- Create: `tests/test_sandbox_up.sh`

**Interfaces:**
- Consumes: Phase 1 / Task 1 helpers (`scan_verdict`, `container_state`, `need_running`).
- Produces: `cmd_up firm [--accept-question]`, `cmd_exec firm cmd...`, `cmd_apply firm`
  (patch on stdin). Password file: `work/<firm>/password`, mode 600.

- [ ] **Step 1: Write the failing tests**

`tests/test_sandbox_up.sh`:

```bash
. "$(dirname "$0")/sandbox_helpers.sh"
setup
export FAKE_DOCKER_VOLUMES="jt-acme"

run up acme
assert_eq "no scan: refused" 1 "$CODE"
assert_contains "no scan: says scan first" 'scan acme' "$OUT"
verdict acme Red
run up acme
assert_eq "Red: refused" 1 "$CODE"
assert_contains "Red: says remove" "sandbox rm acme" "$OUT"
printf 'Verdict: Green but odd\n' > "$SANDBOX_WORK_DIR/acme/scan.md"
run up acme
assert_eq "malformed verdict: refused" 1 "$CODE"
verdict acme Question
run up acme
assert_eq "Question without flag: refused" 1 "$CODE"
assert_contains "Question: flag named" "--accept-question" "$OUT"
assert_eq "refusals never start a container" "" "$(log | grep -E '^(run|start) ')"
run up acme --accept-question
assert_eq "Question with flag: starts" 0 "$CODE"

setup
export FAKE_DOCKER_VOLUMES="jt-acme"
verdict acme Green
run up acme
assert_eq "Green: starts" 0 "$CODE"
assert_contains "hardened work container on localhost ports" \
  "run -d --name jt-acme --hostname jt-acme --user dev --cap-drop=ALL --security-opt no-new-privileges --pids-limit 1024 --memory 6g --cpus 4 -p 127.0.0.1:8443:8443 -p 127.0.0.1:5173:5173 -e PASSWORD=" "$(log)"
assert_contains "code-server command" "code-server --bind-addr 0.0.0.0:8443 --disable-telemetry /home/dev/project" "$(log)"
pw="$SANDBOX_WORK_DIR/acme/password"
assert_eq "password file is private" 600 "$(stat -f %Lp "$pw")"
assert_contains "password printed" "Password: $(cat "$pw")" "$OUT"

export FAKE_DOCKER_STOPPED="jt-acme"
clear_log
run up acme
assert_contains "stopped container is restarted" "start jt-acme" "$(log)"
assert_not_contains "stopped container is not recreated" "run -d" "$(log)"

export FAKE_DOCKER_STOPPED="" FAKE_DOCKER_RUNNING="jt-acme"
run up acme
assert_contains "running container reported" "already running" "$OUT"

export FAKE_DOCKER_RUNNING=""
run exec acme npm ci
assert_eq "exec needs a running container" 1 "$CODE"
assert_contains "exec says how" "sandbox up acme" "$OUT"
export FAKE_DOCKER_RUNNING="jt-acme"
clear_log
run exec acme npm ci
assert_contains "exec as dev in the project" "exec --user dev -w /home/dev/project jt-acme npm ci" "$(log)"

clear_log
OUT="$(printf 'diff --git a/x b/x\n' | "$ROOT/bin/sandbox" apply acme 2>&1)"; CODE=$?
assert_eq "apply: exit 0" 0 "$CODE"
assert_contains "apply runs git apply on stdin" "exec -i --user dev -w /home/dev/project jt-acme git apply --whitespace=nowarn -" "$(log)"
assert_contains "apply shows the result" "git diff --stat" "$(log)"
assert_eq "patch reached the container" "diff --git a/x b/x" "$(cat "$FAKE_DOCKER_STDIN")"

finish
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `tests/run.sh tests/test_sandbox_up.sh`
Expected: FAIL lines ("cmd_up: command not found").

- [ ] **Step 3: Implement**

```bash
cmd_up() {
  local firm="${1:-}" accept="${2:-}"
  check_firm "$firm"
  need_docker; need_image; need_volume "$firm"
  case "$(scan_verdict "$firm")" in
    Green) ;;
    Question) [ "$accept" = --accept-question ] ||
      die "scan verdict is Question; read work/$firm/scan.md, then: sandbox up $firm --accept-question" ;;
    Red) die "scan verdict is Red; do not run it. Remove it: sandbox rm $firm" ;;
    *) die "no 'Verdict:' line in work/$firm/scan.md; ask Claude \"scan $firm\" first" ;;
  esac
  local pwfile="$WORK/$firm/password"
  case "$(container_state "$firm")" in
    running) echo "jt-$firm is already running." ;;
    stopped) docker start "jt-$firm" >/dev/null ;;
    missing)
      mkdir -p "$WORK/$firm"
      ( umask 077; openssl rand -hex 12 > "$pwfile" )
      docker run -d --name "jt-$firm" --hostname "jt-$firm" "${HARDEN[@]}" \
        --pids-limit 1024 --memory 6g --cpus 4 \
        -p 127.0.0.1:8443:8443 -p 127.0.0.1:5173:5173 \
        -e PASSWORD="$(cat "$pwfile")" \
        -v "jt-$firm:$PROJECT" "$IMAGE" \
        code-server --bind-addr 0.0.0.0:8443 --disable-telemetry "$PROJECT" >/dev/null ;;
  esac
  local pw="(missing: work/$firm/password)"
  if [ -f "$pwfile" ]; then pw="$(cat "$pwfile")"; fi
  echo "Open http://127.0.0.1:8443 in the sandbox browser profile. Password: $pw"
}

cmd_exec() {
  local firm="${1:-}"
  check_firm "$firm"; shift
  [ $# -gt 0 ] || die "usage: sandbox exec <firm> <command>"
  need_docker; need_running "$firm"
  local tty=""
  if [ -t 0 ] && [ -t 1 ]; then tty="-it"; fi
  docker exec $tty --user dev -w "$PROJECT" "jt-$firm" "$@"
}

# The patch is written by Claude or you on the Mac; the test code itself never leaves the volume.
cmd_apply() {
  local firm="${1:-}"
  check_firm "$firm"
  if [ -t 0 ]; then die "pipe a patch in: sandbox apply $firm < change.patch"; fi
  need_docker; need_running "$firm"
  docker exec -i --user dev -w "$PROJECT" "jt-$firm" git apply --whitespace=nowarn -
  docker exec --user dev -w "$PROJECT" "jt-$firm" git diff --stat
}
```

- [ ] **Step 4: Run all tests**

Run: `tests/run.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add bin/sandbox tests/test_sandbox_up.sh
git commit -m "Add sandbox up with scan gate, exec and apply"
```

### Task 4: `export` and `rm`

**Files:**
- Modify: `bin/sandbox`
- Create: `tests/test_sandbox_export_rm.sh`

**Interfaces:**
- Consumes: Phase 1 / Task 1 helpers.
- Produces: `cmd_export firm` → `work/<firm>/out/<firm>.bundle` and `.zip`;
  `cmd_rm firm [--yes]`.

- [ ] **Step 1: Write the failing tests**

`tests/test_sandbox_export_rm.sh`:

```bash
. "$(dirname "$0")/sandbox_helpers.sh"
setup
export FAKE_DOCKER_VOLUMES="jt-acme"

run export acme
assert_eq "export: exit 0" 0 "$CODE"
assert_contains "bundle made offline, read-only" \
  "run --rm --network none --user dev --cap-drop=ALL --security-opt no-new-privileges -v jt-acme:/src:ro -w /src job-sandbox:base git bundle create - --all" "$(log)"
assert_contains "zip made from HEAD" "git archive --format=zip HEAD" "$(log)"
assert_eq "bundle written" FAKE-OUTPUT "$(cat "$SANDBOX_WORK_DIR/acme/out/acme.bundle")"
assert_eq "zip written" FAKE-OUTPUT "$(cat "$SANDBOX_WORK_DIR/acme/out/acme.zip")"

export FAKE_DOCKER_STOPPED="jt-acme"
run rm acme
assert_eq "rm without a terminal needs --yes" 1 "$CODE"
assert_contains "rm says how to confirm" "sandbox rm acme --yes" "$OUT"
assert_not_contains "nothing removed yet" "volume rm" "$(log)"

run rm acme --yes
assert_eq "rm --yes: exit 0" 0 "$CODE"
assert_contains "container removed" "rm -f jt-acme" "$(log)"
assert_contains "volume removed" "volume rm jt-acme" "$(log)"
assert_contains "work dir kept" "work/acme/ is kept" "$OUT"

export FAKE_DOCKER_VOLUMES="" FAKE_DOCKER_STOPPED=""
run rm acme --yes
assert_eq "rm of nothing fails" 1 "$CODE"
assert_contains "rm of nothing explained" "nothing to remove" "$OUT"

finish
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `tests/run.sh tests/test_sandbox_export_rm.sh`
Expected: FAIL lines ("cmd_export: command not found").

- [ ] **Step 3: Implement**

```bash
cmd_export() {
  local firm="${1:-}"
  check_firm "$firm"
  need_docker; need_image; need_volume "$firm"
  local out="$WORK/$firm/out"
  mkdir -p "$out"
  docker run --rm --network none "${HARDEN[@]}" -v "jt-$firm:/src:ro" -w /src "$IMAGE" \
    git bundle create - --all > "$out/$firm.bundle"
  docker run --rm --network none "${HARDEN[@]}" -v "jt-$firm:/src:ro" -w /src "$IMAGE" \
    git archive --format=zip HEAD > "$out/$firm.zip"
  echo "Wrote $out/$firm.bundle and $out/$firm.zip. Send or push them yourself (README Phase 5 / Task 2)."
}

cmd_rm() {
  local firm="${1:-}" yes="${2:-}"
  check_firm "$firm"
  need_docker
  local state
  state="$(container_state "$firm")"
  if [ "$state" = missing ] && ! volume_exists "$firm"; then die "nothing to remove for $firm"; fi
  if [ "$yes" != --yes ]; then
    [ -t 0 ] || die "confirm with: sandbox rm $firm --yes"
    local answer
    read -r -p "Delete container and volume jt-$firm? Work not exported is lost. Type '$firm': " answer
    [ "$answer" = "$firm" ] || die "not confirmed; nothing removed"
  fi
  if [ "$state" != missing ]; then docker rm -f "jt-$firm" >/dev/null; fi
  if volume_exists "$firm"; then docker volume rm "jt-$firm" >/dev/null; fi
  echo "Removed jt-$firm. work/$firm/ is kept; delete it yourself when you no longer need it."
}
```

- [ ] **Step 4: Run all tests**

Run: `tests/run.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add bin/sandbox tests/test_sandbox_export_rm.sh
git commit -m "Add sandbox export and rm"
```

---

## Phase 2 — Claude guardrails (written and tested, not yet active)

### Task 1: Guard hook — Bash commands

**Files:**
- Create: `.claude/hooks/guard.sh`
- Create: `tests/test_guard.sh`

**Interfaces:**
- Contract (Claude Code docs, hooks): JSON on stdin with `tool_name`, `tool_input`, `cwd`,
  `scratchpad_dir`; env `CLAUDE_PROJECT_DIR`. Exit 2 blocks and shows stderr to Claude. Exit 0
  with `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask",
  "permissionDecisionReason":"…"}}` forces a permission prompt.
- Produces: `guard.sh` functions `deny`, `ask`, `inside path dir`, `path_ok path read|write`,
  `check_segment words`, `check_bash`, `check_file_tool` (the last added in Phase 2 / Task 2).

- [ ] **Step 1: Write the failing tests**

`tests/test_guard.sh`:

```bash
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib.sh"
GUARD="$ROOT/.claude/hooks/guard.sh"
R=/fake/repo H=/fake/home S=/fake/scratch

hook() {  # tool, tool_input JSON -> OUT, CODE
  OUT="$(jq -n --arg t "$1" --argjson i "$2" --arg c "$R" --arg s "$S" \
    '{tool_name:$t, tool_input:$i, cwd:$c, scratchpad_dir:$s}' |
    CLAUDE_PROJECT_DIR="$R" HOME="$H" /bin/bash "$GUARD" 2>&1)"
  CODE=$?
}
bash_cmd() { hook Bash "$(jq -n --arg c "$1" '{command:$c}')"; }
allows() { bash_cmd "$1"; assert_eq "allows: $1" 0 "$CODE"; assert_not_contains "no prompt: $1" '"ask"' "$OUT"; }
denies() { bash_cmd "$1"; assert_eq "denies: $1" 2 "$CODE"; }

allows 'bin/sandbox status'
allows './bin/sandbox scan acme grep -rn postinstall .'
allows '/fake/repo/bin/sandbox status --short'
allows 'bin/sandbox status 2>&1 | head -5'
allows 'tests/run.sh'
allows 'git status'
allows 'git commit -m "Add guard"'
allows 'ls -la'
allows 'cat README.md'
allows 'cd /fake/repo && git status'
allows 'bin/sandbox apply acme < /fake/scratch/change.patch'

denies 'docker ps'
denies 'docker run -v /Users:/x job-sandbox:base true'
denies 'bin/sandbox scan acme cat /var/run/docker.sock'
denies 'npm i'
denies 'npx vite'
denies 'node x.js'
denies 'curl https://example.com'
denies 'git push'
denies 'git push origin main'
denies 'git clone https://github.com/acme/test.git'
denies 'git -c core.pager=sh status'
denies 'cat ~/.ssh/id_rsa'
denies 'cat /etc/passwd'
denies 'cd /tmp'
denies 'cd .. && ls'
denies 'echo $(whoami)'
denies 'echo `whoami`'
denies 'bash -c ls'
denies 'PATH=/tmp bin/sandbox status'
denies 'find . -exec rm {} \;'
denies 'ls; npm i'
denies 'bin/sandbox status && npm i'
denies 'ls | sh'
denies 'echo x > /Users/someone/.zshrc'

bash_cmd 'docker ps'
assert_contains "docker denial names the alternative" "bin/sandbox" "$OUT"
bash_cmd 'npm ci'
assert_contains "npm denial names exec" "bin/sandbox exec" "$OUT"

bash_cmd 'bin/sandbox rm acme --yes'
assert_eq "rm from Claude: exit 0" 0 "$CODE"
assert_contains "rm from Claude: forces a prompt" '"permissionDecision": "ask"' "$OUT"

hook WebFetch '{"url":"https://example.com"}'
assert_eq "other tools pass through" 0 "$CODE"

finish
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `tests/run.sh tests/test_guard.sh`
Expected: FAIL lines (guard.sh does not exist).

- [ ] **Step 3: Implement the Bash part of the guard**

`.claude/hooks/guard.sh`:

```bash
#!/usr/bin/env bash
# PreToolUse guard for this repo (spec: Guardrails / Layer 1). Claude may reach test code
# only through bin/sandbox. Exit 2 blocks the call; stderr is shown to Claude as the reason.
# This is an allowlist: anything not recognised is denied. macOS /bin/bash 3.2 compatible.
set -uo pipefail

input="$(cat)"
field() { jq -r "$1 // empty" <<<"$input"; }
tool="$(field .tool_name)"
root="${CLAUDE_PROJECT_DIR:-$(field .cwd)}"
scratch="$(field .scratchpad_dir)"

deny() { echo "Blocked by the job-test-sandbox guard: $*" >&2; exit 2; }
ask() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
  exit 0
}

inside() { case "$1" in "$2"|"$2"/*) return 0 ;; esac; return 1; }

# path_ok <path> <read|write>: inside the repo, the session scratchpad or Claude's own
# project memory; reads may also use the rest of ~/.claude (skills, tool results).
path_ok() {
  local p="$1"
  case "$p" in *..*) return 1 ;; esac
  case "$p" in
    /*) ;;
    "~"*) p="$HOME${p#\~}" ;;
    *) p="$root/$p" ;;
  esac
  [ "$p" = /dev/null ] && return 0
  inside "$p" "$root" && return 0
  [ -n "$scratch" ] && inside "$p" "$scratch" && return 0
  inside "$p" "$HOME/.claude/projects" && return 0
  [ "$2" = read ] && inside "$p" "$HOME/.claude" && return 0
  return 1
}

READ_ONLY=" ls cat head tail grep wc sort uniq jq echo printf pwd date diff file mkdir test true "
GIT_OK=" status diff log show add commit branch rev-parse ls-files restore stash grep blame "

check_segment() {
  local word t w1 w2
  set -f; set -- $1; set +f
  [ $# -eq 0 ] && return 0
  for word in "$@"; do
    t="${word//\"/}"; t="${t//\'/}"
    t="${t#[0-9]}"; t="${t#>>}"; t="${t#>}"; t="${t#<}"
    case "$t" in *=/*|*="~"*) t="${t#*=}" ;; esac
    case "$t" in
      /*|"~"*|*..*) path_ok "$t" write || deny "path outside this repo: $t" ;;
    esac
  done
  w1="${1//\"/}"; w1="${w1//\'/}"; w2="${2:-}"
  case "$w1" in
    bin/sandbox|./bin/sandbox|"$root/bin/sandbox")
      [ "$w2" = rm ] && WANTS_ASK=1
      return 0 ;;
    tests/run.sh|./tests/run.sh|"$root/tests/run.sh") return 0 ;;
    git)
      [ "$w2" = push ] && deny "git push is yours to run, not Claude's."
      case "$GIT_OK" in *" $w2 "*) return 0 ;; esac
      deny "git $w2 is not allowed here (no push, clone, fetch, config or -c). Allowed:$GIT_OK" ;;
    cd) return 0 ;;  # the target was checked as a path above; relative targets stay in the repo
    find)
      for word in "$@"; do
        case "$word" in -exec|-execdir|-ok|-okdir|-delete) deny "find $word is not allowed." ;; esac
      done
      return 0 ;;
    docker) deny "use bin/sandbox instead of docker (for example: bin/sandbox status)." ;;
    npm|npx|node|pnpm|yarn|bun)
      deny "$w1 never runs on the Mac here; inside the container use: bin/sandbox exec <firm> $w1 ..." ;;
    curl|wget) deny "$w1 is not allowed in this repo." ;;
  esac
  case "$READ_ONLY" in *" $w1 "*) return 0 ;; esac
  deny "'$w1' is not on this repo's allowlist. Use bin/sandbox <command> (README: The sandbox command)."
}

check_bash() {
  local cmd seg
  cmd="$(field .tool_input.command)"
  case "$cmd" in
    *docker.sock*|*--privileged*|*"-v /Users"*) deny "docker.sock, --privileged and -v /Users are never allowed." ;;
    *'$('*|*'`'*|*'<('*|*'>('*) deny "command substitution is not allowed here; run the parts as separate commands." ;;
  esac
  WANTS_ASK=""
  # One segment per simple command. Quotes are not parsed, so ';' or '|' inside quotes
  # splits too: that can only cause a false denial, never a false allow.
  while IFS= read -r seg; do
    check_segment "$seg"
  done < <(printf '%s\n' "$cmd" | awk '{ gsub(/[0-9]*>&[0-9-]*/, ""); gsub(/&&|\|\||[;|&]/, "\n"); print }')
  [ -n "$WANTS_ASK" ] && ask "sandbox rm deletes the project volume and any work not exported. Confirm?"
  exit 0
}

case "$tool" in
  Bash) check_bash ;;
esac
exit 0
```

Run: `chmod +x .claude/hooks/guard.sh`

- [ ] **Step 4: Run all tests**

Run: `tests/run.sh`
Expected: `ALL PASS`. If a single `allows`/`denies` line fails, fix the guard, not the test:
the lists come from the spec's Layer 1.

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/guard.sh tests/test_guard.sh
git commit -m "Add Claude guard hook for Bash commands (not active yet)"
```

### Task 2: Guard hook — file tools

**Files:**
- Modify: `.claude/hooks/guard.sh`
- Create: `tests/test_guard_files.sh`

**Interfaces:**
- Consumes: Phase 2 / Task 1 `field`, `deny`, `path_ok`, `root`.
- Produces: `check_file_tool`, wired for `Read|Edit|Write|NotebookEdit|Grep|Glob`.

- [ ] **Step 1: Write the failing tests**

`tests/test_guard_files.sh`:

```bash
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib.sh"
GUARD="$ROOT/.claude/hooks/guard.sh"
R=/fake/repo H=/fake/home S=/fake/scratch
hook() {
  OUT="$(jq -n --arg t "$1" --argjson i "$2" --arg c "$R" --arg s "$S" \
    '{tool_name:$t, tool_input:$i, cwd:$c, scratchpad_dir:$s}' |
    CLAUDE_PROJECT_DIR="$R" HOME="$H" /bin/bash "$GUARD" 2>&1)"
  CODE=$?
}
f() { hook "$1" "$(jq -n --arg k "$2" --arg p "$3" '{($k): $p}')"; assert_eq "$1 $3" "$4" "$CODE"; }

f Read file_path README.md 0
f Read file_path /fake/repo/bin/sandbox 0
f Read file_path /fake/home/.claude/plugins/x/SKILL.md 0
f Read file_path /fake/scratch/notes.txt 0
f Read file_path /etc/passwd 2
f Read file_path /fake/home/.ssh/id_rsa 2
f Read file_path /fake/repo/../other/x 2
f Write file_path /fake/repo/docs/x.md 0
f Write file_path /fake/scratch/change.patch 0
f Write file_path /fake/home/.claude/projects/p/memory/x.md 0
f Write file_path /fake/home/.claude/settings.json 2
f Write file_path /fake/repo/.claude/settings.json 2
f Write file_path /fake/repo/.claude/settings.local.json 2
f Edit file_path /fake/repo/.claude/hooks/guard.sh 2
f Edit file_path .claude/hooks/guard.sh 2
f NotebookEdit notebook_path /tmp/n.ipynb 2
f Grep path /fake/repo/bin 0
f Grep path /Users/someone 2
f Glob path /fake/repo 0
hook Grep '{"pattern":"x"}'
assert_eq "Grep without path stays in cwd" 0 "$CODE"
hook Write '{"file_path":"/fake/repo/.claude/settings.json"}'
assert_contains "settings denial explained" "edited by you" "$OUT"

finish
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `tests/run.sh tests/test_guard_files.sh`
Expected: FAIL lines (file tools pass through with exit 0).

- [ ] **Step 3: Implement**

Add above the final `case` in `guard.sh`:

```bash
check_file_tool() {
  local p mode=read
  p="$(field '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path')"
  case "$tool" in Edit|Write|NotebookEdit) mode=write ;; esac
  [ -z "$p" ] && exit 0
  path_ok "$p" "$mode" ||
    deny "$tool outside this repo is not allowed ($p). Test code is read only through: bin/sandbox scan <firm> <read command>"
  if [ "$mode" = write ]; then
    case "$p" in /*) ;; *) p="$root/$p" ;; esac
    case "$p" in
      "$root"/.claude/settings*.json|"$root"/.claude/hooks/*)
        deny "the guard and its settings are edited by you, not by Claude ($p)." ;;
    esac
  fi
  exit 0
}
```

Replace the final `case`:

```bash
case "$tool" in
  Bash) check_bash ;;
  Read|Edit|Write|NotebookEdit|Grep|Glob) check_file_tool ;;
esac
exit 0
```

- [ ] **Step 4: Run all tests**

Run: `tests/run.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/guard.sh tests/test_guard_files.sh
git commit -m "Extend guard hook to file tools (not active yet)"
```

### Task 3: Claude statusline script

**Files:**
- Create: `.claude/statusline.sh`
- Create: `tests/test_statusline.sh`

**Interfaces:**
- Contract (Claude Code docs, statusline): session JSON on stdin with
  `workspace.project_dir`; first stdout line is shown.
- Consumes: `bin/sandbox status --short` (Phase 1 / Task 1).

- [ ] **Step 1: Write the failing test**

`tests/test_statusline.sh`:

```bash
. "$(dirname "$0")/sandbox_helpers.sh"
setup
SL="$ROOT/.claude/statusline.sh"
json="$(jq -n --arg d "$ROOT" '{workspace: {project_dir: $d}}')"

OUT="$(printf '%s' "$json" | /bin/bash "$SL")"
assert_eq "no projects" "🛡 sandbox: none" "$OUT"
export FAKE_DOCKER_VOLUMES="jt-acme" FAKE_DOCKER_RUNNING="jt-acme"
verdict acme Green
OUT="$(printf '%s' "$json" | /bin/bash "$SL")"
assert_eq "running project" "🛡 sandbox: acme · Green · running" "$OUT"
OUT="$(printf '%s' "$json" | PATH=/usr/bin:/bin /bin/bash "$SL")"
assert_eq "no docker" "🛡 sandbox: docker not installed" "$OUT"
OUT="$(printf '{}' | /bin/bash "$SL")"
assert_contains "no project_dir falls back to the script location" "🛡 sandbox:" "$OUT"

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `tests/run.sh tests/test_statusline.sh`
Expected: FAIL lines (script missing).

- [ ] **Step 3: Implement**

`.claude/statusline.sh`:

```bash
#!/usr/bin/env bash
# Claude Code status line for this repo (spec: Statusline): the current sandbox project.
dir="$(jq -r '.workspace.project_dir // .cwd // empty' 2>/dev/null)"
[ -n "$dir" ] || dir="$(cd "$(dirname "$0")/.." && pwd)"
"$dir/bin/sandbox" status --short 2>/dev/null || echo "🛡 sandbox: status unavailable"
```

Run: `chmod +x .claude/statusline.sh`

- [ ] **Step 4: Run all tests**

Run: `tests/run.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add .claude/statusline.sh tests/test_statusline.sh
git commit -m "Add Claude statusline script for the sandbox"
```

---

## Phase 3 — Mac shell guard

### Task 1: `shell/sandbox.zsh` — docker guard, `sandbox` function, warnings, prompt marker

**Files:**
- Create: `shell/sandbox.zsh`
- Create: `tests/test_zsh.sh`

**Interfaces:**
- Produces (zsh): `docker`, `git`, `unzip`, `sandbox` functions; `_jts_prompt` precmd hook;
  `JTS_ROOT`, `_JTS_MARK`. Bypass: `command docker …`.

- [ ] **Step 1: Write the failing tests**

`tests/test_zsh.sh`:

```bash
. "$(dirname "$0")/sandbox_helpers.sh"
setup
Z="$ROOT/shell/sandbox.zsh"
zr() {  # run zsh code with the guard loaded; sets OUT, CODE
  OUT="$(cd "${2:-/tmp}" && zsh -f -c "source '$Z'; $1" 2>&1)"; CODE=$?
}

zr 'docker run -v /Users:/x job-sandbox:base true'
assert_eq "bind mount refused" 1 "$CODE"
assert_contains "refusal names the sandbox command" "bin/sandbox" "$OUT"
zr 'docker run --mount type=bind,src=/Users,dst=/x job-sandbox:base true'
assert_eq "--mount bind refused" 1 "$CODE"
zr 'docker run --privileged job-sandbox:base true'
assert_eq "--privileged refused" 1 "$CODE"
zr 'docker run -v /var/run/docker.sock:/s job-sandbox:base true'
assert_eq "docker.sock refused" 1 "$CODE"
zr 'docker run -p 8443:8443 --name jt-acme job-sandbox:base true'
assert_eq "port on all interfaces refused" 1 "$CODE"
assert_eq "refused calls never reach docker" "" "$(log)"

zr 'docker run -p 127.0.0.1:8443:8443 -v jt-acme:/home/dev/project --name jt-acme job-sandbox:base true'
assert_eq "localhost port and named volume pass" 0 "$CODE"
zr 'docker run --rm -v /Users/me/db:/data postgres'
assert_eq "non-sandbox docker is untouched" 0 "$CODE"
assert_contains "non-sandbox call reached docker" "run --rm -v /Users/me/db:/data postgres" "$(log)"
zr 'command docker run --privileged jt-x'
assert_eq "command docker bypasses on purpose" 0 "$CODE"

zr 'git clone --bogus-flag' "$ROOT"
assert_contains "git clone in the repo warns" "never get cloned on the Mac" "$OUT"
zr 'git clone --bogus-flag' /tmp
assert_not_contains "git clone elsewhere is quiet" "never get cloned" "$OUT"
zr 'unzip /nonexistent.zip' "$ROOT"
assert_contains "unzip in the repo warns" "sandbox new" "$OUT"

zr 'sandbox status --short'
assert_eq "sandbox function runs bin/sandbox" "🛡 sandbox: none" "$OUT"

zr 'PROMPT="> "; _jts_prompt; print -r -- "$PROMPT"' "$ROOT"
assert_contains "prompt marked inside the repo" "🛡 MAC · job-test-sandbox" "$OUT"
zr 'PROMPT="> "; cd "'"$ROOT"'"; _jts_prompt; _jts_prompt; cd /tmp; _jts_prompt; print -r -- "$PROMPT"'
assert_eq "marker added once and removed outside" "> " "$OUT"

finish
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `tests/run.sh tests/test_zsh.sh`
Expected: FAIL lines (sandbox.zsh missing).

- [ ] **Step 3: Implement**

`shell/sandbox.zsh`:

```zsh
# Job test sandbox: Mac shell guard (spec: Guardrails / Layer 3).
# Load it from ~/.zshrc AFTER oh-my-zsh:
#   source ~/github/agenticDraft/job-test-sandbox/shell/sandbox.zsh
# It guards against mistakes, not attacks: `command docker ...` bypasses it on purpose.

typeset -g JTS_ROOT="${${(%):-%x}:A:h:h}"
typeset -g _JTS_MARK='%F{yellow}🛡 MAC · job-test-sandbox%f '

sandbox() { "$JTS_ROOT/bin/sandbox" "$@"; }

# Only calls that name sandbox objects are checked; everything else goes straight to docker.
docker() {
  if [[ "$*" != *jt-* && "$*" != *job-sandbox* ]]; then
    command docker "$@"; return
  fi
  local a prev="" reason=""
  for a in "$@"; do
    case "$a" in
      *docker.sock*) reason="mounting the Docker socket hands the container control of Docker" ;;
      --privileged) reason="--privileged removes the container's isolation" ;;
      *type=bind*) reason="bind mounts expose Mac files" ;;
      --volume=/*|--volume=\~*) reason="bind mount of a Mac path ($a)" ;;
      --publish=*) [[ "$a" == --publish=127.0.0.1:* ]] || reason="port ${a#--publish=} is not bound to 127.0.0.1" ;;
    esac
    case "$prev" in
      -v|--volume) [[ "$a" == /* || "$a" == \~* || "$a" == .* ]] && reason="bind mount of a Mac path ($a)" ;;
      -p|--publish) [[ "$a" == 127.0.0.1:* ]] || reason="port $a is not bound to 127.0.0.1" ;;
    esac
    prev="$a"
  done
  if [[ -n "$reason" ]]; then
    print -u2 "🛡 blocked: $reason."
    print -u2 "   Use the sandbox command instead: $JTS_ROOT/bin/sandbox help"
    print -u2 "   (Deliberate override: command docker ...)"
    return 1
  fi
  command docker "$@"
}

_jts_in_repo() { [[ "$PWD" == "$JTS_ROOT" || "$PWD" == "$JTS_ROOT"/* ]]; }

git() {
  if [[ "$1" == clone ]] && _jts_in_repo; then
    print -u2 "🛡 warning: test repos never get cloned on the Mac. Use: sandbox new <firm> <url>"
  fi
  command git "$@"
}

unzip() {
  if _jts_in_repo; then
    print -u2 "🛡 warning: test zips are never unpacked on the Mac. Use: sandbox new <firm> <file.zip>"
  fi
  command unzip "$@"
}

_jts_prompt() {
  if _jts_in_repo; then
    [[ "$PROMPT" == "$_JTS_MARK"* ]] || PROMPT="$_JTS_MARK$PROMPT"
  else
    PROMPT="${PROMPT#$_JTS_MARK}"
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _jts_prompt
```

- [ ] **Step 4: Run all tests**

Run: `tests/run.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add shell/sandbox.zsh tests/test_zsh.sh
git commit -m "Add Mac zsh guard and prompt marker for the sandbox"
```

- [ ] **Step 6: Ask Zoran to load it**

Claude does not edit `~/.zshrc`. Tell Zoran to add this line **after**
`source $ZSH/oh-my-zsh.sh` and open a new terminal:

```zsh
source ~/github/agenticDraft/job-test-sandbox/shell/sandbox.zsh
```

---

## Phase 4 — Base image

### Task 1: Dockerfile and container-side files

**Files:**
- Create: `boilerplate/Dockerfile`, `boilerplate/sandbox-prompt.sh`,
  `boilerplate/code-server-settings.json`

**Interfaces:**
- Consumes: image name `job-sandbox:base`, user `dev`, project path `/home/dev/project`
  (Phase 1 / Task 1 constants), built by `sandbox build` (Phase 1 / Task 2).
- Produces: hostname-based prompt `🧪 SANDBOX <firm>`; `NPM_CONFIG_IGNORE_SCRIPTS=true`;
  empty system `credential.helper`; orange code-server bars.

Docker is not installed yet, so this task has no runnable test; Phase 6 / Task 2 checks the
built image.

- [ ] **Step 1: Write the prompt snippet**

`boilerplate/sandbox-prompt.sh`:

```bash
# Sourced from ~dev/.bashrc in the sandbox image (spec: Guardrails / Layer 2):
# this terminal must never be mistaken for the Mac.
_sbx_firm="${HOSTNAME#jt-}"
_sbx_prompt() {
  local warn=""
  if [ -n "$(git config --get credential.helper 2>/dev/null)" ]; then
    warn='\[\e[41;97m\] credential helper set: remove it \[\e[0m\] '
  fi
  PS1="${warn}\[\e[48;5;208;30m\] 🧪 SANDBOX ${_sbx_firm} \[\e[0m\] \w \$ "
}
PROMPT_COMMAND=_sbx_prompt
```

- [ ] **Step 2: Write the code-server settings**

`boilerplate/code-server-settings.json`:

```json
{
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "#d9480f",
    "titleBar.activeForeground": "#ffffff",
    "titleBar.inactiveBackground": "#a33a0c",
    "statusBar.background": "#d9480f",
    "statusBar.foreground": "#ffffff"
  },
  "window.title": "🧪 SANDBOX — ${rootName}",
  "task.allowAutomaticTasks": "off",
  "security.workspace.trust.enabled": true,
  "telemetry.telemetryLevel": "off"
}
```

- [ ] **Step 3: Write the Dockerfile**

`boilerplate/Dockerfile`:

```dockerfile
# Base image for job tests (README Phase 1 / Task 3; spec Guardrails / Layer 2).
# Built once with `sandbox build`. Each project gets its own volume and container;
# this image is never modified per project.
FROM node:24-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends git unzip ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# Standalone code-server under /usr/local (https://coder.com/docs/code-server/install).
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/usr/local

# npm install scripts never run; one package at a time: npm rebuild <pkg> --ignore-scripts=false
ENV NPM_CONFIG_IGNORE_SCRIPTS=true
# No credential is ever stored in the container.
RUN git config --system credential.helper ""

COPY sandbox-prompt.sh /etc/sandbox-prompt.sh
RUN useradd --create-home --shell /bin/bash dev \
 && mkdir -p /home/dev/project /home/dev/.local/share/code-server/User \
 && echo '. /etc/sandbox-prompt.sh' >> /home/dev/.bashrc \
 && chown -R dev:dev /home/dev
COPY --chown=dev:dev code-server-settings.json /home/dev/.local/share/code-server/User/settings.json

USER dev
WORKDIR /home/dev/project
```

`/home/dev/project` is created empty and owned by `dev`, so a new named volume mounted there
starts owned by `dev` and `git clone` as `dev` can write into it.

- [ ] **Step 4: Static check**

Run: `grep -c 'job-sandbox\|ignore-scripts\|credential.helper' boilerplate/Dockerfile boilerplate/sandbox-prompt.sh`
Expected: non-zero counts; no build possible until Phase 6.

- [ ] **Step 5: Commit**

```bash
git add boilerplate/
git commit -m "Add sandbox base image with prompt, npm and code-server defaults"
```

---

## Phase 5 — Docs and activation

### Task 1: README and CLAUDE.md

**Files:**
- Modify: `README.md`, `CLAUDE.md`

- [ ] **Step 1: Update README.md**

- Replace every `bin/sandbox-new|scan|up|export|rm acme` with `sandbox new|scan|up|export|rm acme`.
- Phase 1 / Task 3: `sandbox build` instead of `cd boilerplate && docker build …`.
- New Phase 1 / Task 5 "Load the Mac shell guard": the `source …/shell/sandbox.zsh` line, after
  oh-my-zsh, and what it does (spec Layer 3).
- After Rules, add sections "Who does what" (legend 💬 🖥 🧪 🌐 and the "Where am I?" check),
  "Daily flow" (the 12 steps from the spec), "The sandbox command" (one line per
  subcommand, including `build` and `rm --yes`), "Working with Claude" (accepted limits),
  "Guardrails" (three layers, scope, `command docker` escape, statusline).
- Phase 3 / Task 4: `scan.md` must contain a line exactly `Verdict: Green`, `Verdict: Question`
  or `Verdict: Red`; `sandbox up` reads it.
- Phase 4 / Task 2: `npm ci` alone (scripts are off by default); exception
  `npm rebuild esbuild --ignore-scripts=false`.
- Phase 7: point to the plan's Phase 6 checks in addition to the five existing ones.

- [ ] **Step 2: Update CLAUDE.md**

Status: `bin/sandbox`, guard, statusline, zsh guard and Dockerfile written and tested against a
fake docker; not run against real Docker. Rules: read test code only with
`bin/sandbox scan <firm> <read command>`; change it only with patches through
`bin/sandbox apply <firm>`; run things only with `bin/sandbox exec <firm>`; scan results need
the `Verdict: X` line; the guard hook in `.claude/hooks/guard.sh` is edited by Zoran only;
commits use `git commit -m "…"` (no `$(…)` heredocs, the guard denies them).

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "Document the sandbox command, guardrails and daily flow"
```

### Task 2: Update the published runbook

**Files:**
- Modify: `.claude/artifacts/job-test-sandbox.html` (gitignored; not committed)

- [ ] **Step 1: Edit the artifact source**

Add `sandbox build` to "The sandbox command", the `Verdict: X` line format to Phase 3 / Task 4,
the `npm rebuild <pkg> --ignore-scripts=false` exception, `rm --yes` and the hook prompt, the
zsh `source` line, `task.allowAutomaticTasks: off`. Update the status box: "built and tested
against a fake docker; not yet run on real Docker".

- [ ] **Step 2: Publish to the same URL**

Artifact tool: `file_path` = that file, `url` = `https://claude.ai/artifact/P6jREw8p4i9BE8mQD3yLNa`.

### Task 3: Activate the guard and statusline

**Files:**
- Create: `.claude/settings.json`

This is the last code change, because from here on Claude in this repo can only use the
allowlist (including `tests/run.sh`). The file is written with the Write tool; Claude Code asks
Zoran to approve that write.

- [ ] **Step 1: Write the settings**

`.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "/bin/bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/guard.sh\"" }
        ]
      }
    ]
  },
  "permissions": {
    "allow": ["Bash(bin/sandbox status)", "Bash(bin/sandbox status *)", "Bash(bin/sandbox scan *)", "Bash(tests/run.sh)", "Bash(tests/run.sh *)"],
    "deny": ["Monitor", "Bash(docker *)", "Bash(npm *)", "Bash(npx *)", "Bash(node *)", "Bash(curl *)", "Bash(wget *)", "Bash(git push)", "Bash(git push *)"]
  },
  "sandbox": {
    "excludedCommands": ["bin/sandbox *", "./bin/sandbox *"]
  },
  "statusLine": {
    "type": "command",
    "command": "/bin/bash \"${CLAUDE_PROJECT_DIR:-.}/.claude/statusline.sh\""
  }
}
```

Hook and statusline run via /bin/bash (no exec bit needed); bin/sandbox is excluded from the Bash sandbox because docker cannot run inside it (Claude Code docs: sandboxing, 'docker commands fail').

- [ ] **Step 2: Commit**

```bash
git add .claude/settings.json
git commit -m "Activate the sandbox guard hook and statusline"
```

- [ ] **Step 3: Restart Claude Code in this repo** so the hook and statusline load.

---

## Phase 6 — Verification on this Mac

### Task 1: Install and build (Zoran)

- [ ] **Step 1:** Install OrbStack (README Phase 1 / Task 1); turn off "Expose ports to LAN".
- [ ] **Step 2:** In a new terminal: `sandbox build`. Expected: image `job-sandbox:base` built.
- [ ] **Step 3:** Create a harmless test project from a repo you own, e.g.
  `sandbox new acme https://github.com/agenticDraft/job-test-sandbox.git`, and put
  `Verdict: Green` into `work/acme/scan.md`.

### Task 2: Run every check

Every line must give the expected result.

- [ ] **Step 1: Unit tests** — `tests/run.sh` → `ALL PASS`.
- [ ] **Step 2: Claude hook** — from Claude in this repo, each of these must fail with
  "Blocked by the job-test-sandbox guard": `cat /etc/hosts`; a Write to `bin/x`; a Monitor tool
  call. Also: `bin/sandbox up acme --accept-question` asks for confirmation; `bin/sandbox status`
  runs and reaches Docker; the statusline shows `🛡 sandbox: …`.
- [ ] **Step 3: Gate** — with `Verdict: Red`, then `Verdict: Question`, then no `scan.md`:
  `sandbox up acme` refuses each time; with `Verdict: Green` it starts and prints the password.
- [ ] **Step 4: Container** —
  `sandbox exec acme npm config get ignore-scripts` → `true`;
  `sandbox exec acme git config --system credential.helper` → empty line;
  code-server at `http://127.0.0.1:8443`: terminal prompt starts with `🧪 SANDBOX acme`,
  status bar orange, title bar orange (if the browser shows no custom title bar, record that);
  `npm rebuild esbuild --ignore-scripts=false` runs the package's script (any project with
  esbuild).
- [ ] **Step 5: Apply** — write a one-line patch, `sandbox apply acme < change.patch`;
  `sandbox exec acme git diff` shows it; `find ~ -name README.md -newer change.patch -path '*acme*'`
  finds nothing on the Mac.
- [ ] **Step 6: Mac zsh** — `docker run -v /Users:/x job-sandbox:base true` refused;
  `docker run --rm hello-world` runs; `docker <TAB>` still completes; prompt shows
  `🛡 MAC · job-test-sandbox` only inside the repo.
- [ ] **Step 7: README Phase 7** — run its five checks against `jt-acme`.
- [ ] **Step 8: Clean up** — `sandbox rm acme` (type `acme`), then `sandbox status` → no projects.

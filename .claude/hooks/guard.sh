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

READ_ONLY=" ls cat head tail grep wc echo printf pwd date diff test true mkdir "
GIT_OK=" status diff log show add commit branch rev-parse ls-files "
GIT_OPTS=" -m -n -p -s -v -1 -5 -10 -20 --stat --oneline --name-only --name-status --cached --staged --short --porcelain "

check_segment() {
  local word t w1 w2 seg
  seg="${1//\"/}"; seg="${seg//\'/}"
  set -f; set -- $seg; set +f
  [ $# -eq 0 ] && return 0
  for word in "$@"; do
    t="${word#[0-9]}"; t="${t#>}"; t="${t#<}"
    case "$t" in
      -*/*) deny "options with a path attached are not allowed: $t" ;;
      /*|*..*) path_ok "$t" write || deny "path outside this repo: $t" ;;
    esac
  done
  w1="$1"; w2="${2:-}"
  case "$w1" in
    bin/sandbox|./bin/sandbox|"$root/bin/sandbox")
      [ "$w2" = rm ] && WANTS_ASK=1
      return 0 ;;
    tests/run.sh|./tests/run.sh|"$root/tests/run.sh")
      shift
      for word in "$@"; do
        case "$word" in tests/test_*.sh) ;; *) deny "tests/run.sh takes only tests/test_*.sh files (got $word)." ;; esac
      done
      return 0 ;;
    git)
      case "$GIT_OK" in *" $w2 "*) ;; *) deny "git $w2 is not allowed here. Allowed:$GIT_OK" ;; esac
      shift 2
      for word in "$@"; do
        case "$word" in
          -*) case "$GIT_OPTS" in *" $word "*) ;; *) deny "git option $word is not on the allowlist:$GIT_OPTS" ;; esac
              [ "$word" = -m ] && [ "$w2" != commit ] && deny "-m is allowed only for git commit." ;;
        esac
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
  local cmd seg rest
  cmd="$(field .tool_input.command)"
  [ "$(field .cwd)" = "$root" ] || deny "run commands from the repo root ($root); cd is not allowed."
  case "$cmd" in
    *$'\n'*) deny "one command line at a time." ;;
    *docker.sock*|*--privileged*|*"-v /Users"*) deny "docker.sock, --privileged and -v /Users are never allowed." ;;
  esac
  # The only redirections allowed: fd duplication (2>&1) and output to /dev/null.
  rest="$(printf '%s\n' "$cmd" | awk '{ gsub(/(^| )[12]?>&[12]( |$)/, " "); gsub(/(^| )[12]?> ?\/dev\/null( |$)/, " "); print }')"
  # Every other character must be plain: no expansion, glob, brace, subshell, ~, = or redirection.
  if printf '%s' "$rest" | LC_ALL=C grep -q "[^A-Za-z0-9 _./:,@+\"'|;&<-]"; then
    deny "only plain words are allowed here: no \$ \` \\ * ? [ ] { } ( ) ~ = ! # > (except 2>&1 and >/dev/null)."
  fi
  WANTS_ASK=""
  # One segment per simple command. Quotes are not parsed, so ';' or '|' inside quotes
  # splits too: that can only cause a false denial, never a false allow.
  while IFS= read -r seg; do
    check_segment "$seg"
  done < <(printf '%s\n' "$rest" | awk '{ gsub(/&&|\|\||[;|&]/, "\n"); print }')
  [ -n "$WANTS_ASK" ] && ask "sandbox rm deletes the project volume and any work not exported. Confirm?"
  exit 0
}

check_file_tool() {
  local p mode=read
  case "$tool" in Edit|Write|NotebookEdit) mode=write ;; esac
  local key
  case "$tool" in
    NotebookEdit) key=notebook_path ;;
    Grep|Glob) key=path ;;
    *) key=file_path ;;
  esac
  p="$(field ".tool_input.$key")"
  if [ -z "$p" ]; then
    case "$tool" in Grep|Glob) exit 0 ;; esac
    deny "$tool needs a $key."
  fi
  path_ok "$p" "$mode" ||
    deny "$tool outside this repo is not allowed ($p). Test code is read only through: bin/sandbox scan <firm> <read command>"
  if [ "$mode" = write ]; then
    case "$p" in /*) ;; "~"*) p="$HOME${p#\~}" ;; *) p="$root/$p" ;; esac
    if inside "$p" "$root"; then
      case "$p" in
        "$root"/work/*|"$root"/docs/*|"$root"/README.md|"$root"/CLAUDE.md) ;;
        *) deny "while the guard is active Claude writes only work/, docs/, README.md and CLAUDE.md in this repo; scripts, tests, .claude/ and .git/ are edited by you ($p)." ;;
      esac
    fi
  fi
  exit 0
}

case "$tool" in
  Bash) check_bash ;;
  Read|Edit|Write|NotebookEdit|Grep|Glob) check_file_tool ;;
esac
exit 0

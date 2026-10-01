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

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
  # Only container creation can mount or publish; stop at the image so the
  # command that runs inside the container is never inspected.
  if [[ "$1" == run || "$1" == create ]]; then
    for a in "${@:2}"; do
      # The image is the first job-sandbox* word that is not the value of an option.
      case "$prev" in
        --name|--env|-e|--label|-l|--network|--net|--user|-u|--workdir|-w|--hostname|-h|--entrypoint|--memory|-m|--cpus|--pids-limit|--cap-drop|--cap-add|--security-opt|--tmpfs|--mount) ;;
        *) [[ "$a" == job-sandbox* ]] && break ;;
      esac
      case "$a" in
        *docker.sock*) reason="mounting the Docker socket hands the container control of Docker" ;;
        --privileged) reason="--privileged removes the container's isolation" ;;
        *type=bind*) reason="bind mounts expose Mac files" ;;
        -v/*|-v\~*|-v.*|--volume=/*|--volume=\~*|--volume=.*) reason="bind mount of a Mac path ($a)" ;;
        --publish=*) [[ "$a" == --publish=127.0.0.1:* ]] || reason="port ${a#--publish=} is not bound to 127.0.0.1" ;;
      esac
      case "$prev" in
        -v|--volume) [[ "$a" == /* || "$a" == \~* || "$a" == .* ]] && reason="bind mount of a Mac path ($a)" ;;
        -p|--publish) [[ "$a" == 127.0.0.1:* ]] || reason="port $a is not bound to 127.0.0.1" ;;
      esac
      prev="$a"
    done
  fi
  if [[ -n "$reason" ]]; then
    print -u2 "🛡 blocked: $reason."
    print -u2 "   Use the sandbox command instead: $JTS_ROOT/bin/sandbox help"
    print -u2 "   (Deliberate override: command docker ...)"
    return 1
  fi
  command docker "$@"
}

# Switch the Claude guard hook of this repo on and off (docs/reference.md: Guardrails, "Scope, on and
# off"). Works from any directory; touches only this repo's .claude/settings.json.
_jts_claude() { print -r -- "${JTS_CLAUDE_DIR:-$JTS_ROOT/.claude}"; }
guard-status() {
  local d; d="$(_jts_claude)"
  if [[ -f "$d/settings.json" ]]; then print "🛡 guard is on"
  elif [[ -f "$d/settings.json.off" ]]; then print "⚠️  guard is off (guard-on to switch it back)"
  else print -u2 "🛡 no $d/settings.json or settings.json.off"; return 1; fi
}
guard-on() {
  local d; d="$(_jts_claude)"
  if [[ -f "$d/settings.json" ]]; then print "🛡 guard is already on"; return 0; fi
  [[ -f "$d/settings.json.off" ]] || { guard-status; return 1; }
  command mv "$d/settings.json.off" "$d/settings.json" && guard-status
}
guard-off() {
  local d; d="$(_jts_claude)"
  if [[ -f "$d/settings.json.off" ]]; then print "⚠️  guard is already off"; return 0; fi
  [[ -f "$d/settings.json" ]] || { guard-status; return 1; }
  command mv "$d/settings.json" "$d/settings.json.off" && guard-status &&
    print "   Only for maintenance. Never work on a test project like this. Back on: guard-on"
}

_jts_in_repo() { [[ "$PWD" == "$JTS_ROOT" || "$PWD" == "$JTS_ROOT"/* ]]; }

# Starting Claude Code in this repo switches the guard on first, so a forgotten guard-off
# never carries into a new session. It has to happen here, before Claude Code reads its
# settings. Deliberate override for maintenance: `command claude …` after guard-off.
claude() {
  if _jts_in_repo && [[ ! -f "$(_jts_claude)/settings.json" ]]; then
    guard-on || return
  fi
  command claude "$@"
}

# Inside this repo, test code never lands on the Mac: clone, unzip and opening an archive are
# blocked here. Deliberate override: `command git clone …`, `command unzip …`, `command open …`.
_jts_block() {
  print -u2 "🛡 blocked: $1 Use: sandbox new <firm> <https-url|zip>"
  print -u2 "   (Deliberate override: command $2 ...)"
  return 1
}

git() {
  if [[ "$1" == clone ]] && _jts_in_repo; then
    _jts_block "test repos never get cloned on the Mac." git; return
  fi
  command git "$@"
}

unzip() {
  if _jts_in_repo; then
    _jts_block "test zips are never unpacked on the Mac." unzip; return
  fi
  command unzip "$@"
}

open() {
  local a
  if _jts_in_repo; then
    for a in "$@"; do
      case "$a" in
        *.zip|*.tar|*.tgz|*.gz|*.7z|*.rar) _jts_block "archives are never opened on the Mac ($a)." open; return ;;
      esac
    done
  fi
  command open "$@"
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

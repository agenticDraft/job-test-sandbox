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

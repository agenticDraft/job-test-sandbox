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

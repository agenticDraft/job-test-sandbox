#!/bin/bash
# From Claude (CLAUDECODE set), commands that touch test code need the guard hook switched on.
. "$(dirname "$0")/sandbox_helpers.sh"
setup
export FAKE_DOCKER_VOLUMES="jt-acme" FAKE_DOCKER_RUNNING="jt-acme"
verdict acme Green
export CLAUDECODE=1

# Guard off: no settings file (it was renamed to settings.json.off).
for c in "new beta https://github.com/acme/test.git" "scan acme ls" "up acme" "exec acme ls" "apply acme $T/p.patch" "export acme"; do
  clear_log
  set -f; run $c; set +f
  assert_eq "guard off, from Claude: refuses $c" 1 "$CODE"
  assert_contains "guard off explained: $c" "guard is off" "$OUT"
  assert_eq "guard off: $c never reaches docker" "" "$(log)"
done
# Commands that do not run test code stay available.
run status
assert_eq "guard off: status still works" 0 "$CODE"
run stop acme
assert_eq "guard off: stop still works" 0 "$CODE"

# A settings file that does not register the guard does not count.
printf '{"statusLine": {}}\n' > "$SANDBOX_SETTINGS"
run scan acme ls
assert_eq "settings without the guard: refused" 1 "$CODE"

# Guard on.
printf '{"hooks": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "/bin/bash .claude/hooks/guard.sh"}]}]}}\n' > "$SANDBOX_SETTINGS"
run scan acme ls
assert_eq "guard on, from Claude: scan runs" 0 "$CODE"

# Your own terminal (no CLAUDECODE): never blocked by this check.
rm -f "$SANDBOX_SETTINGS"
unset CLAUDECODE
run scan acme ls
assert_eq "own terminal, guard off: scan runs" 0 "$CODE"

finish

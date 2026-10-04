#!/bin/bash
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
printf '# Scan\n\nVerdict: Red\nVerdict: Green\n' > "$SANDBOX_WORK_DIR/acme/scan.md"
run up acme
assert_eq "two Verdict lines: refused" 1 "$CODE"
printf '# Scan\n\nVerdict: Green\nVerdict: Red\n' > "$SANDBOX_WORK_DIR/acme/scan.md"
run up acme
assert_eq "two Verdict lines, Green first: refused" 1 "$CODE"
printf '# Scan\n\nVerdict: Green\nVerdict: maybe\n' > "$SANDBOX_WORK_DIR/acme/scan.md"
run up acme
assert_eq "a second malformed Verdict line: refused" 1 "$CODE"
printf '# Scan\n\n> Verdict: Green\n' > "$SANDBOX_WORK_DIR/acme/scan.md"
run up acme
assert_eq "quoted Verdict line is not a verdict" 1 "$CODE"
printf '# Scan\n\n> Verdict: Red\nVerdict: Green\n' > "$SANDBOX_WORK_DIR/acme/scan.md"
run up acme
assert_eq "quoted line does not count against the real one" 0 "$CODE"
clear_log
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

# Every up firewalls the container (README.md, Residual risks: Container → Mac services).
fw="run --rm --network container:jt-acme --user root --cap-drop=ALL --cap-add NET_ADMIN --security-opt no-new-privileges job-sandbox:base sh -c"
assert_contains "new container: firewalled" "$fw" "$(log)"
assert_contains "firewall loads both tables" "ip6tables-restore" "$(log)"
assert_not_contains "firewall helper mounts nothing" " -v " "$(log | grep -- '--network container:')"
assert_not_contains "firewall replaces, never appends" "--noflush" "$(log)"
assert_eq "firewall runs after the start" "run -d|run --" "$(log | grep -E '^run (-d|--rm --network)' | cut -c1-6 | paste -sd'|' -)"

export FAKE_DOCKER_FAIL_ON="--network container:"
clear_log
run up acme
assert_eq "firewall fails: exit 1" 1 "$CODE"
assert_contains "firewall fails: container stopped" "stop jt-acme" "$(log)"
assert_contains "firewall fails: says so" "could not firewall jt-acme" "$OUT"
assert_contains "firewall fails: names the fix" "sandbox build" "$OUT"
assert_not_contains "firewall fails: no password" "Password:" "$OUT"
export FAKE_DOCKER_FAIL_ON=""

export FAKE_DOCKER_EXIT=1
clear_log
run up acme
assert_eq "failed start: exit 1" 1 "$CODE"
assert_contains "failed start: half-made container removed" "rm -f jt-acme" "$(log)"
assert_contains "failed start: ports hint" "sandbox stop" "$OUT"
export FAKE_DOCKER_EXIT=0

export FAKE_DOCKER_STOPPED="jt-acme"
clear_log
run up acme
assert_contains "stopped container is restarted" "start jt-acme" "$(log)"
assert_not_contains "stopped container is not recreated" "run -d" "$(log)"
assert_contains "restarted container: firewalled" "$fw" "$(log)"

export FAKE_DOCKER_STOPPED="" FAKE_DOCKER_RUNNING="jt-acme"
clear_log
run up acme
assert_contains "running container reported" "already running" "$OUT"
assert_contains "running container: firewalled again" "$fw" "$(log)"

clear_log
run stop acme
assert_eq "stop running: exit 0" 0 "$CODE"
assert_contains "stop running: docker stop" "stop jt-acme" "$(log)"

export FAKE_DOCKER_RUNNING=""
clear_log
run stop acme
assert_eq "stop when not running: exit 0" 0 "$CODE"
assert_contains "stop when not running: says so" "not running" "$OUT"
assert_not_contains "stop when not running: no docker stop" "stop jt-acme" "$(log)"

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

# A patch file as argument: Claude's Bash sandbox catches `< file`, so this is Claude's form.
printf 'diff --git a/y b/y\n' > "$T/change.patch"
: > "$FAKE_DOCKER_STDIN"
clear_log
run apply acme "$T/change.patch"
assert_eq "apply with a file: exit 0" 0 "$CODE"
assert_contains "apply with a file runs git apply" "exec -i --user dev -w /home/dev/project jt-acme git apply --whitespace=nowarn -" "$(log)"
assert_eq "patch file reached the container" "diff --git a/y b/y" "$(cat "$FAKE_DOCKER_STDIN")"
run apply acme "$T/missing.patch"
assert_eq "apply with a missing file fails" 1 "$CODE"
assert_contains "missing patch file named" "missing.patch" "$OUT"

# Docker installed but not reachable (OrbStack stopped, or run inside Claude's Bash sandbox).
export FAKE_DOCKER_DOWN=1
run exec acme npm ci
assert_eq "unreachable docker: exec fails" 1 "$CODE"
assert_contains "unreachable docker named, not 'not running'" "cannot reach the Docker server" "$OUT"
assert_not_contains "no false 'not running'" "is not running" "$OUT"
run up acme
assert_contains "up names unreachable docker" "cannot reach the Docker server" "$OUT"
unset FAKE_DOCKER_DOWN

finish

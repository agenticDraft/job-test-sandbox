. "$(dirname "$0")/sandbox_helpers.sh"
setup

run
assert_eq "no args: exit 0" 0 "$CODE"
assert_contains "no args: usage lists status" "status [firm] [--short]" "$OUT"
assert_contains "no args: usage lists stop" "stop <firm>" "$OUT"
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

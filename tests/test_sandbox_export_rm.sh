#!/bin/bash
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

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
  "job-sandbox:base git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c diff.external= -c core.pager=cat -c gpg.program=/bin/false -c core.attributesFile=/dev/null log --no-ext-diff --no-textconv -p" "$(log)"

clear_log
for bad in "npm ls" "node x.js" "sh -c id" "git config -l" "find . -exec cat {} ;" "find . -delete" "git log -p --ext-diff" "git log -p --textconv" "git show --show-signature" "git log --format=%G?" "git log -c core.pager=sh" "find . -fprint /tmp/x" "awk -f x.awk ."; do
  set -f; run scan acme $bad; set +f
  assert_eq "scan refuses: $bad" 1 "$CODE"
done
run scan acme awk '{print}' x
assert_eq "scan refuses: awk" 1 "$CODE"
assert_eq "refused scans never reach docker run" "" "$(log | grep '^run ')"
run scan ghost ls
assert_eq "scan of unknown project fails" 1 "$CODE"

finish

. "$(dirname "$0")/sandbox_helpers.sh"
setup
Z="$ROOT/shell/sandbox.zsh"
zr() {  # run zsh code with the guard loaded; sets OUT, CODE
  OUT="$(cd "${2:-/tmp}" && zsh -f -c "source '$Z'; $1" 2>&1)"; CODE=$?
}

zr 'docker run -v /Users:/x job-sandbox:base true'
assert_eq "bind mount refused" 1 "$CODE"
assert_contains "refusal names the sandbox command" "bin/sandbox" "$OUT"
zr 'docker run --mount type=bind,src=/Users,dst=/x job-sandbox:base true'
assert_eq "--mount bind refused" 1 "$CODE"
zr 'docker run --privileged job-sandbox:base true'
assert_eq "--privileged refused" 1 "$CODE"
zr 'docker run -v /var/run/docker.sock:/s job-sandbox:base true'
assert_eq "docker.sock refused" 1 "$CODE"
zr 'docker run -p 8443:8443 --name jt-acme job-sandbox:base true'
assert_eq "port on all interfaces refused" 1 "$CODE"
assert_eq "refused calls never reach docker" "" "$(log)"

zr 'docker run -p 127.0.0.1:8443:8443 -v jt-acme:/home/dev/project --name jt-acme job-sandbox:base true'
assert_eq "localhost port and named volume pass" 0 "$CODE"
zr 'docker run --rm -v /Users/me/db:/data postgres'
assert_eq "non-sandbox docker is untouched" 0 "$CODE"
assert_contains "non-sandbox call reached docker" "run --rm -v /Users/me/db:/data postgres" "$(log)"
zr 'command docker run --privileged jt-x'
assert_eq "command docker bypasses on purpose" 0 "$CODE"

zr 'git clone --bogus-flag' "$ROOT"
assert_eq "git clone in the repo is blocked" 1 "$CODE"
assert_contains "git clone block explained" "never get cloned on the Mac" "$OUT"
assert_not_contains "blocked clone never ran git" "unknown option" "$OUT"
zr 'git clone --bogus-flag' /tmp
assert_not_contains "git clone elsewhere is untouched" "never get cloned" "$OUT"
zr 'command git clone --bogus-flag' "$ROOT"
assert_contains "command git clone bypasses on purpose" "unknown option" "$OUT"
zr 'unzip /nonexistent.zip' "$ROOT"
assert_eq "unzip in the repo is blocked" 1 "$CODE"
assert_contains "unzip block names sandbox new" "sandbox new" "$OUT"
zr 'open /nonexistent/acme.zip' "$ROOT"
assert_eq "open of a zip in the repo is blocked" 1 "$CODE"
assert_contains "open block explained" "archives are never opened" "$OUT"
zr 'git status --short >/dev/null' "$ROOT"
assert_eq "other git commands in the repo work" 0 "$CODE"

zr 'sandbox status --short'
assert_eq "sandbox function runs bin/sandbox" "🛡 sandbox: none" "$OUT"

zr 'PROMPT="> "; _jts_prompt; print -r -- "$PROMPT"' "$ROOT"
assert_contains "prompt marked inside the repo" "🛡 MAC · job-test-sandbox" "$OUT"
zr 'PROMPT="> "; cd "'"$ROOT"'"; _jts_prompt; _jts_prompt; cd /tmp; _jts_prompt; print -r -- "$PROMPT"'
assert_eq "marker added once and removed outside" "> " "$OUT"

zr 'docker exec jt-acme git log -p src/'
assert_eq "exec into a sandbox container is untouched" 0 "$CODE"
zr 'docker exec jt-acme cat /var/run/docker.sock'
assert_eq "commands inside the container are not inspected" 0 "$CODE"
zr 'docker run --rm job-sandbox:base ls -v /usr'
assert_eq "args after the image are not inspected" 0 "$CODE"
zr 'docker run -v/Users:/x job-sandbox:base true'
assert_eq "attached -v/ refused" 1 "$CODE"
zr 'docker run --volume=./a:/x job-sandbox:base true'
assert_eq "--volume=./ refused" 1 "$CODE"
zr 'docker run --publish=8443:8443 job-sandbox:base true'
assert_eq "--publish= without 127.0.0.1 refused" 1 "$CODE"

finish

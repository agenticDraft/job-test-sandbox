ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib.sh"
GUARD="$ROOT/.claude/hooks/guard.sh"
R=/fake/repo H=/fake/home S=/fake/scratch

hook() {  # tool, tool_input JSON -> OUT, CODE
  OUT="$(jq -n --arg t "$1" --argjson i "$2" --arg c "$R" --arg s "$S" \
    '{tool_name:$t, tool_input:$i, cwd:$c, scratchpad_dir:$s}' |
    CLAUDE_PROJECT_DIR="$R" HOME="$H" /bin/bash "$GUARD" 2>&1)"
  CODE=$?
}
bash_cmd() { hook Bash "$(jq -n --arg c "$1" '{command:$c}')"; }
allows() { bash_cmd "$1"; assert_eq "allows: $1" 0 "$CODE"; assert_not_contains "no prompt: $1" '"ask"' "$OUT"; }
denies() { bash_cmd "$1"; assert_eq "denies: $1" 2 "$CODE"; }

allows 'bin/sandbox status'
allows './bin/sandbox scan acme grep -rn postinstall .'
allows '/fake/repo/bin/sandbox status --short'
allows 'bin/sandbox status 2>&1 | head -5'
allows 'tests/run.sh'
allows 'git status'
allows 'git commit -m "Add guard"'
allows 'ls -la'
allows 'cat README.md'
allows 'cd /fake/repo && git status'
allows 'bin/sandbox apply acme < /fake/scratch/change.patch'

denies 'docker ps'
denies 'docker run -v /Users:/x job-sandbox:base true'
denies 'bin/sandbox scan acme cat /var/run/docker.sock'
denies 'npm i'
denies 'npx vite'
denies 'node x.js'
denies 'curl https://example.com'
denies 'git push'
denies 'git push origin main'
denies 'git clone https://github.com/acme/test.git'
denies 'git -c core.pager=sh status'
denies 'cat ~/.ssh/id_rsa'
denies 'cat /etc/passwd'
denies 'cd /tmp'
denies 'cd .. && ls'
denies 'echo $(whoami)'
denies 'echo `whoami`'
denies 'bash -c ls'
denies 'PATH=/tmp bin/sandbox status'
denies 'find . -exec rm {} \;'
denies 'ls; npm i'
denies 'bin/sandbox status && npm i'
denies 'ls | sh'
denies 'echo x > /Users/someone/.zshrc'

bash_cmd 'docker ps'
assert_contains "docker denial names the alternative" "bin/sandbox" "$OUT"
bash_cmd 'npm ci'
assert_contains "npm denial names exec" "bin/sandbox exec" "$OUT"

bash_cmd 'bin/sandbox rm acme --yes'
assert_eq "rm from Claude: exit 0" 0 "$CODE"
assert_contains "rm from Claude: forces a prompt" '"permissionDecision": "ask"' "$OUT"

hook WebFetch '{"url":"https://example.com"}'
assert_eq "other tools pass through" 0 "$CODE"

finish

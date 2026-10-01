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
denies 'cd /fake/repo && git status'
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

denies 'cat $HOME/.ssh/id_rsa'
denies 'cat \/etc/passwd'
denies 'echo x > bin/sandbox'
denies 'echo x >> tests/run.sh'
denies 'sort -o bin/sandbox README.md'
denies 'uniq README.md bin/sandbox'
denies 'find . -fprint bin/x'
denies 'git grep -Osh x'
denies 'git grep --open-files-in-pager=sh x'
denies 'git diff --output=bin/sandbox'
denies 'git log --ext-diff'
allows 'ls > /dev/null'
allows 'git status 2>/dev/null'
allows 'bin/sandbox scan acme grep -rn postinstall . 2>&1 | head -20'

denies 'echo x >&bin/sandbox'
denies 'echo x >& tests/run.sh'
denies 'git grep -nOsh x'
denies 'git diff --outp=bin/sandbox'
denies 'git log --ext'
denies 'cat {/etc,/x}/passwd'
denies 'cat =ls'
denies 'ls *(e:id:)'
denies 'tests/run.sh work/x.sh'
denies 'tests/run.sh README.md'
denies 'cd work && bin/sandbox status'
denies 'cd && cat .ssh/id_rsa'
denies 'grep -f/fake/home/x .'
denies 'git commit -F/fake/home/.ssh/id_rsa'
denies 'jq -n env'
denies 'find . -name x'
denies 'git restore --source=HEAD .claude/hooks/guard.sh'
denies 'git branch -D main'
denies 'git stash'
denies "$(printf 'ls\nnpm i')"
allows 'tests/run.sh tests/test_guard.sh'
allows 'git log --oneline -n 5'
allows 'git commit -m "Add x" -m "Claude-Session: https://claude.ai/code/session_01XT43ApAs9E6zJKP5Yenc7W"'
OUT="$(jq -n '{tool_name:"Bash", tool_input:{command:"bin/sandbox status"}, cwd:"/fake/repo/work", scratchpad_dir:"/fake/scratch"}' |
  CLAUDE_PROJECT_DIR=/fake/repo HOME=/fake/home /bin/bash "$GUARD" 2>&1)"; CODE=$?
assert_eq "commands only from the repo root" 2 "$CODE"

finish

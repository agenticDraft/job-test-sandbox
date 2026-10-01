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
assert_eq "known safe tool allowed: WebFetch" 0 "$CODE"
for t in Monitor mcp__ide__executeCode mcp__plugin_playwright_playwright__browser_run_code_unsafe \
  mcp__claude-in-chrome__javascript_tool KillShell BashOutput FooTool; do
  hook "$t" '{"command":"id"}'
  assert_eq "unknown tool denied: $t" 2 "$CODE"
done
hook FooTool '{}'
assert_contains "unknown tool denial names the tool" "tool FooTool is not allowed" "$OUT"
hook MultiEdit '{"file_path":"/fake/repo/bin/sandbox","edits":[]}'
assert_eq "MultiEdit on bin/sandbox denied" 2 "$CODE"
hook MultiEdit '{"file_path":"/fake/repo/work/x","edits":[]}'
assert_eq "MultiEdit on work/x allowed" 0 "$CODE"

bash_cmd 'bin/sandbox up acme --accept-question'
assert_eq "up --accept-question from Claude: exit 0" 0 "$CODE"
assert_contains "up --accept-question from Claude: forces a prompt" '"permissionDecision": "ask"' "$OUT"
bash_cmd 'bin/sandbox up acme'
assert_not_contains "plain up: no prompt" '"ask"' "$OUT"

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

denies 'git show "--output" bin/sandbox'
denies "git show '--output' bin/sandbox"
denies 'git diff "--outp" bin/sandbox'
denies 'git log "--ext-diff"'
denies 'git branch "-D" main'
denies 'git commit "--amend"'
denies 'git branch -m main other'
denies 'echo x >&2bin'
denies 'echo x 1>&2tests'
denies 'echo x >&1README.md'
denies 'echo x > /dev/nullx'
allows 'bin/sandbox status 2>&1'
allows 'git status 2>/dev/null | head -3'

# Paths after `exec|scan <firm>` belong to the container, not the Mac.
allows 'bin/sandbox exec acme ls /Users /mnt/mac'
allows 'bin/sandbox exec acme grep CapEff /proc/self/status'
allows 'bin/sandbox scan acme grep -f/src/patterns .'
denies 'bin/sandbox exec /etc ls'
denies 'bin/sandbox exec acme ls ; cat /etc/hosts'
denies 'bin/sandbox status /etc/hosts'
# apply reads the patch file on the Mac, so its path is still checked.
allows 'bin/sandbox apply acme /fake/scratch/change.patch'
denies 'bin/sandbox apply acme /etc/passwd'

finish

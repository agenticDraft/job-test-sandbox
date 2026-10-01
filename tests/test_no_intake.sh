#!/bin/bash
# The always-on intake hook: Claude never clones a repo or unpacks/opens a zip on the Mac,
# whether or not the main guard is switched on.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib.sh"
HOOK="$ROOT/.claude/hooks/no-intake.sh"

hook() {  # tool, tool_input JSON -> OUT, CODE
  OUT="$(jq -n --arg t "$1" --argjson i "$2" '{tool_name:$t, tool_input:$i, cwd:"/fake/repo"}' |
    /bin/bash "$HOOK" 2>&1)"
  CODE=$?
}
bash_cmd() { hook Bash "$(jq -n --arg c "$1" '{command:$c}')"; }
denies() { bash_cmd "$1"; assert_eq "denies: $1" 2 "$CODE"; }
allows() { bash_cmd "$1"; assert_eq "allows: $1" 0 "$CODE"; }

denies 'git clone https://github.com/acme/test.git'
denies 'git -C /tmp clone https://github.com/acme/test.git'
denies 'cd /tmp && git clone https://github.com/acme/test.git x'
denies 'gh repo clone acme/test'
denies 'unzip ~/Downloads/acme.zip'
denies 'ditto -x -k acme.zip out'
denies 'tar -xf acme.tar.gz'
denies 'bsdtar -xf acme.zip'
denies '7z x acme.zip'
denies 'open ~/Downloads/acme.zip'
denies 'ls ; unzip acme.zip'
bash_cmd 'git clone https://github.com/acme/test.git'
assert_contains "denial points to sandbox new" "bin/sandbox new" "$OUT"

allows 'bin/sandbox new acme https://github.com/acme/test.git'
allows 'bin/sandbox new acme /Users/me/Downloads/acme-test.zip'
allows 'git status'
allows 'git log --oneline -n 5'
allows 'ls work'
allows 'grep -rn tarball README.md'
denies 'bin/sandbox status ; unzip acme.zip'

# A commit message that only mentions the words is not intake.
allows 'git commit -m "Mac intake blocks: clone and unzip" -m "tar and open too"'
denies 'git commit -m x ; unzip acme.zip'
denies 'git commit -m x && git clone https://github.com/acme/test.git'
denies 'git commit -m "$(unzip acme.zip)"'
denies 'git commit -m "`unzip acme.zip`"'
denies 'git commit -F <(unzip -p acme.zip)'

hook Read '{"file_path":"/fake/repo/README.md"}'
assert_eq "other tools pass through" 0 "$CODE"

finish

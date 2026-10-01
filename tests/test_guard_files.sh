ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib.sh"
GUARD="$ROOT/.claude/hooks/guard.sh"
R=/fake/repo H=/fake/home S=/fake/scratch
hook() {
  OUT="$(jq -n --arg t "$1" --argjson i "$2" --arg c "$R" --arg s "$S" \
    '{tool_name:$t, tool_input:$i, cwd:$c, scratchpad_dir:$s}' |
    CLAUDE_PROJECT_DIR="$R" HOME="$H" /bin/bash "$GUARD" 2>&1)"
  CODE=$?
}
f() { hook "$1" "$(jq -n --arg k "$2" --arg p "$3" '{($k): $p}')"; assert_eq "$1 $3" "$4" "$CODE"; }

f Read file_path README.md 0
f Read file_path /fake/repo/bin/sandbox 0
f Read file_path /fake/home/.claude/plugins/x/SKILL.md 0
f Read file_path /fake/scratch/notes.txt 0
f Read file_path /etc/passwd 2
f Read file_path /fake/home/.ssh/id_rsa 2
f Read file_path /fake/repo/../other/x 2
f Write file_path /fake/repo/docs/x.md 0
f Write file_path /fake/scratch/change.patch 0
f Write file_path /fake/home/.claude/projects/p/memory/x.md 0
f Write file_path /fake/home/.claude/settings.json 2
f Write file_path /fake/repo/.claude/settings.json 2
f Write file_path /fake/repo/.claude/settings.local.json 2
f Edit file_path /fake/repo/.claude/hooks/guard.sh 2
f Edit file_path .claude/hooks/guard.sh 2
f NotebookEdit notebook_path /tmp/n.ipynb 2
f Grep path /fake/repo/bin 0
f Grep path /Users/someone 2
f Glob path /fake/repo 0
hook Grep '{"pattern":"x"}'
assert_eq "Grep without path stays in cwd" 0 "$CODE"
hook Write '{"file_path":"/fake/repo/.claude/settings.json"}'
assert_contains "settings denial explained" "edited by you" "$OUT"
f Write file_path /fake/repo/bin/sandbox 2
f Edit file_path tests/run.sh 2
f Write file_path /fake/repo/.git/hooks/pre-commit 2
f Write file_path /fake/repo/.claude/statusline.sh 2
f Write file_path /fake/repo/shell/sandbox.zsh 2
f Write file_path /fake/repo/.gitattributes 2
f Write file_path /fake/repo/work/acme/scan.md 0
f Edit file_path README.md 0
f Edit file_path /fake/repo/CLAUDE.md 0

finish

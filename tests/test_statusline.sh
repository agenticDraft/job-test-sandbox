. "$(dirname "$0")/sandbox_helpers.sh"
setup
SL="$ROOT/.claude/statusline.sh"
json="$(jq -n --arg d "$ROOT" '{workspace: {project_dir: $d}}')"

OUT="$(printf '%s' "$json" | /bin/bash "$SL")"
assert_eq "no projects" "🛡 sandbox: none" "$OUT"
export FAKE_DOCKER_VOLUMES="jt-acme" FAKE_DOCKER_RUNNING="jt-acme"
verdict acme Green
OUT="$(printf '%s' "$json" | /bin/bash "$SL")"
assert_eq "running project" "🛡 sandbox: acme · Green · running" "$OUT"
OUT="$(printf '%s' "$json" | PATH=/usr/bin:/bin /bin/bash "$SL")"
assert_eq "no docker" "🛡 sandbox: docker not installed" "$OUT"
OUT="$(printf '{}' | /bin/bash "$SL")"
assert_contains "no project_dir falls back to the script location" "🛡 sandbox:" "$OUT"

finish

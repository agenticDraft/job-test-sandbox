#!/usr/bin/env bash
# Claude Code status line for this repo (spec: Statusline): the current sandbox project.
dir="$(jq -r '.workspace.project_dir // .cwd // empty' 2>/dev/null)"
[ -n "$dir" ] || dir="$(cd "$(dirname "$0")/.." && pwd)"
"$dir/bin/sandbox" status --short 2>/dev/null || echo "🛡 sandbox: status unavailable"

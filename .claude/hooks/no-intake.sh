#!/usr/bin/env bash
# Always-on PreToolUse hook (registered in .claude/settings.local.json, so it stays on when the
# main guard in settings.json is switched off). Test code reaches the Mac never: Claude may not
# clone a repo or unpack/open an archive here; that goes through bin/sandbox new.
# A denylist safety net, not the boundary (guard.sh is). macOS /bin/bash 3.2 compatible.
set -uo pipefail

input="$(cat)"
[ "$(jq -r '.tool_name // empty' <<<"$input")" = Bash ] || exit 0
cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
root="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"

deny() {
  echo "Blocked by the job-test-sandbox intake rule: $* Test code goes only into a Docker volume: bin/sandbox new <firm> <https-url|zip>." >&2
  exit 2
}

# A single bin/sandbox call is how intake is meant to happen (it streams a zip into the volume).
case "$cmd" in
  *';'*|*'&'*|*'|'*|*$'\n'*) ;;
  bin/sandbox\ *|./bin/sandbox\ *|"$root"/bin/sandbox\ *) exit 0 ;;
esac

# A lone git commit runs nothing else, so words in its message (clone, unzip, tar) are only
# text. Anything that could start another program keeps the normal checks below.
case "$cmd" in
  *';'*|*'&'*|*'|'*|*$'\n'*|*'$('*|*'`'*|*'<('*|*'>('*) ;;
  'git commit '*) exit 0 ;;
esac

B='(^|[^[:alnum:]_./-])'
grep -Eq "${B}git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+clone([[:space:]]|$)" <<<"$cmd" &&
  deny "no git clone on the Mac."
grep -Eq "${B}gh[[:space:]]+repo[[:space:]]+clone([[:space:]]|$)" <<<"$cmd" &&
  deny "no gh repo clone on the Mac."
grep -Eq "${B}(unzip|ditto|tar|bsdtar|gtar|7z|7za|7zz|unar|unrar|xar|cpio|pax)([[:space:]]|$)" <<<"$cmd" &&
  deny "no unpacking archives on the Mac."
grep -Eq "${B}open([[:space:]].*)?\.(zip|tar|tgz|gz|7z|rar)([[:space:]]|$)" <<<"$cmd" &&
  deny "no opening archives on the Mac."
exit 0

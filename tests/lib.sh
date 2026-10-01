# Tiny assert helpers for the shell tests; macOS /bin/bash 3.2 compatible.
FAILS=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else
    fail "$1"; printf '       expected: %s\n       actual:   %s\n' "$2" "$3"; fi
}
assert_contains() {
  case "$3" in *"$2"*) pass "$1" ;; *)
    fail "$1"; printf '       missing: %s\n       in:      %s\n' "$2" "$3" ;; esac
}
assert_not_contains() {
  case "$3" in *"$2"*)
    fail "$1"; printf '       unexpected: %s\n       in:         %s\n' "$2" "$3" ;; *) pass "$1" ;; esac
}
finish() { [ "$FAILS" -eq 0 ]; }

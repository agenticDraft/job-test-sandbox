#!/bin/bash
# Runs tests/test_*.sh (or the files given) with macOS /bin/bash; non-zero exit on any failure.
cd "$(dirname "$0")/.." || exit 1
status=0
if [ $# -gt 0 ]; then files="$*"; else files="$(ls tests/test_*.sh)"; fi
for t in $files; do
  echo "== $t"
  /bin/bash "$t" || status=1
done
if [ $status -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $status

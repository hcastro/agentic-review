#!/bin/bash
# Apply deliberate breaks to production code one at a time and report whether the
# test command fails. Each file is restored after its run, and the clean baseline
# runs last.
#
# Usage: bash mutate.sh <copy-dir> <mutations-file> -- <test command...>
#
# The mutations file has one mutation per line, tab-separated:
#   <label>\t<file relative to copy-dir>\t<perl -0 substitution>
# Lines starting with # are skipped. The substitution is applied with `perl -0pi -e`,
# so it can span lines (use \n and \s+). A mutation that changes nothing is
# reported as NOT APPLIED, so a broken pattern can't look like a survivor.
#
# Example line:
#   drop experiment gate<TAB>lib/x.js<TAB>s/bucket === 'variant' &&//
set -uo pipefail

dir=${1:?copy dir}
mutations=$(cd "$(dirname "${2:?mutations file}")" && pwd)/$(basename "$2")
shift 2
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { echo "missing test command after --" >&2; exit 2; }

cd "$dir" || exit 2
log=$(mktemp "${TMPDIR:-/tmp}/mutate.XXXXXX")

summary() {
  # Jest prints "Tests: ...", vitest prints "Tests  ...".
  grep -E '^\s*Tests:?\s' "$log" | tail -1 | tr -s ' '
}

run_tests() {
  "$@" >"$log" 2>&1
  local code=$?
  if [ $code -eq 0 ]; then echo "SURVIVED (tests pass) $(summary)"; else echo "caught $(summary)"; fi
}

while IFS=$'\t' read -r label file subst; do
  [ -z "${label// }" ] && continue
  case "$label" in \#*) continue ;; esac
  if [ ! -f "$file" ]; then echo "$label: FILE NOT FOUND $file"; continue; fi
  /bin/cp "$file" "$file.mutate-orig"
  perl -0pi -e "$subst" "$file"
  if cmp -s "$file" "$file.mutate-orig"; then
    echo "$label: NOT APPLIED"
  else
    echo "$label: $(run_tests "$@")"
  fi
  /bin/mv "$file.mutate-orig" "$file"
done <"$mutations"

if "$@" >"$log" 2>&1; then
  echo "baseline: pass $(summary)"
else
  echo "baseline: FAIL $(summary) (fix the test command before trusting the mutation results)"
fi
rm -f "$log"

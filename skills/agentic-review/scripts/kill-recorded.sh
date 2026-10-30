#!/usr/bin/env bash
# Kill only processes a probe recorded itself, never by name or pattern.
#
# Usage: bash kill-recorded.sh <pids.tsv> [signal]
#
# Each line of pids.tsv is "<pid>\t<path and arguments>" (fake-tool.sh writes this
# format). When `ps` is usable, a pid is signalled only while its command line still
# contains the recorded path, so a reused pid belonging to another program is left
# alone. Inside a sandbox that blocks `ps`, the pid is signalled if it still exists.
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: kill-recorded.sh <pids.tsv> [signal]" >&2; exit 2; }
FILE=$1; SIG=${2:-KILL}
[ -f "$FILE" ] || exit 0
while IFS=$'\t' read -r pid cmd; do
  case $pid in ''|*[!0-9]*) continue ;; esac
  kill -0 "$pid" 2>/dev/null || continue
  exe=${cmd%% *}
  if now=$(ps -o command= -p "$pid" 2>/dev/null); then
    case $now in
      *"$exe"*) ;;
      *) echo "skipped $pid: now runs something else ($now)"; continue ;;
    esac
  fi
  kill -s "$SIG" "$pid" 2>/dev/null && echo "killed $pid ($cmd)"
done <"$FILE"

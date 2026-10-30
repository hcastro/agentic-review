#!/usr/bin/env bash
# Put a fake command (git, delta, ...) first on PATH for a probe, and record the pid
# and command line of every process it starts, so the probe can later kill exactly
# those processes and nothing else.
#
# Usage: bash fake-tool.sh <dir> <name> [--real <path>] [--sleep <seconds>] [--stderr <text>] [--exit <code>]
#
# Writes <dir>/bin/<name>. Each run appends "<pid>\t<path and arguments>" to <dir>/pids.tsv,
# writes --stderr to stderr, sleeps --sleep seconds, then either execs --real with the
# same arguments or exits with --exit (default 0). Kill what it started with
# kill-recorded.sh <dir>/pids.tsv.
set -euo pipefail

usage() { echo "usage: fake-tool.sh <dir> <name> [--real <path>] [--sleep <s>] [--stderr <text>] [--exit <code>]" >&2; exit 2; }
[ $# -ge 2 ] || usage
mkdir -p "$1/bin"; DIR=$(cd "$1" && pwd); NAME=$2; shift 2
REAL=""; SLEEP=0; STDERR=""; CODE=0
while [ $# -gt 0 ]; do
  case $1 in
    --real) REAL=$2; shift 2 ;;
    --sleep) SLEEP=$2; shift 2 ;;
    --stderr) STDERR=$2; shift 2 ;;
    --exit) CODE=$2; shift 2 ;;
    *) usage ;;
  esac
done
{
  echo '#!/bin/sh'
  printf 'printf "%%s\\t%%s\\n" "$$" "$0 $*" >>%q\n' "$DIR/pids.tsv"
  [ -n "$STDERR" ] && printf 'printf "%%s\\n" %q >&2\n' "$STDERR"
  [ "$SLEEP" != 0 ] && printf 'sleep %q\n' "$SLEEP"
  if [ -n "$REAL" ]; then printf 'exec %q "$@"\n' "$REAL"; else printf 'exit %q\n' "$CODE"; fi
} >"$DIR/bin/$NAME"
chmod +x "$DIR/bin/$NAME"
echo "$DIR/bin/$NAME"

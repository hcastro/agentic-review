#!/usr/bin/env bash
# Give one agent a runnable copy of a snapshot: the frozen tree plus the dependency
# folder, cloned so a dozen agents don't each copy node_modules.
#
# Usage: scratch.sh <snapshot-dir> <agent-id> [--deps <dir-holding-node_modules>]
#
# Prints the copy's path (<snapshot-dir>/scratch/<agent-id>/repo). Running it again
# for the same id prints the existing path. On APFS (macOS) and reflink file systems
# the copy is a clone: near-instant and no extra space until a file changes. Elsewhere
# the tree is copied and node_modules is symlinked (some package managers try to
# reinstall through a symlink; run the test runner from node_modules/.bin directly).
set -euo pipefail

usage() { echo "usage: scratch.sh <snapshot-dir> <agent-id> [--deps <dir>]" >&2; exit 2; }
[ $# -ge 2 ] || usage
SNAP=$(cd "$1" && pwd); ID=$2; shift 2
DEPS=""
while [ $# -gt 0 ]; do
  case $1 in
    --deps) [ $# -ge 2 ] || usage; DEPS=$(cd "$2" && pwd); shift 2 ;;
    *) usage ;;
  esac
done
case $ID in ''|.*|*/*) echo "scratch.sh: agent id must be a plain name" >&2; exit 2 ;; esac
[ -d "$SNAP/tree" ] || { echo "scratch.sh: $SNAP has no tree/; run snapshot.sh first" >&2; exit 1; }

DEST="$SNAP/scratch/$ID/repo"
if [ -e "$DEST" ]; then echo "$DEST"; exit 0; fi
mkdir -p "$SNAP/scratch/$ID"

# Try a clone first; clear any partial result before falling back, so a failed
# attempt can't leave tree/ nested inside the destination.
clone() {
  local src=$1 dst=$2
  /bin/cp -cR "$src" "$dst" 2>/dev/null && return 0
  /bin/rm -rf "$dst"
  /bin/cp --reflink=auto -R "$src" "$dst" 2>/dev/null && return 0
  /bin/rm -rf "$dst"
  return 1
}

clone "$SNAP/tree" "$DEST" || /bin/cp -R "$SNAP/tree" "$DEST"
if [ -n "$DEPS" ] && [ -d "$DEPS/node_modules" ]; then
  clone "$DEPS/node_modules" "$DEST/node_modules" || ln -s "$DEPS/node_modules" "$DEST/node_modules"
fi
echo "$DEST"

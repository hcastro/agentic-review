#!/usr/bin/env bash
# Freeze a checkout's current state (committed, staged, unstaged and untracked-but-not-ignored files)
# into a read-only copy for reviewers, without touching the checkout's index, working tree or refs.
#
# Usage: snapshot.sh <checkout> <base-ref> <out-dir> [--prev <previous-out-dir>]
#
# Writes:
#   <out-dir>/tree/           the frozen files (git archive of a snapshot commit; no .git)
#   <out-dir>/change.patch    everything since the merge base with <base-ref>
#   <out-dir>/delta.patch     what changed since --prev (only with --prev)
#   <out-dir>/snapshot.json   commit, head, merge base, file list with line counts, merge flags
#   <out-dir>/scratch/        empty; reviewers copy things here to run them
#
# The snapshot commit is an unreferenced git object, so `git gc` may prune it after a couple of weeks.
# delta.patch falls back to diffing the two tree/ folders when the previous commit is gone.
set -euo pipefail

usage() { echo "usage: snapshot.sh <checkout> <base-ref> <out-dir> [--prev <previous-out-dir>]" >&2; exit 2; }
[ $# -ge 3 ] || usage
CO=$1; BASE=$2; OUT=$3; shift 3
PREV=""
while [ $# -gt 0 ]; do
  case $1 in
    --prev) [ $# -ge 2 ] || usage; PREV=$2; shift 2 ;;
    *) usage ;;
  esac
done

CO=$(cd "$CO" && pwd)
git -C "$CO" rev-parse --is-inside-work-tree >/dev/null
TOP=$(git -C "$CO" rev-parse --show-toplevel)
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
if [ -e "$OUT/tree" ]; then echo "snapshot.sh: $OUT/tree already exists; use a new out-dir per snapshot" >&2; exit 1; fi

HEAD_SHA=$(git -C "$TOP" rev-parse HEAD)
MB=$(git -C "$TOP" merge-base "$BASE" HEAD)

# Build the snapshot tree in a throwaway index so the checkout's real index is never modified.
IDX=$(mktemp "${TMPDIR:-/tmp}/snapshot-index.XXXXXX")
trap 'rm -f "$IDX"' EXIT
GIT_INDEX_FILE=$IDX git -C "$TOP" read-tree HEAD
GIT_INDEX_FILE=$IDX git -C "$TOP" add -A
TREE=$(GIT_INDEX_FILE=$IDX git -C "$TOP" write-tree)

if [ "$TREE" = "$(git -C "$TOP" rev-parse 'HEAD^{tree}')" ]; then
  SNAP=$HEAD_SHA
else
  SNAP=$(GIT_AUTHOR_NAME=snapshot GIT_AUTHOR_EMAIL=snapshot@localhost \
         GIT_COMMITTER_NAME=snapshot GIT_COMMITTER_EMAIL=snapshot@localhost \
         git -C "$TOP" commit-tree "$TREE" -p "$HEAD_SHA" -m "review snapshot of working tree")
fi

mkdir -p "$OUT/tree" "$OUT/scratch"
git -C "$TOP" archive "$SNAP" | tar -x -C "$OUT/tree"
git -C "$TOP" diff --binary --no-renames "$MB" "$SNAP" > "$OUT/change.patch"

json_str() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }

# Emit a JSON array of {path, added, removed, status} for a diff between two commits.
files_json() {
  local from=$1 to=$2 first=1 a r p st
  printf '['
  while IFS="$(printf '\t')" read -r a r p; do
    [ -n "$p" ] || continue
    [ "$a" = "-" ] && a=0
    [ "$r" = "-" ] && r=0
    st=$(git -C "$TOP" diff --no-renames --name-status "$from" "$to" -- "$p" | cut -c1)
    case $st in A) st=added ;; D) st=deleted ;; *) st=modified ;; esac
    [ $first -eq 1 ] || printf ','
    first=0
    printf '{"path":%s,"added":%s,"removed":%s,"status":"%s"}' "$(json_str "$p")" "$a" "$r" "$st"
  done < <(git -C "$TOP" diff --no-renames --numstat "$from" "$to")
  printf ']'
}

loc() { git -C "$TOP" diff --no-renames --numstat "$1" "$2" | awk '{ a = ($1 == "-") ? 0 : $1; r = ($2 == "-") ? 0 : $2; s += a + r } END { print s + 0 }'; }

MERGES=$(git -C "$TOP" rev-list --merges --count "$MB..$HEAD_SHA")
MERGE_HEAD=false
git -C "$TOP" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && MERGE_HEAD=true

DELTA_JSON='null'
DELTA_LOC='null'
PREV_SNAP=""
if [ -n "$PREV" ]; then
  PREV=$(cd "$PREV" && pwd)
  PREV_SNAP=$(sed -n 's/.*"commit":"\([0-9a-f]*\)".*/\1/p' "$PREV/snapshot.json" | head -n 1)
  if [ -n "$PREV_SNAP" ] && git -C "$TOP" cat-file -e "$PREV_SNAP^{commit}" 2>/dev/null; then
    git -C "$TOP" diff --binary --no-renames "$PREV_SNAP" "$SNAP" > "$OUT/delta.patch"
    DELTA_JSON=$(files_json "$PREV_SNAP" "$SNAP")
    DELTA_LOC=$(loc "$PREV_SNAP" "$SNAP")
  else
    echo "snapshot.sh: previous commit unavailable; diffing tree folders instead" >&2
    (cd "$OUT" && diff -ruN "$PREV/tree" tree > delta.patch) || true
  fi
  # Earlier merges count only when they are new since the previous snapshot.
  if [ -n "$PREV_SNAP" ] && git -C "$TOP" cat-file -e "$PREV_SNAP^{commit}" 2>/dev/null; then
    MERGES=$(git -C "$TOP" rev-list --merges --count "$PREV_SNAP..$HEAD_SHA" 2>/dev/null || echo 0)
  fi
fi

{
  printf '{"commit":"%s","head":"%s","base":%s,"mergeBase":"%s","dirty":%s,' \
    "$SNAP" "$HEAD_SHA" "$(json_str "$BASE")" "$MB" "$([ "$SNAP" = "$HEAD_SHA" ] && echo false || echo true)"
  printf '"tree":%s,"files":%s,"totalLoc":%s,' "$(json_str "$OUT/tree")" "$(files_json "$MB" "$SNAP")" "$(loc "$MB" "$SNAP")"
  printf '"prev":%s,"deltaFiles":%s,"deltaLoc":%s,' "$( [ -n "$PREV_SNAP" ] && json_str "$PREV_SNAP" || echo null)" "$DELTA_JSON" "$DELTA_LOC"
  printf '"mergeCommits":%s,"mergeInProgress":%s}\n' "$MERGES" "$MERGE_HEAD"
} > "$OUT/snapshot.json"

echo "snapshot: $OUT"
echo "  commit $SNAP (head $HEAD_SHA, merge base $MB)"
echo "  $(grep -c '^diff --git' "$OUT/change.patch" || true) files in change.patch, $(loc "$MB" "$SNAP") changed lines"
[ -n "$PREV" ] && echo "  delta since $(basename "$PREV"): ${DELTA_LOC} changed lines"
[ "$MERGES" != "0" ] || [ "$MERGE_HEAD" = true ] && echo "  merge involved: $MERGES merge commit(s), merge in progress: $MERGE_HEAD"
exit 0

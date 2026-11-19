#!/usr/bin/env bash
# Start one fresh agent from the shell and save its final message, so the loop can
# launch reviewers from any harness that can run a command. A new process has an
# empty context, which is what the independence rules ask for.
#
# Usage: agent.sh <cli> <prompt-file> <report-file> [--dir <dir>] [--model <model>] [-- <extra args for the cli>]
#
#   <cli>     claude | codex | cursor | opencode | custom
#   --dir     folder the agent works in (default: the current folder). Give a reviewer
#             its own scratch copy from scratch.sh.
#   --model   passed to the cli's model option
#   custom    runs the command in $AGENTIC_REVIEW_AGENT_CMD through `sh -c`, with the
#             prompt on stdin, in --dir. Its stdout becomes the report.
#
# Exits with the cli's status, and with 3 when the cli wrote an empty report.
# To run several at once, start each with `&` and `wait`. Keep to about 8.
set -uo pipefail

usage() { echo "usage: agent.sh <claude|codex|cursor|opencode|custom> <prompt-file> <report-file> [--dir <dir>] [--model <model>] [-- <extra args>]" >&2; exit 2; }
[ $# -ge 3 ] || usage
CLI=$1; PROMPT=$2; REPORT=$3; shift 3
DIR=$PWD; MODEL=""; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR=${2:?}; shift 2 ;;
    --model) MODEL=${2:?}; shift 2 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) usage ;;
  esac
done
[ -f "$PROMPT" ] || { echo "agent.sh: no prompt file at $PROMPT" >&2; exit 2; }
[ -d "$DIR" ] || { echo "agent.sh: no folder at $DIR" >&2; exit 2; }
PROMPT=$(cd "$(dirname "$PROMPT")" && pwd)/$(basename "$PROMPT")
mkdir -p "$(dirname "$REPORT")"
REPORT=$(cd "$(dirname "$REPORT")" && pwd)/$(basename "$REPORT")
: > "$REPORT"
cd "$DIR" || exit 2

case "$CLI" in
  claude)
    claude -p ${MODEL:+--model "$MODEL"} ${EXTRA[@]+"${EXTRA[@]}"} < "$PROMPT" > "$REPORT" ;;
  codex)
    codex exec --skip-git-repo-check -s workspace-write ${MODEL:+-m "$MODEL"} ${EXTRA[@]+"${EXTRA[@]}"} -o "$REPORT" - < "$PROMPT" > "$REPORT.log" 2>&1 ;;
  cursor)
    cursor-agent -p --trust --output-format text ${MODEL:+--model "$MODEL"} ${EXTRA[@]+"${EXTRA[@]}"} "$(cat "$PROMPT")" < /dev/null > "$REPORT" ;;
  opencode)
    opencode run ${MODEL:+-m "$MODEL"} ${EXTRA[@]+"${EXTRA[@]}"} "$(cat "$PROMPT")" < /dev/null > "$REPORT" ;;
  custom)
    [ -n "${AGENTIC_REVIEW_AGENT_CMD:-}" ] || { echo "agent.sh: set AGENTIC_REVIEW_AGENT_CMD for the custom cli" >&2; exit 2; }
    sh -c "$AGENTIC_REVIEW_AGENT_CMD" < "$PROMPT" > "$REPORT" ;;
  *) usage ;;
esac
STATUS=$?
[ "$STATUS" -eq 0 ] && [ ! -s "$REPORT" ] && { echo "agent.sh: $CLI wrote an empty report" >&2; exit 3; }
exit "$STATUS"

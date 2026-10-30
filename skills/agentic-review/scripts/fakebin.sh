#!/usr/bin/env bash
# Fake clipboard tools for probes and tests, so nothing reaches the real clipboard.
#
# Usage: eval "$(bash fakebin.sh <dir>)"
#
# Writes <dir>/bin/{pbcopy,wl-copy,xclip,xsel,clip.exe}, prints an `export PATH=...`
# line that puts them first, and a check that fails loudly if a real tool still wins.
# Each fake appends "--- <tool> <pid>" and its stdin to <dir>/clipboard.log.
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: eval \"\$(bash fakebin.sh <dir>)\"" >&2; exit 2; }
mkdir -p "$1/bin"
DIR=$(cd "$1" && pwd)
for tool in pbcopy wl-copy xclip xsel clip.exe; do
  cat >"$DIR/bin/$tool" <<FAKE
#!/bin/sh
printf -- '--- %s %s\n' '$tool' "\$\$" >>'$DIR/clipboard.log'
cat >>'$DIR/clipboard.log'
FAKE
  chmod +x "$DIR/bin/$tool"
done
printf 'export PATH=%q:"$PATH"\n' "$DIR/bin"
printf 'for t in pbcopy wl-copy xclip xsel clip.exe; do [ "$(command -v "$t")" = %q/"$t" ] || { echo "real $t still first on PATH" >&2; return 1 2>/dev/null || exit 1; }; done\n' "$DIR/bin"

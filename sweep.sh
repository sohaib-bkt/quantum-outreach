#!/bin/bash
# sweep.sh — run run.sh over a niche's keyword variations (IG returns ~5 hits/query max)
# Usage: ./sweep.sh barber        (uses keywords/barber.txt; ls keywords/ for niches)
#        ./sweep.sh keywords/custom.txt 40
#        ./sweep.sh all 40         (every pack in keywords/, long run)
# keywords file: one "trade city" per line, # comments allowed
set -e
LIST="${1:-barber}"
LIMIT="${2:-40}"
DIR="$(cd "$(dirname "$0")" && pwd)"
resolve_list() {
  local q="$1"
  [ -f "$q" ] && { echo "$q"; return 0; }
  [ -f "$DIR/$q" ] && { echo "$DIR/$q"; return 0; }
  local base="${q%.txt}"
  [ -f "$DIR/keywords/$base.txt" ] && { echo "$DIR/keywords/$base.txt"; return 0; }
  return 1
}
LISTS=""
if [ "$LIST" = "all" ]; then
  LISTS="$DIR"/keywords/*.txt
else
  LISTS=$(resolve_list "$LIST") || { echo "Unknown niche/list: $LIST (ls $DIR/keywords/)"; exit 1; }
fi
TOTAL_Q=0
run_list() {
  while IFS= read -r KW || [ -n "$KW" ]; do
    KW=$(echo "$KW" | sed 's/#.*//' | xargs)
    [ -z "$KW" ] && continue
    echo "########## SWEEP: $KW ##########"
    "$DIR/run.sh" "$KW" "$LIMIT" 2>&1 | tail -n 12
    echo ""
    TOTAL_Q=$((TOTAL_Q + 1))
    sleep 20
  done < "$1"
}
for L in $LISTS; do
  case "$L" in */README.txt) continue;; esac
  echo "### pack: $L"
  export NICHE=$(basename "$L" .txt)
  # temp ad-hoc lists keep their filename as niche (one place per list)
  run_list "$L"
done
unset NICHE
echo "=== sweep done: $TOTAL_Q keywords ==="
echo "Qualified pool: sort -u /tmp/quantum-*-usernames.txt | grep -v '^$'"

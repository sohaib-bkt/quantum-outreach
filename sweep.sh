#!/bin/bash
# sweep.sh — run run.sh over many keyword variations (IG returns ~5 hits/query max)
# Usage: ./sweep.sh keywords-barber.txt 40
#        ./sweep.sh   (defaults: keywords.txt 40)
# keywords file: one "niche city" per line, # comments allowed
set -e
LIST="${1:-keywords.txt}"
LIMIT="${2:-40}"
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$LIST" ]; then
  # allow relative to script dir
  [ -f "$DIR/$LIST" ] && LIST="$DIR/$LIST" || { echo "Missing list: $LIST"; exit 1; }
fi
TOTAL_Q=0
while IFS= read -r KW || [ -n "$KW" ]; do
  KW=$(echo "$KW" | sed 's/#.*//' | xargs)
  [ -z "$KW" ] && continue
  echo "########## SWEEP: $KW ##########"
  "$DIR/run.sh" "$KW" "$LIMIT" 2>&1 | tail -n 12
  echo ""
  TOTAL_Q=$((TOTAL_Q + 1))
  sleep 20
done < "$LIST"
echo "=== sweep done: $TOTAL_Q keywords ==="
echo "Qualified pool: sort -u /tmp/quantum-*-usernames.txt | grep -v '^$'"

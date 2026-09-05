#!/bin/bash
# quantum-outreach entrypoint — keyword first, multi-niche
# Usage: ./run.sh "clinique dentaire paris" 20
#        ./run.sh   (will ask for keyword)
set -e
export PATH="$HOME/quantum-outreach/.venv/bin:$PATH"
KEYWORD="${1:-}"
LIMIT="${2:-20}"
if [ -z "$KEYWORD" ]; then
  printf "Keyword (e.g. restaurant paris, clinique lyon, ecommerce france): "
  read -r KEYWORD
fi
if [ -z "$KEYWORD" ]; then echo "No keyword, abort."; exit 1; fi
SAFE=$(echo "$KEYWORD" | tr ' ' '_' | tr -cd '[:alnum:]_-')
OUT="/tmp/quantum-${SAFE}-$(date +%Y%m%d).yaml"
mkdir -p ~/.agent-reach
touch ~/.agent-reach/quantum-prospects.csv
echo "=== keyword: $KEYWORD (limit $LIMIT) ==="
if ! command -v agent-reach >/dev/null 2>&1; then
  echo "WARN: agent-reach not on PATH here. Run where it IS installed:"
  echo "  agent-reach doctor --json"
  echo "Manual fallback: give me 10 usernames for '$KEYWORD' and I draft messages."
  exit 2
fi
agent-reach doctor --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); i=d.get('instagram',{}); print('instagram:', i.get('status'), '| backend:', i.get('active_backend'))" 2>/dev/null || echo "(doctor unavailable)"
if ! command -v opencli >/dev/null 2>&1; then
  echo "WARN: opencli missing. Install: agent-reach install --env=auto --system --channels=instagram,opencli"
  exit 3
fi
echo "--- search (read-only, no DM sending) ---"
opencli instagram search "$KEYWORD" -f yaml > "$OUT" 2>&1 || true
if grep -q "BROWSER_CONNECT\|not connected" "$OUT"; then
  echo "BLOCKED: Chrome extension not connected. Do in Chrome:"
  echo "  1. Install OpenCLI extension, 2. Login instagram.com, 3. opencli doctor"
  exit 4
fi
if grep -q "HTTP 429" "$OUT"; then
  echo "RATE-LIMITED (429): wait 10-15 min, re-login instagram.com if needed, retry later."
  exit 5
fi
head -n $((LIMIT * 8)) "$OUT"
echo "--- saved raw: $OUT"
# --- no-website filter: extract usernames, stage as to_verify ---
ULIST="/tmp/quantum-${SAFE}-usernames.txt"
grep -oP 'username:\s*\K\S+' "$OUT" | sort -u > "$ULIST" || true
N=$(wc -l < "$ULIST" | tr -d ' ')
echo "--- $N usernames -> $ULIST ---"
CSV=~/.agent-reach/quantum-prospects.csv
D=$(date +%Y-%m-%d)
ADDED=0
while read -r u; do
  [ -z "$u" ] && continue
  if ! grep -q ",$u," "$CSV" 2>/dev/null; then
    echo "$D,$KEYWORD,$u,,to_verify: web-check official site (profile API is 429),no,no" >> "$CSV"
    ADDED=$((ADDED + 1))
  fi
done < "$ULIST"
echo "staged $ADDED new candidates in $CSV"
echo "Next: give me the usernames (or $ULIST), I web-check official sites,"
echo "keep only NO-SITE ones, then draft FR messages. You send manually."

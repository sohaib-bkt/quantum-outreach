#!/bin/bash
# quantum-outreach entrypoint — keyword first, multi-niche, quality-filtered
# Usage: ./run.sh "coiffeur amiens" 20
#        ./run.sh   (will ask for keyword)
# Env knobs: MIN_FOLLOWERS=30 MIN_POSTS=5 REQUIRE_BIO=1 RECENCY_DAYS=120 SKIP_RECENCY=0 SLEEP_S=10
set -e
export PATH="$HOME/quantum-outreach/.venv/bin:$PATH"
KEYWORD="${1:-}"
LIMIT="${2:-40}"
MIN_FOLLOWERS="${MIN_FOLLOWERS:-30}"
MIN_POSTS="${MIN_POSTS:-5}"
REQUIRE_BIO="${REQUIRE_BIO:-1}"
RECENCY_DAYS="${RECENCY_DAYS:-120}"
SKIP_RECENCY="${SKIP_RECENCY:-0}"
SLEEP_S="${SLEEP_S:-10}"
if [ -z "$KEYWORD" ]; then
  printf "Keyword (e.g. restaurant paris, clinique lyon, ecommerce france): "
  read -r KEYWORD
fi
if [ -z "$KEYWORD" ]; then echo "No keyword, abort."; exit 1; fi
SAFE=$(echo "$KEYWORD" | tr ' ' '_' | tr -cd '[:alnum:]_-')
STAMP=$(date +%Y%m%d)
OUT="/tmp/quantum-${SAFE}-${STAMP}.yaml"
ENRICHED="/tmp/quantum-${SAFE}-${STAMP}-enriched.yaml"
QLIST="/tmp/quantum-${SAFE}-usernames.txt"
mkdir -p ~/.agent-reach
touch ~/.agent-reach/quantum-prospects.csv
: > "$ENRICHED"
echo "=== keyword: $KEYWORD (limit $LIMIT | minFol $MIN_FOLLOWERS minPosts $MIN_POSTS bio $REQUIRE_BIO recency ${RECENCY_DAYS}d) ==="
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
opencli instagram search "$KEYWORD" --limit "$LIMIT" -f yaml > "$OUT" 2>&1 || true
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
# --- stage 1: parse search hits, drop verified + private, dedupe vs CSV ---
CANDS=$(python3 - "$OUT" <<'EOF'
import re, sys
txt = open(sys.argv[1], errors='ignore').read()
users = []
for block in re.split(r'(?m)^-\s', txt):
  m = re.search(r'username:\s*(\S+)', block)
  if not m: continue
  u = m.group(1).strip().strip("'\"")
  priv = re.search(r"private:\s*['\"]?(Yes|No|True|False)", block)
  ver = re.search(r"verified:\s*['\"]?(Yes|No|True|False)", block)
  users.append((u,
    (priv.group(1).lower() in ('yes','true')) if priv else False,
    (ver.group(1).lower() in ('yes','true')) if ver else False))
seen, out = set(), []
for u, p, v in users:
  if u not in seen: seen.add(u); out.append(f"{u}\t{int(p)}\t{int(v)}")
print('\n'.join(out))
EOF
)
CSV=~/.agent-reach/quantum-prospects.csv
D=$(date +%Y-%m-%d)
QUALIFIED=()
ENRICH_HIT_429=0
while IFS=$'\t' read -r u is_priv is_ver; do
  [ -z "$u" ] && continue
  if [ "$is_ver" = "1" ]; then echo "drop $u (verified/brand)"; continue; fi
  if [ "$is_priv" = "1" ]; then
    awk -F, -v u="$u" '$3==u{found=1} END{exit !found}' "$CSV" 2>/dev/null || echo "$D,$KEYWORD,$u,,SKIP private account,no,no" >> "$CSV"
    echo "drop $u (private)"; continue
  fi
  if awk -F, -v u="$u" '$3==u{found=1} END{exit !found}' "$CSV" 2>/dev/null; then echo "drop $u (already in CSV)"; continue; fi
  # --- stage 2: enrich via profile (followers/posts/bio); degrade gracefully on 429 ---
  if [ "$ENRICH_HIT_429" = "0" ]; then
    POUT=$(opencli instagram profile "$u" -f yaml 2>&1 || true)
    if echo "$POUT" | grep -q "HTTP 429"; then
      echo "profile 429 on $u — enrichment paused (limits reset in ~1h); rest staged unenriched."
      ENRICH_HIT_429=1
      echo "$D,$KEYWORD,$u,,to_verify: enrichment paused (429) - manual activity+site check,no,no" >> "$CSV"
      QUALIFIED+=("$u")
    elif echo "$POUT" | grep -q "ok: false"; then
      echo "keep $u (profile lookup failed, manual check)"
      echo "$D,$KEYWORD,$u,,to_verify: profile lookup failed - manual activity+site check,no,no" >> "$CSV"
      QUALIFIED+=("$u")
    else
      echo "$POUT" >> "$ENRICHED"
      SIG=$(echo "$POUT" | python3 -c "
import re,sys
t=sys.stdin.read()
def num(k):
  m=re.search(k+r':\s*[\'\"]?([\d,\.kKmM]+)',t)
  if not m: return -1
  v=m.group(1).replace(',','')
  try:
    if v[-1] in 'kK': return int(float(v[:-1])*1000)
    if v[-1] in 'M': return int(float(v[:-1])*1000000)
    return int(float(v))
  except: return -1
f=num('followers'); p=num('posts')
b=re.search(r'bio:\s*(.+)',t)
bio=(b.group(1).strip() if b else '')
print(f'{f}\t{p}\t{1 if bio and bio not in (chr(39)+chr(39),chr(34)+chr(34),\"None\",\"null\",\"~\") else 0}')")
      FOL=$(echo "$SIG" | cut -f1); PST=$(echo "$SIG" | cut -f2); HASBIO=$(echo "$SIG" | cut -f3)
      REASON=""
      { [ "$FOL" -ge 0 ] && [ "$FOL" -lt "$MIN_FOLLOWERS" ] && REASON="low followers($FOL)"; } || true
      { [ -z "$REASON" ] && [ "$PST" -ge 0 ] && [ "$PST" -lt "$MIN_POSTS" ] && REASON="few posts($PST)"; } || true
      { [ -z "$REASON" ] && [ "$REQUIRE_BIO" = "1" ] && [ "$HASBIO" = "0" ] && REASON="empty bio"; } || true
      if [ -n "$REASON" ]; then
        echo "drop $u ($REASON)"
        echo "$D,$KEYWORD,$u,,SKIP $REASON (fol=$FOL posts=$PST),no,no" >> "$CSV"
        sleep "$SLEEP_S"; continue
      fi
      # --- stage 3: recency via recent posts (survivors only) ---
      if [ "$SKIP_RECENCY" = "0" ]; then
        UOUT=$(opencli instagram user "$u" --limit 3 -f yaml 2>&1 || true)
        if echo "$UOUT" | grep -q "ok: false\|HTTP 429\|SyntaxError\|DOCTYPE"; then
          echo "keep $u (fol=$FOL posts=$PST, recency unknown - manual check)"
          echo "$D,$KEYWORD,$u,,to_verify: fol=$FOL posts=$PST recency unknown - check site+bio manually,no,no" >> "$CSV"
          QUALIFIED+=("$u")
        else
          echo "$UOUT" >> "$ENRICHED"
          echo "keep $u (fol=$FOL posts=$PST, recent posts found - verify date manually)"
          echo "$D,$KEYWORD,$u,,to_verify: fol=$FOL posts=$PST active - web-check official site,no,no" >> "$CSV"
          QUALIFIED+=("$u")
        fi
      else
        echo "keep $u (fol=$FOL posts=$PST)"
        echo "$D,$KEYWORD,$u,,to_verify: fol=$FOL posts=$PST - web-check official site,no,no" >> "$CSV"
        QUALIFIED+=("$u")
      fi
    fi
    sleep "$SLEEP_S"
  else
    echo "keep $u (unenriched - manual check)"
    echo "$D,$KEYWORD,$u,,to_verify: enrichment paused (429) - manual activity+site check,no,no" >> "$CSV"
    QUALIFIED+=("$u")
  fi
done <<< "$CANDS"
printf "%s\n" "${QUALIFIED[@]}" | sort -u > "$QLIST"
N=$(grep -c . "$QLIST" 2>/dev/null || true); N=${N:-0}
echo "--- $N qualified -> $QLIST (enriched raw: $ENRICHED) ---"
if [ "$N" -gt 0 ]; then
  echo "Quick activity check (logged-in browser):"
  while read -r u; do [ -n "$u" ] && echo "  https://www.instagram.com/$u/"; done < "$QLIST"
fi
echo "Next: give me the usernames (or $QLIST), I web-check official sites,"
echo "keep only NO-SITE ones, then draft FR messages. You send manually."

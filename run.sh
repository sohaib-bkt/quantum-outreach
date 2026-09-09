#!/bin/bash
# quantum-outreach entrypoint — keyword first, multi-niche, quality-filtered
# Usage: ./run.sh "coiffeur amiens" 20
#        NICHE=coiffure ./run.sh "coiffeur amiens"   (override niche file; else auto from keywords/ packs)
# Env knobs: MIN_FOLLOWERS=30 MIN_POSTS=5 REQUIRE_BIO=1 RECENCY_DAYS=180 SKIP_RECENCY=0 SLEEP_S=10
#            EXPAND=1 EXPAND_SEEDS=2 EXPAND_LIMIT=20
# Pool rule (strict): a user enters clients/<niche>.csv ONLY with a verified
# post <= RECENCY_DAYS old. Anything unverifiable (profile/user 429, login
# wall, unparseable dates) is parked in the master CSV as to_verify and stays
# OUT of the pool. SKIP_RECENCY=1 is an explicit opt-out (marks UNCHECKED).
set -e
export PATH="$HOME/quantum-outreach/.venv/bin:$PATH"
KEYWORD="${1:-}"
LIMIT="${2:-40}"
MIN_FOLLOWERS="${MIN_FOLLOWERS:-30}"
MIN_POSTS="${MIN_POSTS:-5}"
REQUIRE_BIO="${REQUIRE_BIO:-1}"
RECENCY_DAYS="${RECENCY_DAYS:-180}"
SKIP_RECENCY="${SKIP_RECENCY:-0}"
SLEEP_S="${SLEEP_S:-10}"
LIBDIR="$(cd "$(dirname "$0")/lib" && pwd)"
EXPAND="${EXPAND:-1}"
EXPAND_SEEDS="${EXPAND_SEEDS:-2}"
EXPAND_LIMIT="${EXPAND_LIMIT:-20}"
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
        echo "profile 429 on $u — parked (NOT pool-qualified, limits reset in ~1h)."
        ENRICH_HIT_429=1
        echo "$D,$KEYWORD,$u,,to_verify: enrichment paused (429) - manual activity+site check,no,no" >> "$CSV"
      elif echo "$POUT" | grep -q "ok: false"; then
        echo "park $u (profile lookup failed - manual check, NOT pool-qualified)"
        echo "$D,$KEYWORD,$u,,to_verify: profile lookup failed - manual activity+site check,no,no" >> "$CSV"
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
bio=(b.group(1).strip().strip(chr(39)+chr(34)) if b else '')
bio=bio.replace('\t',' ').strip()
print(f'{f}\t{p}\t{1 if bio and bio not in (\"None\",\"null\",\"~\") else 0}\t{bio}')")
      FOL=$(echo "$SIG" | cut -f1); PST=$(echo "$SIG" | cut -f2); HASBIO=$(echo "$SIG" | cut -f3)
      BIO=$(echo "$SIG" | cut -f4-)
      REASON=""
      { [ "$FOL" -ge 0 ] && [ "$FOL" -lt "$MIN_FOLLOWERS" ] && REASON="low followers($FOL)"; } || true
      { [ -z "$REASON" ] && [ "$PST" -ge 0 ] && [ "$PST" -lt "$MIN_POSTS" ] && REASON="few posts($PST)"; } || true
      { [ -z "$REASON" ] && [ "$REQUIRE_BIO" = "1" ] && [ "$HASBIO" = "0" ] && REASON="empty bio"; } || true
      if [ -n "$REASON" ]; then
        echo "drop $u ($REASON)"
        echo "$D,$KEYWORD,$u,,SKIP $REASON (fol=$FOL posts=$PST),no,no" >> "$CSV"
        sleep "$SLEEP_S"; continue
      fi
      # --- stage 2b: bio site pre-filter (own domain -> OUT now, not later) ---
      SITE=$(printf '%s' "$BIO" | PYTHONPATH="$LIBDIR" python3 -c "import sys; sys.path.insert(0,'$LIBDIR'); from filter import classify_bio; k,d=classify_bio(sys.stdin.read()); print(k+'\t'+(d or ''))")
      SKIND=$(echo "$SITE" | cut -f1); SDOM=$(echo "$SITE" | cut -f2)
      ANGLE=""
      if [ "$SKIND" = "standalone" ]; then
        echo "drop $u (bio links own site $SDOM)"
        echo "$D,$KEYWORD,$u,,OUT has $SDOM (bio link pre-filter),no,no" >> "$CSV"
        sleep "$SLEEP_S"; continue
      elif [ "$SKIND" = "booking" ]; then
        ANGLE=" - angle resa directe ($SDOM only)"
      fi
      # --- stage 3: recency via recent posts (survivors only).
      # STRICT: only a verified post <= RECENCY_DAYS old qualifies for the pool.
      # Unverifiable (429/login wall/unparseable) is parked in master, NOT qualified.
      if [ "$SKIP_RECENCY" = "0" ]; then
        UOUT=$(opencli instagram user "$u" --limit 5 -f yaml 2>&1 || true)
        if echo "$UOUT" | grep -q "ok: false\|HTTP 429\|SyntaxError\|DOCTYPE"; then
          echo "park $u (fol=$FOL posts=$PST, recency unverifiable - manual date check, NOT pool-qualified)"
          echo "$D,$KEYWORD,$u,,to_verify: fol=$FOL posts=$PST recency unknown - check last-post date+bio manually,no,no" >> "$CSV"
        else
          echo "$UOUT" >> "$ENRICHED"
          AGE=$(printf '%s' "$UOUT" | PYTHONPATH="$LIBDIR" python3 -c "import sys; sys.path.insert(0,'$LIBDIR'); from filter import newest_post_age_days; a=newest_post_age_days(sys.stdin.read()); print('' if a is None else a)")
          if [ -z "$AGE" ]; then
            echo "park $u (fol=$FOL posts=$PST, no parseable post date - manual check, NOT pool-qualified)"
            echo "$D,$KEYWORD,$u,,to_verify: fol=$FOL posts=$PST no parseable post date - manual check,no,no" >> "$CSV"
          elif [ "$AGE" -gt "$RECENCY_DAYS" ]; then
            echo "drop $u (inactive: last post ${AGE}d ago > ${RECENCY_DAYS}d)"
            echo "$D,$KEYWORD,$u,,SKIP inactive last post ${AGE}d ago (> ${RECENCY_DAYS}d) (fol=$FOL posts=$PST),no,no" >> "$CSV"
          else
            echo "keep $u (fol=$FOL posts=$PST, last post ${AGE}d ago$ANGLE)"
            echo "$D,$KEYWORD,$u,,active ${AGE}d ago fol=$FOL posts=$PST$ANGLE - web-check official site,no,no" >> "$CSV"
            QUALIFIED+=("$u")
          fi
        fi
      else
        echo "keep $u (fol=$FOL posts=$PST, recency UNCHECKED via SKIP_RECENCY=1$ANGLE)"
        echo "$D,$KEYWORD,$u,,active UNCHECKED (SKIP_RECENCY=1) fol=$FOL posts=$PST$ANGLE - web-check official site,no,no" >> "$CSV"
        QUALIFIED+=("$u")
      fi
    fi
    sleep "$SLEEP_S"
  else
    echo "park $u (unenriched - manual check, NOT pool-qualified)"
    echo "$D,$KEYWORD,$u,,to_verify: enrichment paused (429) - manual activity+site check,no,no" >> "$CSV"
  fi
done <<< "$CANDS"
printf "%s\n" "${QUALIFIED[@]}" | sort -u > "$QLIST"
# --- stage 4: follower expansion (degrades on 429; same filters as stage 1) ---
if [ "$EXPAND" = "1" ]; then
  SEEDS=$(grep . "$QLIST" 2>/dev/null | head -n "$EXPAND_SEEDS")
  if [ -z "$SEEDS" ]; then echo "--- expansion skipped (no qualified seeds) ---"; fi
  for s in $SEEDS; do
    FOUT=$(opencli instagram followers "$s" --limit "$EXPAND_LIMIT" -f yaml 2>&1 || true)
    if echo "$FOUT" | grep -q "HTTP 429\|ok: false\|DOCTYPE\|SyntaxError\|BROWSER_CONNECT\|not connected"; then
      echo "--- expansion paused on @$s (endpoint limited, auto-retries next run) ---"
      break
    fi
    NEWN=0
    while IFS=$'\t' read -r u is_priv is_ver; do
      [ -z "$u" ] && continue
      [ "$is_ver" = "1" ] && continue
      if [ "$is_priv" = "1" ]; then
        awk -F, -v u="$u" '$3==u{found=1} END{exit !found}' "$CSV" 2>/dev/null || echo "$D,$KEYWORD,$u,,SKIP private account (via $s),no,no" >> "$CSV"
        continue
      fi
      awk -F, -v u="$u" '$3==u{found=1} END{exit !found}' "$CSV" 2>/dev/null && continue
      # Expansion hits skip enrichment (no profile/recency proof) -> staged in
      # master for a later verification run, NEVER directly pool-qualified.
      echo "$D,$KEYWORD,$u,,to_verify: found via @$s followers - needs profile+recency check,no,no" >> "$CSV"
      NEWN=$((NEWN + 1))
    done <<< "$(echo "$FOUT" | python3 -c "
import re,sys
txt = sys.stdin.read()
users = []
for block in re.split(r'(?m)^-\s', txt):
  m = re.search(r'username:\s*(\S+)', block)
  if not m: continue
  u = m.group(1).strip().strip(chr(39)+chr(34))
  priv = re.search(r\"private:\s*['\\\"]?(Yes|No|True|False)\", block)
  ver = re.search(r\"verified:\s*['\\\"]?(Yes|No|True|False)\", block)
  users.append((u, (priv.group(1).lower() in ('yes','true')) if priv else False, (ver.group(1).lower() in ('yes','true')) if ver else False))
seen, out = set(), []
for u, p, v in users:
  if u not in seen: seen.add(u); out.append(f'{u}\t{int(p)}\t{int(v)}')
print('\n'.join(out))")"
    echo "expand @$s: +$NEWN staged for verification (NOT pool-qualified until recency proven)"
    printf "%s\n" "${QUALIFIED[@]}" | sort -u > "$QLIST"
    sleep "$SLEEP_S"
  done
fi
N=$(grep -c . "$QLIST" 2>/dev/null || true); N=${N:-0}
echo "--- $N qualified -> $QLIST (enriched raw: $ENRICHED) ---"
# --- persist qualified in-repo: one file per niche -> clients/<niche>.csv ---
CDIR="$(cd "$(dirname "$0")" && pwd)/clients"
mkdir -p "$CDIR"
if [ -z "${NICHE:-}" ]; then
  NICHE=$(python3 -c "
import sys, glob, os
kw = sys.argv[1]
for fp in glob.glob(os.path.expanduser('~/quantum-outreach/keywords/*.txt')):
  n = os.path.basename(fp)[:-4]
  if n == 'README': continue
  for line in open(fp, errors='ignore'):
    if line.split('#')[0].strip() == kw: print(n); raise SystemExit
print('misc')" "$KEYWORD")
fi
NFILE="$CDIR/$NICHE.csv"
[ -f "$NFILE" ] || echo "date,keyword,username,niche,stage,sent,replied" > "$NFILE"
python3 -c "
import sys
csv, qlist, nfile, niche = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
have = set()
for line in open(nfile, errors='ignore'):
  p = line.rstrip('\n').split(',')
  if len(p) > 2 and p[2] != 'username': have.add(p[2])
users = [l.strip() for l in open(qlist, errors='ignore') if l.strip()]
store = {}
for line in open(csv, errors='ignore'):
  line = line.rstrip('\n')
  if line.startswith('date,') or not line.strip(): continue
  head, sent, replied = line.rsplit(',', 2)
  p = head.split(',', 4)
  if len(p) != 5: continue
  d, kw, u, n4, stage = p
  if stage.startswith(('SKIP','OUT','to_verify','unclear')): continue
  store[u] = (d, kw, stage, sent, replied)
added = 0
with open(nfile, 'a') as f:
  for u in users:
    if u in have or u not in store: continue
    d, kw, stage, sent, replied = store[u]
    f.write(f'{d},{kw},{u},{niche},{stage},{sent},{replied}\n')
    have.add(u); added += 1
print(f'niche file: {nfile} (+{added})')" "$CSV" "$QLIST" "$NFILE" "$NICHE"
if [ "$N" -gt 0 ]; then
  echo "Quick activity check (logged-in browser):"
  while read -r u; do [ -n "$u" ] && echo "  https://www.instagram.com/$u/"; done < "$QLIST"
fi
echo "Next: give me the usernames (or $QLIST = active <=${RECENCY_DAYS}d only), I web-check"
echo "official sites, keep only NO-SITE ones, then draft FR messages. You send manually."
echo "Parked (unverified recency/site): grep to_verify ~/.agent-reach/quantum-prospects.csv"

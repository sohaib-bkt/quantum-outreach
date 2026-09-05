# AGENTS.md — quantum-outreach

Semi-auto Instagram prospecting for quantum.web.space (France/GDPR). AI finds + drafts, human sends. No auto-DM exists — never try to send.

## Layout (non-obvious)

- Repo = `~/quantum-outreach/` (the home dir itself is not a repo). Logic lives here; run outputs:
  - `clients/<keyword>-<date>.csv` + `clients/pool.csv` — qualified per run (public IG usernames only, no PII). Committable.
  - `~/.agent-reach/quantum-prospects.csv` — full store incl. OUT/SKIP + message tracking. **Never commit or move into repo.**
  - `/tmp/quantum-<kw>-<date>.yaml` — raw per-run output, ephemeral.
- `run.sh "keyword" [limit]` (default 40) — single keyword. `sweep.sh <niche|file|all> [limit]` loops a `keywords/<niche>.txt` pack (`barber coiffure beaute resto artisans sante immobilier`) with 20s pauses. `niches/*.md` — per-vertical problem + FR message angle (read before drafting).

## Commands

```bash
cd ~/quantum-outreach
./run.sh "coiffeur rouen" 40
./sweep.sh beaute 40     # niche pack; ls keywords/ for all
bash -n run.sh   # syntax check after edits (no test suite exists)
```

`run.sh` prepends `.venv/bin` to PATH itself. `opencli` resolves via nvm node v24.15.0 on PATH; bare `agent-reach` is NOT on PATH — use `./.venv/bin/agent-reach`.

## Gotchas that bite

- **IG returns ~5 users per query no matter `--limit`.** Scale via niche packs (`keywords/<niche>.txt`, run with `./sweep.sh <niche>`) + glued one-token variants (`barberlille`, `coiffurelille`) + follower expansion (`EXPAND=1`, auto-degrades on 429), not bigger limits. Expect `[]` for phrasings nobody uses as a username (e.g. "clinique dentaire rouen" — see `keywords/sante.txt` warning).
- **Site verdicts follow `VERIFY.md` — read it before marking KEEP.** Ladder: `OUT has <domain>` / `OUT <network> group` / `unclear` (never default to KEEP) / `KEEP-weak` (Planity/Booksy/Kalendes-only — résa-directe angle) / `KEEP` (no site: directories/DM only). Traps: "rdv via notre site" usually = platform subdomain; same-name businesses in other cities; directory profiles ≠ sites.
- **`profile` endpoint is near-permanently HTTP 429; `user` returns HTML login wall.** `run.sh` already degrades (stages `to_verify`, prints profile links for manual check). Do not "fix" by retry hammering — back off ~1h. Enrichment filters (`MIN_FOLLOWERS=30`, `MIN_POSTS=5`, `REQUIRE_BIO=1`, `RECENCY_DAYS=120`, `SKIP_RECENCY`, `SLEEP_S=10`) arm automatically when limits lift.
- **CSV dedupe must be exact username-field match** (`awk -F, '$3==u'`). Never `grep ",$u,"` — regex dots match the keyword column (`barber.lille` false-matched `barber lille`) and silently drop fresh prospects.
- Keep `sleep`s between IG calls; search 429 → exit 5 means stop for 10–15 min, not retry.
- After a run: web-check official sites, mark `KEEP` (no site) vs `OUT <reason>` in CSV, draft FR message per `niches/` angle. First DM: no link, <400 chars, end with `Répondez STOP si non concerné`. B2B pro accounts only.
- README's "Deps status" section is stale (2026-09-04) — trust this file + the scripts.

# quantum-outreach

Semi-auto Instagram prospecting for quantum.web.space. FRANCE focus (GDPR).
AI finds + drafts, **you send manually** — no auto-DM exists, never try to send.

## Layout

| Path | What |
|---|---|
| `run.sh "keyword" [limit]` | Single-keyword run (default limit 40). Niche auto-detected from `keywords/` packs; `NICHE=` overrides |
| `sweep.sh <niche\|file\|all> [limit]` | Loops a `keywords/<niche>.txt` pack with 20s pauses |
| `keywords/<niche>.txt` | Keyword packs: `barber coiffure beaute resto artisans sante immobilier` (+ wording×city + glued one-token variants) |
| `clients/<niche>.csv` | Qualified pool, one file per niche (`date,keyword,username,niche,stage,sent,replied`). Committable |
| `~/.agent-reach/quantum-prospects.csv` | Master store incl. OUT/SKIP + tracking (`date,keyword,username,niche,problem_found,message_sent,replied`). **Never commit** |
| `niches/*.md` | Per-vertical problem + FR message angle (read before drafting) |
| `VERIFY.md` | Site-verification ladder — read before marking KEEP |
| `AGENTS.md` | Agent operating instructions (subagents, gotchas) |
| `/tmp/quantum-<kw>-<date>.yaml` | Raw per-run output, ephemeral |

Reopen after closing the terminal: `cd ~/quantum-outreach && ls`, then run.

## Use

```bash
./run.sh "coiffeur rouen" 40   # one keyword
./sweep.sh beaute 40           # whole niche pack
./sweep.sh all 40              # everything (slow, mind 429s)
bash -n run.sh                 # syntax check after edits (no test suite)
```

Flow: search (read-only) → enrich profile + recency (auto-degrades to `to_verify`
when IG 429s — back off ~1h, don't retry-hammer) → web-check official sites →
mark verdicts → draft FR message per `niches/` angle → **you send manually**
(10–15/hour, 20–30/day, vary).

## Verdicts (`VERIFY.md`)

- `KEEP` — no site (directories/DM-only don't count as sites)
- `KEEP-weak` — booking-platform-only (Planity/Booksy/Kalendes): résa-directe angle
- `OUT <domain|network>` — has a site or belongs to a network group (mandataires: personal site required, network page doesn't count)
- `unclear` — never default to KEEP; check bio link manually

Pool status 2026-09-05: **70 qualified staged** across 5 niche files,
**31 verified (22 KEEP + 9 KEEP-weak)**. CSV dedupe is exact username-field match
(`awk -F, '$3==u'`) — never `grep ",$u,"` (regex dots false-match the keyword column).

Why keyword packs, not big limits: **IG returns ~5 users per query no matter
`--limit`.** Scale via wording×city variations + glued tokens (`barberlille`)
+ follower expansion (`EXPAND=1`, auto-pauses on 429).

## Safety (France/GDPR)

- `opencli instagram` = search/profile/user only. Never connect password-based bots.
- First DM: no link, <400 chars, specific problem, end with `Répondez STOP si non concerné`.
- B2B pro accounts only, honor STOP in 24h, keep logs 90 days.

## Deps (2026-09-05, this machine)

- `agent-reach` v1.5.0 in `./.venv/bin/` (`run.sh` prepends it to PATH; bare `agent-reach` is NOT on PATH)
- `opencli` v1.8.7 via nvm node v24.15.0; daemon on :19825; extension v1.0.24, profile `m4kfxxv4`
- `opencli instagram profile` ≈ permanently HTTP 429; `user` returns HTML login wall — `run.sh` already degrades around both

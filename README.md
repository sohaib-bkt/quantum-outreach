# quantum-outreach

Semi-auto Instagram prospecting for quantum.web.space. FRANCE focus (GDPR).

## Where things live (so you can close the terminal)

- Logic: `~/quantum-outreach/` (this folder — persists after close)
- Temp per run: `/tmp/quantum-KEYWORD-DATE.yaml`
- Persistent leads: `~/.agent-reach/quantum-prospects.csv`
- Reopen: `cd ~/quantum-outreach && ls` then `./run.sh "your keyword"`

## Use (keyword first)

```bash
./run.sh "restaurant paris" 20
./run.sh "clinique dentaire lyon" 20
./run.sh "ecommerce france" 20
./run.sh "centre d'appel casablanca" 20
./run.sh "assurance paris" 20
```

Flow: search (read-only) -> pick 5-10 usernames -> I enrich profile + draft FR message -> YOU send manually (10-15/hour, 20-30/day, vary).

## Safety

- `opencli instagram` = search/profile/user only. No auto-DM. Never connect password-based bots.
- First DM: no link, <400 chars, specific problem, include `Répondez STOP si non concerné`.
- France/GDPR: B2B pro accounts only, honor STOP in 24h, keep logs 90 days.

## Deps status in this terminal (2026-09-04)

- agent-reach: NOT FOUND here (you have it elsewhere — run `agent-reach doctor --json` there)
- opencli: NOT FOUND here
- Have: python3 3.12, node 24, yt-dlp
- Install here when ready: `pipx install https://github.com/Panniantong/agent-reach/archive/main.zip`

## Niches

See `niches/` — one file per vertical with what problem to look for + message angle.

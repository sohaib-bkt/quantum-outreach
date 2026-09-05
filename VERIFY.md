# VERIFY.md — site-verification rules (KEEP = no own site)

A prospect is KEEP **only** after ALL checks pass. One miss = OUT or unclear.
Order matters: cheapest signals first.

## The 4 checks (all required for KEEP)

1. **IG bio link**: open `instagram.com/<user>/` (logged-in browser).
   Open the bio link. `linktr.ee` / `beacons.ai` / `link bio` page = NO SITE (KEEP-leaning).
   Any `*.fr / *.com / *.ma` business domain = OUT.
2. **Google `"<business name>" <city>`** (exact name from IG, not username):
   standalone domain in results = OUT — even if the site is ugly or Wix.
3. **Google `"<username>"`** catches link-in-bio pages and Planity/Booksy/Kalendes.
4. **Franchise/network test**: name matches a network (L'Onglerie, Hemera, Vilains,
   Junot, Century 21, Efficity page only)? Parent domain = OUT, **except**
   mandataires (Efficity/IAD/SAFTI agents) whose only page is the network profile:
   those are KEEP (pitch: site à votre nom).

## Verdict ladder (write exactly this into CSV `problem_found`)

- `OUT has <domain>` — standalone site found. Never pitch.
- `OUT <network> group` — franchise/network site. Never pitch.
- `unclear site - verify bio link manually` — conflicting signals. Do NOT draft
  until bio link is opened. Never default to KEEP.
- `KEEP-weak <reason>` — Planity/Booksy/Kalendes-only or <10 posts.
  Draft only if pool is thin; angle = résa directe (stop commissions).
- `KEEP <facts>` — no site anywhere: directories only (PagesJaunes/Planity
  listings), booking via DM/MP, or nothing. Draft.

## Common traps (learned the hard way)

- "Prise de rdv via notre site" in a post often means a **Planity/Kalendes page**,
  not a site. Open it before calling OUT.
- Same-name businesses in other cities/countries (e.g. Maxime Coiffure Canada).
  Match city + IG handle before calling OUT.
- `*.fr` result that is a **directory profile** (PagesJaunes, Fresha, Yelp) = not a site.
- Competitor-built sites (e.g. danohys.fr by IKONIK) = OUT, and never pitch.
- New accounts (<10 posts, e.g. pre-opening shops) are KEEP only with an
  opening-soon or wedding/event angle — otherwise park as `unclear`.

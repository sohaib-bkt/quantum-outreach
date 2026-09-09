"""Shared parsers for run.sh: recency + bio site pre-filter.

- newest_post_age_days(yaml_text, now=None) -> int | None
  Age in days of the newest parseable `date:` value in `opencli instagram
  user -f yaml` output. None = no parseable date (unverifiable).
- classify_bio(bio) -> (kind, domain)
  kind: 'standalone' (own site -> OUT), 'booking' (Planity/Booksy/Kalendes/
  Fresha/Treatwell only -> KEEP-weak angle), 'neutral' (aggregator/DM/nothing).
"""
import re
from datetime import datetime, timezone

BOOKING_HOSTS = (
    "planity.", "booksy.", "kalendes.", "fresha.", "treatwell.",
    "reservio.", "planfy.", "leguidedesce.",
)
AGGREGATORS = (
    "linktr.ee", "beacons.ai", "bio.site", "solo.to", "taplink.",
    "linkin.bio", "lnk.bio", "campsite.bio", "snipfeed.co",
)
SOCIAL_NOISE = (
    "instagram.com", "facebook.com", "fb.com", "tiktok.com", "youtube.com",
    "wa.me", "whatsapp.", "maps.google", "goo.gl", "bit.ly", "tinyurl.",
)
DOMAIN_RE = re.compile(r"(?:https?://|www\.)?([a-z0-9][a-z0-9.-]*\.[a-z]{2,})(?:[/\s:'\"]|$)", re.I)

_REL_RE = re.compile(
    r"il y a\s+(\d+)\s*(jour|heure|semaine|mois|an)|"
    r"(\d+)\s*(second|minute|hour|day|week|month|year)s?\s*ago|"
    r"(\d+)\s*([smhdwy])\b", re.I)


def _parse_one(raw):
    s = raw.strip().strip("'\"")
    if not s or s.lower() in ("none", "null", "~", "-"):
        return None
    now = datetime.now(timezone.utc)
    m = _REL_RE.search(s)
    if m:
        if m.group(1):
            n, unit = int(m.group(1)), m.group(2).lower()
            days = {"jour": 1, "heure": 0, "semaine": 7, "mois": 30, "an": 365}[unit]
            return now - __import__("datetime").timedelta(days=n * days)
        n = int(m.group(3) or m.group(5))
        unit = (m.group(4) or m.group(6)).lower()
        mult = {"second": 0, "minute": 0, "hour": 0, "day": 1, "week": 7,
                "month": 30, "year": 365, "s": 0, "m": 0, "h": 0, "d": 1,
                "w": 7, "y": 365}[unit]
        return now - __import__("datetime").timedelta(days=n * mult)
    if re.fullmatch(r"\d{10}(\d{3})?", s):
        v = int(s)
        if len(s) == 13:
            v //= 1000
        return datetime.fromtimestamp(v, timezone.utc)
    try:
        d = datetime.fromisoformat(s.replace("Z", "+00:00"))
        return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
    except ValueError:
        pass
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d", "%d/%m/%Y", "%d.%m.%Y"):
        try:
            return datetime.strptime(s[:19], fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def newest_post_age_days(yaml_text, now=None):
    """Days since newest parseable post date; None if none parseable."""
    now = now or datetime.now(timezone.utc)
    best = None
    for m in re.finditer(r"(?m)^\s*(?:-\s*)?date:\s*(.+)$", yaml_text):
        dt = _parse_one(m.group(1))
        if dt and (best is None or dt > best):
            best = dt
    if best is None:
        return None
    return max(0, (now - best).days)


def classify_bio(bio):
    """(kind, domain) site pre-filter for a profile bio string."""
    domains = []
    for m in DOMAIN_RE.finditer(bio or ""):
        d = m.group(1).lower().rstrip(".")
        if d not in domains:
            domains.append(d)
    booking, standalone = None, None
    for d in domains:
        if any(n in d for n in SOCIAL_NOISE) or any(a in d for a in AGGREGATORS):
            continue
        if any(b in d for b in BOOKING_HOSTS):
            booking = booking or d
        elif "." in d:
            standalone = standalone or d
    if standalone:
        return ("standalone", standalone)
    if booking:
        return ("booking", booking)
    return ("neutral", None)

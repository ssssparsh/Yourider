#!/usr/bin/env python3
"""KNOWLEDGE-SYSTEM-DESIGN.md §3.7c confidence decay sweep.

Scans knowledge-vault/library/**/*.md, computes each entry's current
confidence per the per-entry decay formula, and reports what would change.

    baseline   = last_decayed_at OR last_reinforced_at OR created_date
    weeks      = (now - baseline) / 1 week
    decay      = decay_rate * weeks
    confidence = max(CONFIDENCE_FLOOR, confidence - decay)

Dry-run by default (CHARTER.md §5 — reversibility by default; a mistake
here costs nothing until it's applied). Pass --apply to actually rewrite
frontmatter. Never removes an entry from disk or from the library, and
never lowers a status below its current lifecycle stage — decay only ever
touches confidence_level / confidence_decay_factor / age_category, per
§3.7's "decay never removes from recall" rule.

Usage:
    python3 scripts/decay_sweep.py                 # report only
    python3 scripts/decay_sweep.py --apply          # write the changes
    python3 scripts/decay_sweep.py --domain=engineering
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml

CONFIDENCE_FLOOR = 0.5
DEFAULT_DECAY_RATE_PER_WEEK = 0.02  # ~1.0 -> floor over ~25 weeks unreinforced
VAULT_ROOT = Path(__file__).resolve().parent.parent / "knowledge-vault" / "library"


def _parse_frontmatter(path: Path) -> tuple[dict, str] | None:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return None
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None
    try:
        meta = yaml.safe_load(parts[1]) or {}
    except yaml.YAMLError as exc:
        print(f"  ! could not parse frontmatter in {path}: {exc}", file=sys.stderr)
        return None
    body = parts[2]
    return meta, body


def _parse_dt(value) -> datetime | None:
    if not value:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def compute_decay(meta: dict, now: datetime) -> tuple[float, str]:
    """Return (new_confidence_decay_factor, note)."""
    baseline = (
        _parse_dt(meta.get("last_decayed_at"))
        or _parse_dt(meta.get("last_reinforced_at"))
        or _parse_dt(meta.get("last_re_verified_date"))
        or _parse_dt(meta.get("created_date"))
    )
    if baseline is None:
        return 1.0, "no baseline date found; leaving confidence untouched"

    weeks = max((now - baseline).total_seconds() / (7 * 24 * 3600), 0.0)
    decay_rate = meta.get("decay_rate", DEFAULT_DECAY_RATE_PER_WEEK)
    current = meta.get("confidence_decay_factor", 1.0)
    decay = decay_rate * weeks
    new_confidence = max(CONFIDENCE_FLOOR, current - decay)
    note = f"{weeks:.4f} weeks since baseline, decay_rate={decay_rate} -> {current:.6f} -> {new_confidence:.6f}"
    return new_confidence, note


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="write changes (default: dry-run report only)")
    parser.add_argument("--domain", default=None, help="restrict to one domain directory")
    args = parser.parse_args()

    if not VAULT_ROOT.exists():
        print(f"No knowledge vault found at {VAULT_ROOT}", file=sys.stderr)
        return 1

    now = datetime.now(timezone.utc)
    entries = sorted(VAULT_ROOT.rglob("*.md"))
    if args.domain:
        entries = [e for e in entries if f"/{args.domain}/" in str(e)]

    if not entries:
        print("No knowledge entries found.")
        return 0

    changed = 0
    for path in entries:
        parsed = _parse_frontmatter(path)
        if parsed is None:
            print(f"  ! skipping {path} — no valid YAML frontmatter")
            continue
        meta, body = parsed
        new_confidence, note = compute_decay(meta, now)
        old_confidence = meta.get("confidence_decay_factor", 1.0)
        marker = "would change" if not args.apply else "changed"
        # Compare at the same precision actually persisted (4 decimals), so
        # the report never claims a change that rounding would then erase.
        if round(new_confidence, 4) != round(float(old_confidence), 4):
            changed += 1
            print(f"[{marker}] {path.relative_to(VAULT_ROOT.parent.parent)}: {note}")
            if new_confidence <= CONFIDENCE_FLOOR + 1e-9:
                print(f"           at/below floor ({CONFIDENCE_FLOOR}) — status stays as-is, age_category -> aging_unverified")
            if args.apply:
                meta["confidence_decay_factor"] = round(new_confidence, 4)
                meta["last_decayed_at"] = now.isoformat()
                if new_confidence <= CONFIDENCE_FLOOR + 1e-9:
                    meta["age_category"] = "aging_unverified"
                new_frontmatter = yaml.safe_dump(meta, sort_keys=False, allow_unicode=True)
                path.write_text(f"---\n{new_frontmatter}---{body}", encoding="utf-8")
        else:
            print(f"[unchanged] {path.relative_to(VAULT_ROOT.parent.parent)}: {note}")

    print(f"\n{changed} of {len(entries)} entries {'changed' if args.apply else 'would change'}.")
    if not args.apply and changed:
        print("Dry run only — pass --apply to write these changes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

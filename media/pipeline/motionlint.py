"""Motion gate for a built HyperFrames/GSAP composition (Emil Kowalski's animation standards, adapted to video).

usage: python3 media/pipeline/motionlint.py <index.html> [--exceptions script.json]

FAIL  scale-from-zero entrances (start at 0.9-0.97 with opacity instead)
FAIL  linear / "none" easing on a tween (speed comes from acceleration; shotcraft R2)
FAIL  tweening layout properties (left, top, width, height, margin, padding): transform and opacity only
WARN  ease-in on an entrance (right only for a slam into an impact)
WARN  4+ entrances starting on the same frame with the same ease and no stagger (everything-at-once)
Exceptions: script.json "motion_exceptions": {"<selector glob>": "reason"}; each use is printed.
Parses tl./gsap./any-timeline .to/.from/.fromTo with string selectors (any quote style).
Not covered: Remotion (interpolate/spring) and Lemo-Opuscar timelines; review those by eye.
Exits 1 on any FAIL.
"""
import argparse
import fnmatch
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

CALL = re.compile(r'\b[A-Za-z_$][\w$]*\.(fromTo|from|to)\(\s*(["\'`])(.+?)\2\s*,\s*(\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\})(?:\s*,\s*(\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}))?(?:\s*,\s*([-0-9.]+|"[^"]*"|\'[^\']*\'))?\s*\)')
LAYOUT = re.compile(r'\b(left|top|right|bottom|width|height|margin\w*|padding\w*)\s*:')
EASE = re.compile(r'ease:\s*(?:S\()?["\']([^"\']+)["\']')
ZERO = r"\bscale:\s*[\"']?0+(?:\.0+)?[\"']?\s*[,}]"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("html")
    ap.add_argument("--exceptions")
    a = ap.parse_args()
    src = Path(a.html).read_text()
    exc = json.loads(Path(a.exceptions).read_text()).get("motion_exceptions", {}) if a.exceptions else {}
    fails, warns, used = [], [], set()

    def excused(sel: str) -> bool:
        for pat in exc:
            if fnmatch.fnmatch(sel, pat):
                used.add(pat)
                return True
        return False

    starts = defaultdict(list)
    n = 0
    for m in CALL.finditer(src):
        n += 1
        kind, sel, v1, v2 = m.group(1), m.group(3), m.group(4), m.group(5)
        try:
            t = float(m.group(6))
        except (TypeError, ValueError):
            t = 0.0  # no position or a label: reported at 0
        frm = v1 if kind in ("from", "fromTo") else ""
        to = v2 if kind == "fromTo" else v1
        ease_m = EASE.search(to or "") or EASE.search(v1)
        ease = ease_m.group(1) if ease_m else ""
        entrance = kind == "from" or (kind == "fromTo" and re.search(r"opacity:\s*0[,}\s]|scale:\s*0?\.\d|scale:\s*0[,}\s]|[xy]:\s*-?\d", frm))
        where = f"{sel} @ {t:.2f}s"
        if excused(sel):
            continue
        if re.search(ZERO, frm):
            fails.append(f"scale-from-zero entrance {where}: start at scale 0.9-0.97 with opacity")
        if ease in ("none", "linear", "Linear.easeNone", "power0", "power0.none"):
            fails.append(f"linear easing {where}: use an ease-out")
        if entrance and re.fullmatch(r"(power\d|expo|circ|sine|quad|cubic|quart|quint)\.in", ease):
            warns.append(f"ease-in on an entrance {where} ({ease}): right only for a slam into an impact; otherwise ease out")
        for vars_ in (frm, to):
            for prop in LAYOUT.findall(vars_ or ""):
                fails.append(f"layout property '{prop}' tweened {where}: animate transform/opacity only")
        if entrance:
            starts[(round(t * 30), ease)].append(sel)
    for (f, ease), sels in starts.items():
        if len(sels) >= 4:
            warns.append(f"{len(sels)} entrances on frame {f} ({f / 30:.2f}s) with '{ease}' and no stagger: {', '.join(sels[:4])}...")

    print(f"INFO {n} tweens checked in {a.html}")
    for pat in sorted(used):
        print(f"INFO exception used: {pat}: {exc[pat]}")
    for w in warns:
        print("WARN " + w)
    for f in fails[:40]:
        print("FAIL " + f)
    if len(fails) > 40:
        print(f"FAIL ... and {len(fails) - 40} more")
    print(f"RESULT {'PASS' if not fails else f'FAIL ({len(fails)})'}" + (f", {len(warns)} warning(s)" if warns else ""))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()

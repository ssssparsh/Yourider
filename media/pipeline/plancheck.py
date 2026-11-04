"""Plan gate: catch slop and plan mistakes in script.json BEFORE anything is built. Exit 1 on any FAIL.

usage: python3 media/pipeline/plancheck.py <project_dir>

Reads <project_dir>/script.json (and FACTS.md when present). Checks:
  copy  (blader/humanizer patterns, applied to every spoken line and every on_screen string):
        overused AI words, sales language, "not X but Y" staging, dashes as connectors, curly quotes,
        chatbot residue, repeated sentence openings, one- or two-word dramatic fragments (warn)
  plan  headline repeating a caption (unless the line has "plate": false, i.e. the word sync runs inside
        the headline), speaking rate, gaps between lines, lines past the end, numbers not in FACTS.md,
        and every rule in media/LEARNINGS.md marked `check:` (substring checks on copy)
Prints PASS/WARN/FAIL lines and RESULT. WARN does not fail; FAIL does.
"""
import difflib
import json
import re
import sys
from pathlib import Path

# blader/humanizer SKILL.md §12 (overused AI words) and §16 (sales language), checked 2026-11-04
AI_WORDS = ["additionally", "bolstered", "crucial", "deep dive", "delve", "garner", "interplay", "intricate",
            "intricacies", "meticulous", "meticulously", "pivotal", "showcase", "tapestry", "testament", "underscore",
            "vibrant"]
# same list, but words people also use normally ("I recorded it in landscape"): warn, a person decides
AI_WORDS_SOFT = ["actually", "align with", "enduring", "enhance", "landscape", "quietly", "valuable"]
# SaaS-marketing filler (our addition, not from humanizer): FAIL hard ones, WARN vague adjectives
BUZZ = ["streamline", "leverage", "harness", "robust", "next-gen", "all-in-one", "game-changing", "reimagine",
        "redefine", "one-stop", "best-in-class", "deserves better", "here's the thing", "here is the thing"]
BUZZ_SOFT = ["powerful", "intuitive", "smart", "simple", "easy", "magic", "magical"]
SALES = ["game-changer", "game changer", "revolutionize", "revolutionise", "seamless", "seamlessly", "supercharge",
         "unlock", "unleash", "effortless", "effortlessly", "next-level", "cutting-edge", "world-class",
         "transform your", "elevate your", "empower", "the future of"]
STAGING = [r"\bnot (just|only|merely)\b", r"\b(is|are)n'?t (just|only|merely)\b", r"\bmore than (just|a|an)\b",
           r"\bno \w+\.\s+(no \w+\.\s+)*just\b", r"\bit'?s not\b[^.]*\bit'?s\b", r"\bnot\b[^.,]{1,40}\bbut\b", r"\brather than\b"]
RESIDUE = ["i hope this", "let me know", "as an ai", "certainly!", "great question", "in conclusion", "in summary"]

fails: list[str] = []
warns: list[str] = []


def fail(msg: str) -> None:
    fails.append(msg)
    print("FAIL " + msg)


def warn(msg: str) -> None:
    warns.append(msg)
    print("WARN " + msg)


NUMWORDS = {"zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7",
            "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12", "twenty": "20", "thirty": "30"}


def norm(s: str) -> str:
    out = re.sub(r"[^a-z0-9 ]", " ", s.lower().replace("/", " "))
    return " ".join(NUMWORDS.get(w, w) for w in out.split())


def sentences(t: str) -> list[str]:
    return [x for x in (norm(p) for p in re.split(r"(?<=[.!?:])\s+", t.replace("/", " "))) if x]


def strings(v) -> list[str]:
    """every string inside an on_screen value (lists and objects too)"""
    if isinstance(v, str):
        return [v]
    if isinstance(v, list):
        return [s for x in v for s in strings(x)]
    if isinstance(v, dict):
        return [s for x in v.values() for s in strings(x)]
    return []


def copy_checks(label: str, text: str) -> None:
    low = text.lower()
    for w in AI_WORDS:
        if re.search(rf"\b{re.escape(w)}\b", low):
            fail(f"{label}: overused AI word '{w}' (humanizer §12): \"{text}\"")
    for w in AI_WORDS_SOFT + BUZZ_SOFT:
        if re.search(rf"\b{re.escape(w)}\b", low):
            warn(f"{label}: '{w}' is often filler; keep only if it states something concrete: \"{text}\"")
    for w in BUZZ:
        if w in low:
            fail(f"{label}: marketing filler '{w}': say what it does instead: \"{text}\"")
    # forced triad by repetition: "built for X, built for Y, built for Z"
    toks = norm(text).split()
    grams = [" ".join(toks[i:i + 2]) for i in range(len(toks) - 1)]
    for g in set(grams):
        if grams.count(g) >= 3:
            fail(f"{label}: forced triad, '{g}' repeated {grams.count(g)}x (humanizer §10): \"{text}\"")
    for w in SALES:
        if w in low:
            fail(f"{label}: sales language '{w}' (humanizer §16): \"{text}\"")
    for pat in STAGING:
        if re.search(pat, low):
            fail(f"{label}: 'not X but Y' staging (humanizer §1): \"{text}\"")
            break
    for r in RESIDUE:
        if r in low:
            fail(f"{label}: chatbot residue '{r}' (humanizer §22): \"{text}\"")
    if re.search(r"\s[—–-]\s|—|–", text):
        fail(f"{label}: dash used as a connector (humanizer §8): \"{text}\"")
    if re.search(r"[“”‘’]", text):
        fail(f"{label}: curly quotes (humanizer §21): \"{text}\"")
    for s in re.split(r"(?<=[.!?])\s+", text.strip()):
        words = [w for w in norm(s).split() if w]
        if 0 < len(words) <= 2 and s.strip().endswith("."):
            warn(f"{label}: dramatic fragment \"{s.strip()}\" (humanizer §2); keep only if it carries a fact")


def main() -> None:
    proj = Path(sys.argv[1])
    spec = json.loads((proj / "script.json").read_text())
    lines, dur = spec["lines"], spec["duration"]
    on_screen = {f"{k}[{i}]" if len(strings(v)) > 1 else k: t for k, v in spec.get("on_screen", {}).items()
                 if not k.startswith("_") for i, t in enumerate(strings(v))}
    if not on_screen:
        warn("script.json has no on_screen texts: headline/caption duplication and copy checks on screen text skipped")

    # copy
    for ln in lines:
        copy_checks(ln["id"], ln["show"])
    for k, v in on_screen.items():
        copy_checks(k, v.replace("/", " "))
    opens = [norm(ln["show"]).split()[0] for ln in lines if norm(ln["show"])]
    for w in set(opens):
        if opens.count(w) >= 3 and w not in ("the", "a"):
            warn(f"{opens.count(w)} lines open with '{w}' (humanizer §7: repeated openings)")

    # headline repeating a caption: the same sentence twice on screen, in two typefaces
    for k, v in on_screen.items():
        if "headline" not in k.lower():
            continue
        h = norm(v)
        for ln in lines:
            cand = [norm(ln["show"])] + sentences(ln["show"])
            r = max(difflib.SequenceMatcher(a=h, b=c).ratio() for c in cand)
            contained = len(h.split()) >= 3 and f" {h} " in f" {norm(ln['show'])} "
            if (r >= 0.75 or contained) and ln.get("plate", True):
                fail(f"{k} repeats caption {ln['id']} ({r:.2f}): \"{v}\" vs \"{ln['show']}\"; sync inside the headline "
                     f"(set \"plate\": false on {ln['id']}) or rewrite the headline to add information")

    # timing estimates (Kokoro speaks ~3 words/s measured; voice.py enforces the exact gaps with real audio)
    for a, b in zip(lines, lines[1:]):
        est = a["start"] + len(a["say"].split()) / 3.0
        if est + 0.3 > b["start"]:
            warn(f"{a['id']} may run to ~{est:.1f}s, close to {b['id']} at {b['start']:.1f}s (voice.py will measure)")
    last = lines[-1]
    if last["start"] + len(last["say"].split()) / 3.0 > dur - 1.0:
        fail(f"{last['id']} likely ends after {dur - 1.0:.1f}s: no room for the end hold")
    total = sum(len(ln["say"].split()) for ln in lines)
    rate = total / dur
    (fail if rate > 2.6 else (warn if rate > 2.3 else lambda m: print("PASS " + m)))(f"{total} words in {dur:.0f}s = {rate:.2f} words/s (max 2.6)")

    # facts: every number on screen or spoken must appear in FACTS.md
    facts_p = proj / "FACTS.md"
    if facts_p.exists():
        facts = facts_p.read_text().lower()
        texts = [(ln["id"], ln["show"]) for ln in lines] + list(on_screen.items())
        for label, t in texts:
            for n in re.findall(r"\d+(?:\.\d+)?", t):
                if n not in facts:
                    fail(f"{label}: number {n} is not in FACTS.md: \"{t}\"")
    else:
        warn("no FACTS.md: claims are not checked against a fact sheet")

    # learned rules (media/LEARNINGS.md lines like: - check: phrase | reason)
    learn = Path(__file__).resolve().parents[1] / "LEARNINGS.md"
    if learn.exists():
        for m in re.finditer(r"^- check: (.+?) \| (.+)$", learn.read_text(), re.M):
            phrase, why = m.group(1).strip().lower(), m.group(2).strip()
            for label, t in [(ln["id"], ln["show"]) for ln in lines] + list(on_screen.items()):
                if phrase in t.lower():
                    fail(f"{label}: learned rule '{phrase}': {why}")

    print(f"RESULT {'PASS' if not fails else f'FAIL ({len(fails)})'}" + (f", {len(warns)} warning(s)" if warns else ""))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()

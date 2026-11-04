"""HyperFrames composition for the collage shot (1920x1080).

usage: python gen.py <project_dir> <build_dir>   -> <build_dir>/hf/index.html, timed from <build_dir>/words.json
"""
import html
import json
import sys
from pathlib import Path

PROJECT, BUILD = Path(sys.argv[1]), Path(sys.argv[2])
words = json.loads((BUILD / "words.json").read_text())
DUR = json.loads((PROJECT / "script.json").read_text())["duration"]
# the stamp lands on the spoken word "handshake", wherever the chosen voice take puts it
_ALL = [w for ln in words.values() for w in ln["words"]]
LAND = next(w["t0"] for w in _ALL if w["w"].lower().strip(".,!?") == "handshake") + .02
INK, RED, CREAM = "#26241F", "#E3002B", "#F6F1E4"

caps, tw = [], []
for li, (lid, ln) in enumerate(words.items()):
    spans = " ".join(f'<span class="w" id="c{li}_{j}">{html.escape(w["w"])}</span>' for j, w in enumerate(ln["words"]))
    a, b = ln["start"] - .15, ln["start"] + ln["dur"] + .35
    caps.append(f'<div id="cap{li}" class="clip cap" data-start="{a:.2f}" data-duration="{b - a:.2f}" data-track-index="5"><div class="plate"><i></i>{spans}</div></div>')
    tw.append(f'tl.from("#cap{li} .plate", {{y: 40, opacity: 0, duration: .3, ease: "power3.out"}}, {a:.2f});')
    for j, w in enumerate(ln["words"]):
        tw.append(f'tl.to("#c{li}_{j}", {{color: "{RED}", opacity: 1, duration: .1}}, {w["t0"]:.2f});')
        tw.append(f'tl.to("#c{li}_{j}", {{color: "{INK}", duration: .15}}, {w["t1"] + .02:.2f});')

doc = f'''<!doctype html>
<html lang="en" data-resolution="landscape">
<head>
<meta charset="UTF-8" /><meta name="viewport" content="width=1920, height=1080" />
<script src="gsap.min.js"></script>
<style>
@font-face{{font-family:Inter;src:url(Inter.woff2) format('woff2');font-weight:100 900}}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:1920px;height:1080px;overflow:hidden;background:#B8432F;font-family:Inter,sans-serif}}
.abs{{position:absolute}}
.shadow{{filter:drop-shadow(0 18px 22px rgba(58,48,32,.28)) drop-shadow(0 3px 4px rgba(58,48,32,.18))}}
#field{{position:absolute;inset:0;background:url(field.png)}}
.cap{{position:absolute;left:0;right:0;bottom:46px;display:flex;justify-content:center}}
.plate{{background:rgba(246,241,228,.96);border-radius:44px;padding:16px 40px 18px 34px;font-weight:700;font-size:46px;color:{INK};
  box-shadow:0 14px 24px rgba(58,48,32,.25);display:flex;gap:13px;align-items:center}}
.plate i{{width:14px;height:14px;border-radius:50%;background:{RED};display:inline-block;margin-right:6px}}
.w{{opacity:.38}}
.stampin{{width:300px;height:300px;border-radius:50%;background:{RED};color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;
  border:8px solid #fff;box-shadow:0 0 0 5px {RED};font-weight:900;letter-spacing:3px;text-align:center}}
.stampin b{{font-size:54px;line-height:1}} .stampin span{{font-size:20px;letter-spacing:6px;margin-top:10px;opacity:.9}}
.brandin{{width:100%;height:100%;display:flex;align-items:center;justify-content:center;color:{CREAM};font-weight:900;font-size:64px;letter-spacing:-1px}}
.brandin em{{color:{RED};font-style:normal}}
</style>
</head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-duration="{DUR}" data-width="1920" data-height="1080">
  <audio id="mix" src="mix.wav" data-start="0" data-duration="{DUR}" data-track-index="9" data-volume="1"></audio>
  <div id="field" class="clip" data-start="0" data-duration="{DUR}" data-track-index="0"></div>
  <div id="card" class="clip abs shadow" data-start="0" data-duration="{DUR}" data-track-index="1" style="left:350px;top:70px;width:1220px;height:800px"><img src="card.png" style="width:100%;height:100%"></div>
  <div id="map" class="clip abs shadow" data-start="0.4" data-duration="{DUR - .4:.2f}" data-track-index="2" style="left:250px;top:95px;width:600px;height:340px">
    <img src="mapcard.png" style="position:absolute;inset:0;width:100%;height:100%">
    <svg width="600" height="340" viewBox="0 0 600 340" style="position:absolute;inset:0">
      <text x="48" y="74" font-family="Inter" font-weight="800" font-size="26" fill="{INK}" letter-spacing="3">THE DEAL ROUTE</text>
      <path id="route" d="M60 250 L220 250 L320 150 L540 150" fill="none" stroke="{RED}" stroke-width="14" stroke-linecap="round" stroke-linejoin="round" pathLength="1" stroke-dasharray="1" stroke-dashoffset="1"/>
      <circle id="st0" cx="60" cy="250" r="12" fill="#fff" stroke="{RED}" stroke-width="7"/>
      <circle id="st1" cx="220" cy="250" r="12" fill="#fff" stroke="{RED}" stroke-width="7"/>
      <circle id="st2" cx="320" cy="150" r="12" fill="#fff" stroke="{RED}" stroke-width="7"/>
      <circle id="st3" cx="540" cy="150" r="20" fill="#fff" stroke="{INK}" stroke-width="7"/>
      <text id="lb3" x="548" y="112" text-anchor="end" font-family="Inter" font-weight="700" font-size="24" fill="{INK}">Closed Won</text>
    </svg>
  </div>
  <div id="hands" class="clip abs shadow" data-start="0.9" data-duration="{DUR - .9:.2f}" data-track-index="3" style="left:180px;top:290px;width:1560px"><img src="handshake-ht.png" style="width:100%"></div>
  <div id="stamp" class="clip abs" data-start="{LAND - .24:.2f}" data-duration="{DUR - LAND + .24:.2f}" data-track-index="4" style="left:1330px;top:90px;width:300px;height:300px">
    <div class="stampin" id="stampin"><b>CLOSED<br>WON</b><span>YOURIDER</span></div></div>
  <div id="brand" class="clip abs shadow" data-start="3.55" data-duration="{DUR - 3.55:.2f}" data-track-index="6" style="left:1380px;top:740px;width:470px;height:150px">
    <img src="brand.png" style="position:absolute;inset:0;width:100%;height:100%"><div class="brandin" style="position:absolute;inset:0">Your<em>ider</em></div></div>
  {"".join(caps)}
</div>
<script>
const tl = gsap.timeline({{ paused: true }});
tl.from("#card img", {{scale: 1.18, rotation: -7, opacity: 0, duration: .45, ease: "back.out(1.6)", transformOrigin: "50% 50%"}}, 0.0);
tl.to("#card img", {{rotation: -1.5, duration: .01}}, 0.46);
tl.from("#map", {{x: -260, y: -90, rotation: -14, opacity: 0, duration: .45, ease: "power3.out"}}, 0.4);
tl.set("#map", {{rotation: -3}}, 0.86);
tl.to("#route", {{strokeDashoffset: 0, duration: 1.1, ease: "power1.inOut"}}, 0.85);
["#st0", "#st1", "#st2"].forEach((s, i) => tl.from(s, {{attr: {{r: 0}}, duration: .25, ease: "back.out(3)"}}, [0.86, 1.1, 1.45][i]));
tl.from("#st3", {{attr: {{r: 0}}, duration: .3, ease: "back.out(3)"}}, 1.85);
tl.from("#lb3", {{opacity: 0, y: 10, duration: .3}}, 1.9);
tl.from("#hands", {{y: 520, rotation: 5, duration: .8, ease: "power3.out"}}, 0.9);
tl.to("#hands", {{y: -6, duration: .12, ease: "power1.out"}}, 1.7);
tl.to("#hands", {{y: 0, duration: .2, ease: "power1.in"}}, 1.82);
tl.from("#stampin", {{scale: 2.6, rotation: -40, opacity: 0, duration: .22, ease: "power4.in"}}, {LAND - .22:.2f});
tl.to("#stampin", {{rotation: -12, duration: .01}}, {LAND + .01:.2f});
tl.to("#stampin", {{scale: 1.06, duration: .08, yoyo: true, repeat: 1}}, {LAND + .01:.2f});
tl.from("#brand", {{x: 520, rotation: 9, duration: .55, ease: "back.out(1.4)"}}, 3.55);
tl.to("#hands", {{scale: 1.03, duration: {DUR - 2.2:.2f}, ease: "none", transformOrigin: "50% 60%"}}, 2.2);
{chr(10).join(tw)}
window.__timelines["main"] = tl;
</script>
</body>
</html>
'''
(BUILD / "hf" / "index.html").write_text(doc)
print("ok")

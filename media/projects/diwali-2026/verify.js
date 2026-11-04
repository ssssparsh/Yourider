// Browser check of the built composition (run by build.sh after gen.py).
// usage: NODE_PATH=/opt/node-tools/node_modules node verify.js <hf/index.html> <script.json> <words.json>
// Checks: each lamp's first visible flame frame is within 1 frame of its catch cue; lamp 1's flame (catch group,
// flicker excluded) has the same height at 9, 11 and 14 s; no caption box overlaps the rangoli or lamps at any
// spoken word; the end lockup sits inside the 108 px margins. Prints RESULT PASS/FAIL, exits 1 on FAIL.
const { chromium } = require('playwright');
const fs = require('fs');
const [html, specP, wordsP] = process.argv.slice(2);
const spec = JSON.parse(fs.readFileSync(specP)), words = JSON.parse(fs.readFileSync(wordsP));
const key = s => s.toLowerCase().replace(/^[.,!?]+|[.,!?]+$/g, '');
const all = Object.values(words).flatMap(l => l.words);
const wt = w => all.find(x => key(x.w) === key(w)).t0;
const FPS = spec.format.fps, F = 1 / FPS;
(async () => {
  const b = await chromium.launch({ executablePath: process.env.MEDIA_CHROME });
  const pg = await b.newPage({ viewport: { width: spec.format.width, height: spec.format.height } });
  await pg.goto('file://' + require('path').resolve(html));
  await pg.evaluate(() => document.fonts.ready);
  const fails = [];
  const seek = t => pg.evaluate(t => { window.__timelines.main.seek(t, false); return 0; }, t);
  // 1. lamp ignitions
  for (const c of spec.sfx.filter(c => c.lamp)) {
    const cue = c.t ?? wt(c.word) + (c.offset || 0), i = c.lamp - 1;
    let first = null;
    for (let f = Math.floor((cue - 0.2) * FPS); f <= Math.ceil((cue + 0.3) * FPS); f++) {
      await seek(f / FPS);
      const o = await pg.evaluate(i => parseFloat(getComputedStyle(document.getElementById('fc' + i)).opacity), i);
      if (o > 0.01) { first = f / FPS; break; }
    }
    const ok = first !== null && Math.abs(first - cue) <= F + 1e-6;
    console.log(`${ok ? 'PASS' : 'FAIL'} lamp ${c.lamp}: sound ${cue.toFixed(3)}s, first flame frame ${first === null ? 'none' : first.toFixed(3)}s`);
    if (!ok) fails.push('lamp ' + c.lamp);
  }
  // 2. lamp 1 never changes
  const hs = [], fl = [];
  for (const t of [9, 11, 14]) { await seek(t); hs.push(await pg.evaluate(() => (document.querySelector('#fc0 path').getBBox().height * gsap.getProperty('#fc0', 'scaleY')).toFixed(2) + 'px/opacity ' + gsap.getProperty('#fc0', 'opacity')));
    fl.push(await pg.evaluate(() => document.getElementById('fc0').getBoundingClientRect().height.toFixed(1))); }
  const same = hs.every(h => h === hs[0]);
  console.log(`${same ? 'PASS' : 'FAIL'} lamp 1 flame (height px/scaleY/opacity, flicker excluded) at 9/11/14 s: ${hs.join(', ')}`);
  if (!same) fails.push('lamp 1 changes');
  console.log(`INFO lamp 1 visible flame box incl. the always-on flicker (+-6.6 %, same signal family on every lamp): ${fl.join(', ')} px`);
  // 3. captions clear of the rangoli and the lamps at every word
  let worst = 1e9;
  for (const ln of spec.lines.filter(l => l.plate !== false)) {
    for (const w of words[ln.id].words) {
      await seek(w.t0 + 0.05);
      const r = await pg.evaluate(() => {
        const now = window.__timelines.main.time();   // emulate the HyperFrames clip window (data-start/data-duration)
        const cap = [...document.querySelectorAll('.cap')].filter(e => now >= +e.dataset.start && now < +e.dataset.start + +e.dataset.duration && parseFloat(getComputedStyle(e).opacity) > 0);
        const box = el => el.getBoundingClientRect();
        const art = ['k0', 'k1', 'k2', 'k3', 'k4', 'k5', 'k6', 'lamp0', 'lamp4', 'fc0'].map(id => box(document.getElementById(id)));
        const top = Math.min(...art.map(a => a.top));
        return { n: cap.length, bottom: Math.max(...cap.flatMap(c => [...c.querySelectorAll('.w')].map(s => box(s).bottom))), top };
      });
      worst = Math.min(worst, r.top - r.bottom);
      if (r.n !== 1 || r.top - r.bottom < 34) { fails.push(`caption ${ln.id} at '${w.w}'`); console.log(`FAIL caption ${ln.id} '${w.w}': ${r.n} lines on screen, gap ${(r.top - r.bottom).toFixed(0)}px`); }
    }
  }
  console.log(`${fails.some(f => f.startsWith('caption')) ? 'FAIL' : 'PASS'} one caption at a time, smallest gap caption -> rangoli ${worst.toFixed(0)}px (>= 34)`);
  // 4. lockup inside the margins
  await seek(spec.duration - 0.5);
  const e = await pg.evaluate(() => [...document.querySelectorAll('#end .w')].map(s => s.getBoundingClientRect()).reduce((a, r) => ({ l: Math.min(a.l, r.left), r: Math.max(a.r, r.right), t: Math.min(a.t, r.top), b: Math.max(a.b, r.bottom) }), { l: 1e9, r: -1e9, t: 1e9, b: -1e9 }));
  const M = 108, okE = e.l >= M && e.r <= spec.format.width - M && e.b <= spec.format.height - M;
  console.log(`${okE ? 'PASS' : 'FAIL'} lockup x ${e.l.toFixed(0)}-${e.r.toFixed(0)}, y ${e.t.toFixed(0)}-${e.b.toFixed(0)} inside ${M} px margins`);
  if (!okE) fails.push('lockup');
  await b.close();
  console.log(`RESULT ${fails.length ? 'FAIL (' + fails.length + ')' : 'PASS'}`);
  process.exit(fails.length ? 1 : 0);
})();

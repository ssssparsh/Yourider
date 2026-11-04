// Direction of "One Map" (Yourider): growth phases keyed to the narration, camera, printed furniture, captions, cues.
// Every station on the Lead line lights at the moment its name is spoken (word times from words.js, measured by Whisper).
import { clamp, lerp, seg, ss, eio, eo, back, hash } from '/core/lib.js';
import { WORDS } from './words.js';

const DUR = 33.5;
const W = v => v * 100;
const RED = '#E3002B', PAPER = 'rgba(242,238,229,.94)';

// ------------------------------------------------------------------ growth phases
// every arrival is anchored to the spoken word, so a different voice take never breaks the sync
const ALLW = Object.values(WORDS).flatMap(l => l.words);
const key = s => s.toLowerCase().replace(/[^a-z0-9-]/g, '');
function wt(word) { const w = ALLW.find(x => key(x.w) === word); if (!w) throw new Error('word not in narration: ' + word); return w.t0; }
const lineEnd = id => WORDS[id].start + WORDS[id].dur;
const T = {};
T.dot = wt('dot') + .01;
T.con = wt('contacted') + .02; T.go = Math.min(wt('route'), T.con - .9);
T.qua = Math.max(wt('qualified'), T.con + .8); T.pro = Math.max(wt('proposal'), T.qua + .7); T.neg = Math.max(wt('negotiation'), T.pro + .9);
T.web = wt('website') - .1; T.evt = wt('events') - .1; T.out = wt('outreach') - .1; T.ref = wt('referrals') - .1;
T.dive = WORDS.L4.start + .3; T.fup = Math.max(wt('across') + .12, T.dive + 2.2);
T.silence = lineEnd('L5'); T.arrive = T.silence + .82;
const P = (path, a, b, t0, t1, extra = {}) => ({ path, a, b, t0, t1, year: 0, ...extra });
const PHASES = [
  // the deal: a dot on "dot", then the route stop by stop as each stage is named
  P('L', 'NEW', 'NEG', 0, 0, { keys: [[T.dot, 'NEW'], [T.go, 'NEW'], [T.con, 'CON'], [T.qua, 'QUA'], [T.pro, 'PRO'], [T.neg, 'NEG']] }),
  // leads arrive from everywhere: each source line departs as it is named
  P('W', 'WEB', 'QUA', T.web, T.web + 1.33),
  P('E', 'EVT', 'QUA', T.evt, T.evt + 1.35),
  P('O', 'OUT', 'QUA', T.out, T.out + 1.33),
  P('R', 'REF', 'WON', T.ref, T.ref + 1.37),
  // under the river to Follow-up, hold in the silence after the last word, then the arrival that drops the interchange
  P('L', 'NEG', 'WON', 0, 0, { keys: [[T.dive, 'NEG'], [T.fup, 'FUP'], [T.arrive - .65, 'FUP'], [T.arrive, 'WON']] }),
];

let H = null;
function phaseTip(idx, t) { const o = H.PH[idx]; const s = o.t0 >= t ? o.s0 : o.t1 <= t ? o.s1 : lerp(o.s0, o.s1, clamp(o.f(t))); return H.pointAt(o.path, s); }
function smoothTip(idx, t, span = .5) { let x = 0, y = 0; for (let k = -4; k <= 4; k++) { const q = phaseTip(idx, t + k * span / 4); x += q[0]; y += q[1]; } return [x / 9, y / 9]; }
const st = id => { const s = window.NET.ST[id]; return [W(s[0]), W(s[1])]; };

// ------------------------------------------------------------------ camera (keyframed shots, eased joins)
const lz = (a, b, u) => Math.exp(lerp(Math.log(a), Math.log(b), u));
const mix = (a, b, u) => ({ x: lerp(a.x, b.x, u), y: lerp(a.y, b.y, u), z: lz(a.z, b.z, u), tilt: lerp(a.tilt, b.tilt, u), head: lerp(a.head, b.head, u), ap: lerp(a.ap, b.ap, u) });
function shot(t) {
  const [nx, ny] = st('NEW');
  if (t < 4.4) { // the empty sheet, then the first dot: a slow push
    const u = ss(seg(t, 0, 4.4));
    return mix({ x: nx + 260, y: ny - 120, z: 2.5, tilt: 34, head: -16, ap: 18 }, { x: nx + 140, y: ny - 30, z: 1.9, tilt: 26, head: -12, ap: 15 }, u);
  }
  if (t < 9.0) { // ride the pen tip, aimed 1.5 G ahead
    const tp = smoothTip(0, t), ahead = smoothTip(0, t + .45), dx = ahead[0] - tp[0], dy = ahead[1] - tp[1], l = Math.hypot(dx, dy) || 1;
    const ride = { x: tp[0] + dx / l * 150 * clamp(l / 20), y: tp[1] + dy / l * 150 * clamp(l / 20), z: 1.32, tilt: 24, head: -10, ap: 14 };
    const from = shot(4.399);
    return mix(from, ride, ss(seg(t, 4.4, 5.2)));
  }
  const RIDE_END = { ...(() => { const [x, y] = st('NEG'); return { x: x + 60, y: y + 20 }; })(), z: 1.32, tilt: 24, head: -10, ap: 14 };
  const WIDE = { x: W(-1.3), y: W(2.6), z: .5, tilt: 5, head: 0, ap: 2 };
  if (t < 15.6) return mix(RIDE_END, WIDE, eio(seg(t, 9.4, 14.6)));            // pull back: the network fills in
  const [rx] = window.NET.WATER[0].line[3], RIVERCAM = { x: W(rx) - 40, y: W(2) - 30, z: 1.85, tilt: 58, head: 28, ap: 24 };
  if (t < 16.9) return mix(WIDE, RIVERCAM, eio(seg(t, 15.6, 16.9)));             // drop low where the line meets the water
  if (t < 19.4) { const tp = smoothTip(5, t), follow = { x: tp[0] + 70, y: tp[1] - 20, z: 1.85, tilt: 56, head: 26, ap: 22 };
    return mix(RIVERCAM, follow, ss(seg(t, 16.9, 17.6))); }
  const [wx, wy] = st('WON'), FUPV = (() => { const tp = phaseTip(5, 19.4); return { x: tp[0] + 70, y: tp[1] - 20, z: 1.85, tilt: 56, head: 26, ap: 22 }; })();
  const STATION = { x: wx - 120, y: wy - 10, z: 1.45, tilt: 32, head: 12, ap: 12 }, PUSH = { ...STATION, x: wx - 80, z: 1.75, tilt: 28 };
  if (t < 21.4) return mix(FUPV, STATION, eio(seg(t, 19.4, 21.4)));
  if (t < 25.6) return mix(STATION, PUSH, ss(seg(t, 21.4, 25.2)));               // tension, held, then the drop
  const END = { x: W(-1.3), y: W(1.65), z: .525, tilt: 0, head: 0, ap: 0 };
  return mix(PUSH, END, eio(seg(t, 25.6, 30.2)));                                // the whole network, top view
}
function camera(t) { return shot(t); }

// ------------------------------------------------------------------ printed furniture: title block, end title
const SHEET = [-1520, -900, 1260, 1200];
function furniture(c, t, view, k) {
  const { F, INK, MUTED } = k;
  c.save(); c.textBaseline = 'alphabetic'; c.textAlign = 'left';
  c.fillStyle = INK; c.fillRect(-1400, -800, 120, 14);
  c.font = F(800, 104); c.fillText('Yourider', -1400, -680);
  c.font = F(600, 40); c.fillText('Sales network', -1400, -624);
  c.font = F(500, 32); c.fillStyle = MUTED; c.fillText('Leads · Pipelines · Deals', -1400, -580);
  if (k.regW) { for (const [id, s, y, sz] of [['ct1', 'Yourider', -680, 104], ['ct2', 'Sales network', -624, 40], ['ct3', 'Leads · Pipelines · Deals', -580, 32]]) { c.font = F(600, sz); const w = c.measureText(s).width; k.regW(id, s, -1400, y - sz * .9, -1400 + w, y + sz * .25, 1, 12); } }
  // legend: one bullet per line, printed under the title
  const L = [['L', 'Lead journey'], ['W', 'Website'], ['E', 'Events'], ['O', 'Outreach'], ['R', 'Referrals']];
  L.forEach(([id, name], i) => { const y = -470 + i * 68; k.roundel(c, -1376, y, id, 1); c.font = F(600, 36); c.fillStyle = INK; c.textBaseline = 'middle'; c.fillText(name, -1330, y + 2); c.textBaseline = 'alphabetic'; });
  c.restore();
  // end title: printed in the bottom margin, wiped on from its bar
  const u = seg(t, 30.25, 30.85); if (u > 0) {
    c.save(); const x = -1400, y = 1110;
    c.fillStyle = RED; c.fillRect(x, y - 92, 12, 112 * eo(u));
    c.beginPath(); c.rect(x + 24, y - 120, 1500 * eo(seg(t, 30.4, 31.3)), 200); c.clip();
    c.fillStyle = INK; c.font = F(800, 76); c.fillText('Your whole pipeline, on one map.', x + 34, y - 30);
    c.fillStyle = MUTED; c.font = F(500, 34); c.fillText('Yourider · every deal, from first dot to Closed Won', x + 36, y + 18);
    c.restore();
  }
}
function riverLabels(c, t, view, { F }) {
  c.save(); c.fillStyle = '#5f88ad'; c.textBaseline = 'middle'; c.textAlign = 'center';
  for (const yy of [-4.8, 10.4]) { c.save(); c.translate(W(yy < 0 ? 2.6 : 3.4), W(yy)); c.rotate(-Math.PI / 2); c.font = F(700, 24); c.fillText('No Reply', 0, -12); c.font = F(600, 16); c.fillText('the silent river', 0, 12); c.restore(); }
  c.restore();
}

// ------------------------------------------------------------------ trains: the finished network runs
function trains(c, t, { PATHS, train }) {
  const run = seg(t, 25.9, 26.6); if (run <= 0) return;
  for (const path of Object.values(PATHS)) {
    const n = Math.max(1, Math.floor(path.total / 380)), gap = path.total / n, v = 190;
    for (let k = 0; k < n; k++) for (const dir of [1, -1]) {
      let s = (k * gap + hash(path.total + k) * gap + dir * (t - 25) * v) % path.total; if (s < 0) s += path.total;
      if (s < 30 || s > path.total - 30) continue;
      train(c, path, s, path.color, run, 1);
    }
  }
}

// ------------------------------------------------------------------ captions: one plate, each word lights as it is spoken
const LINES = Object.values(WORDS);
function captions(c, t, O) {
  const ln = LINES.find(l => t >= l.start - .15 && t <= l.start + l.dur + .45); if (!ln) return;
  const a = clamp(seg(t, ln.start - .15, ln.start + .05)) * (1 - seg(t, ln.start + ln.dur + .2, ln.start + ln.dur + .45));
  const { F, INK } = O, size = 46, gap = 13;
  c.save(); c.font = F(700, size); c.textBaseline = 'middle';
  const ws = ln.words.map(w => ({ ...w, wd: c.measureText(w.w).width }));
  const total = ws.reduce((s, w) => s + w.wd, 0) + gap * (ws.length - 1), x0 = 960 - total / 2, y = 968;
  c.globalAlpha = a; c.fillStyle = PAPER; c.shadowColor = 'rgba(0,0,0,.22)'; c.shadowBlur = 24; c.shadowOffsetY = 6;
  c.beginPath(); c.roundRect(x0 - 34, y - 44, total + 68, 88, 44); c.fill(); c.shadowBlur = 0; c.shadowOffsetY = 0;
  c.fillStyle = RED; c.beginPath(); c.arc(x0 - 8, y, 7, 0, 7); c.fill();
  let x = x0 + 12;
  for (const w of ws) {
    const on = seg(t, w.t0 - .04, w.t0 + .08), past = t > w.t1 + .05;
    c.fillStyle = on > 0 && !past ? RED : past ? INK : 'rgba(27,28,30,.38)';
    const lift = on > 0 && !past ? -3 * back(on, 2) : 0;
    c.fillText(w.w, x, y + lift);
    if (on > 0 && !past) { c.fillRect(x, y + 26, w.wd * eo(on), 4); }
    x += w.wd + gap;
  }
  if (O.regS) { const s = ln.words.map(w => w.w).join(' '); O.regS('cap-' + ln.start, s, x0, y - 30, x0 + total, y + 30, a); }
  c.restore();
}
function overlay(c, t, O) {
  // fade in from paper white at the head, out at the tail
  const fin = 1 - seg(t, 0, .6), fout = seg(t, 32.6, 33.5);
  captions(c, t, O);
  if (fin > 0) { c.save(); c.fillStyle = `rgba(242,238,229,${fin})`; c.fillRect(0, 0, 1920, 1080); c.restore(); }
  if (fout > 0) { c.save(); c.fillStyle = `rgba(242,238,229,${fout})`; c.fillRect(0, 0, 1920, 1080); c.restore(); }
}

// ------------------------------------------------------------------ labels: stages stay readable on the wide shots
const STAGES = ['NEW', 'CON', 'QUA', 'PRO', 'NEG', 'FUP', 'WON'];
const CUES = [{ t: T.dot, type: 'firstdot' }, { t: 9.4, type: 'pullback' }, { t: 15.6, type: 'dive' }, { t: T.silence, type: 'silence' }, { t: T.arrive, type: 'arrive' }, { t: 25.6, type: 'rise' }, { t: 30.25, type: 'title' }, { t: 32.6, type: 'end' }];
export const DATA = {
  DUR, SHEET, PHASES, camera, furniture, riverLabels, trains, overlay,
  drops: { WON: true },
  LABEL_PREF: { NEW: 's', CON: 's', QUA: 'se', PRO: 'nw', NEG: 'n', FUP: 'n', WON: 'se', WEB: 'e', DEM: 'e', EVT: 's', BTH: 's', OUT: 'e', RPL: 'e', REF: 'e', INT: 'e' },
  forceLabel: (n, t) => STAGES.includes(n.id) ? 1 : 0,
  hubLabelScale: z => clamp(Math.pow(.9 / z, .6), 1, 1.6),
  roundelScale: z => clamp(Math.pow(.9 / z, .55), 1, 1.7),
  cues: CUES,
  init(h) { H = h; },
};

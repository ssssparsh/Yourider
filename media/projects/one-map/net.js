// Yourider sales network, drawn as an octilinear transit schematic (0/45/90 degrees). Units: G = 1 grid step = 100 world units.
// x grows east, y grows south. Stations: [x, y, name, second line, tier] (tier 1 = hub label at every zoom).
// The red Lead line is one deal's journey through the pipeline; the other lines are where leads come from.
(function () {
const G = 100;
const ST = {
  NEW: [-10.5, 4, 'New Lead', 'Stage 1', 1],
  CON: [-8, 4, 'Contacted', 'Stage 2', 2],
  QUA: [-5, 4, 'Qualified', 'Stage 3', 1],
  PRO: [-3, 2, 'Proposal', 'Stage 4', 2],
  NEG: [0.5, 2, 'Negotiation', 'Stage 5', 2],
  FUP: [5.5, 2, 'Follow-up', 'Re-engage', 2],
  WON: [8, 2, 'Closed Won', 'Destination', 1],
  WEB: [-5, -4.5, 'Website', 'Inbound', 2],
  DEM: [-5, -1, 'Demo request', 'Form', 3],
  EVT: [-13, 8, 'Events', 'Booth', 2],
  BTH: [-9.5, 8, 'Badge scan', 'Expo', 3],
  OUT: [2.5, 8.5, 'Outreach', 'Outbound', 2],
  RPL: [0, 6, 'Reply', 'Email', 3],
  REF: [8, -5, 'Referrals', 'Partners', 2],
  INT: [8, -1.5, 'Intro call', 'Warm', 3],
};
const LINES = [
  { id: 'L', name: 'Lead', color: '#E3002B', route: ['NEW', 'CON', 'QUA', 'PRO', 'NEG', 'FUP', 'WON'] },
  { id: 'W', name: 'Website', color: '#0094D8', route: ['WEB', 'DEM', 'QUA'] },
  { id: 'E', name: 'Events', color: '#ED6F00', route: ['EVT', 'BTH', 'QUA'] },
  { id: 'O', name: 'Outreach', color: '#7B3FA0', route: ['OUT', 'RPL', 'QUA'] },
  { id: 'R', name: 'Referrals', color: '#00965E', route: ['REF', 'INT', 'WON'] },
];
// the river "No Reply" runs north-south between Negotiation and Follow-up
const RIVER = [[2.6, -7.5], [2.6, 0], [3.4, 0.8], [3.4, 11.5]];

function pt(it) {
  if (typeof it === 'string') { const s = ST[it]; if (!s) throw new Error('no station ' + it); return [s[0], s[1]]; }
  if (typeof it[0] === 'string') { const s = ST[it[0]]; if (!s) throw new Error('no station ' + it[0]); return [s[0] + it[1], s[1] + it[2]]; }
  return [it[0], it[1]];
}
const sid = it => typeof it === 'string' ? it : (typeof it[0] === 'string' ? it[0] : null);
function expand(route) {
  const out = [], ids = []; let diagFirst = false;
  for (const it of route) {
    if (it === '/') { diagFirst = true; continue; }
    const p = pt(it);
    if (out.length) {
      const a = out[out.length - 1], dx = p[0] - a[0], dy = p[1] - a[1], ax = Math.abs(dx), ay = Math.abs(dy);
      if (ax > 1e-6 && ay > 1e-6 && Math.abs(ax - ay) > 1e-6) {
        const d = Math.min(ax, ay), sx = Math.sign(dx), sy = Math.sign(dy);
        const bend = diagFirst ? [a[0] + sx * d, a[1] + sy * d] : [p[0] - sx * d, p[1] - sy * d];
        out.push(bend); ids.push(null);
      }
    }
    out.push(p); ids.push(sid(it)); diagFirst = false;
  }
  return { pts: out, ids };
}
const WATER = [{ id: 'noreply', line: RIVER, outer: 0.81, inner: 0.75, tunnel: true }];
const LINKS = [];
window.NET = { G, ST, LINES, WATER, LINKS, pt, sid, expand };
})();

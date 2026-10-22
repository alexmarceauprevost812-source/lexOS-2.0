/* LexOS Bureau — les fonds animés du Moteur d'Alex.
   ═══ COPIE CONFORME ═══
   Les sept fonds et les aides de couleur ci-dessous sont recopiés tels
   quels de MOTEUR-INTERFACE/interface/fond.js (le Moteur d'interface
   d'Alex, installé dans /usr/lib/lexos/ti-lex-ia). Le bureau doit avoir
   EXACTEMENT ses animations ; si un fond change dans le Moteur, il se
   recopie ici — le banc tests/test_lexos_bureau.py compare les deux.
   Seule différence : THEME est déclaré ici (dans le Moteur, il vit plus
   haut dans fond.js, avec la mécanique de ses Paramètres). */
"use strict";
const THEME = { hex: "#ff7a18", rgb: "255,122,24", clair: "#ffb070", fonce: "#d9580a" };
function hexVersRgb(h) { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
function rgbVersHex(r, g, b) { return "#" + [r, g, b].map((v) => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, "0")).join(""); }
function hslVersHex(h, s, l) {
  s /= 100; l /= 100;
  const k = (n) => (n + h / 30) % 12, a = s * Math.min(l, 1 - l);
  const f = (n) => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  return rgbVersHex(f(0) * 255, f(8) * 255, f(4) * 255);
}
function melanger(hex, vers, t) { const a = hexVersRgb(hex), b = hexVersRgb(vers); return rgbVersHex(...a.map((v, i) => v + (b[i] - v) * t)); }
function luminance(hex) { const [r, g, b] = hexVersRgb(hex).map((v) => { v /= 255; return v <= .03928 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }); return .2126 * r + .7152 * g + .0722 * b; }


const OR = (a) => `rgba(${THEME.rgb},${a})`, BL = (a) => `rgba(255,255,255,${a})`;
const alea = (a, b) => a + Math.random() * (b - a);

/* ════════════════════════ Les fonds animés ════════════════════════
   Chaque fond : init(L, H, densité) → état ; dessine(x, état, L, H, dt, souris) */
const FONDS = {
  constellation: {
    nom: "Constellation", desc: "points reliés qui fuient la souris",
    init(L, H, d) {
      const n = Math.max(28, Math.round(Math.min(220, (L * H) / 14000) * d));
      return Array.from({ length: n }, () => ({ x: alea(0, L), y: alea(0, H), vx: alea(-.35, .35), vy: alea(-.35, .35), r: alea(.6, 2.1), o: Math.random() < .25 }));
    },
    dessine(x, pts, L, H, dt, m) {
      x.clearRect(0, 0, L, H);
      const D = Math.min(140, L / 6);
      for (const p of pts) {
        p.x += p.vx * dt; p.y += p.vy * dt;
        if (p.x < 0 || p.x > L) p.vx *= -1;
        if (p.y < 0 || p.y > H) p.vy *= -1;
        const dx = p.x - m.x, dy = p.y - m.y, d = Math.hypot(dx, dy);
        if (d < 160 && d > 0) { p.x += dx / d * 1.2 * dt; p.y += dy / d * 1.2 * dt; }
        x.beginPath(); x.arc(p.x, p.y, p.r, 0, 7); x.fillStyle = p.o ? OR(.9) : BL(.55); x.fill();
      }
      x.lineWidth = .8;
      for (let i = 0; i < pts.length; i++) for (let j = i + 1; j < pts.length; j++) {
        const a = pts[i], b = pts[j], d = Math.hypot(a.x - b.x, a.y - b.y);
        if (d < D) { x.strokeStyle = OR((1 - d / D) * .22); x.beginPath(); x.moveTo(a.x, a.y); x.lineTo(b.x, b.y); x.stroke(); }
      }
    },
  },
  aurore: {
    nom: "Aurore", desc: "voiles orange qui ondulent",
    init(L, H, d) { return { t: 0, n: Math.max(3, Math.round(5 * d)) }; },
    dessine(x, e, L, H, dt) {
      e.t += .004 * dt;
      x.globalCompositeOperation = "source-over";
      x.fillStyle = "#070707"; x.fillRect(0, 0, L, H);
      x.globalCompositeOperation = "lighter";
      for (let i = 0; i < e.n; i++) {
        const cx = L * (.5 + .42 * Math.sin(e.t * (0.7 + i * .23) + i * 2.1));
        const cy = H * (.5 + .38 * Math.cos(e.t * (0.5 + i * .17) + i * 1.3));
        const r = Math.max(L, H) * (.28 + .1 * Math.sin(e.t + i));
        const g = x.createRadialGradient(cx, cy, 0, cx, cy, r);
        const c = i % 3 === 0 ? "255,170,80" : i % 3 === 1 ? "255,90,10" : "255,122,24";
        g.addColorStop(0, `rgba(${c},.28)`); g.addColorStop(1, "rgba(0,0,0,0)");
        x.fillStyle = g; x.fillRect(0, 0, L, H);
      }
      x.globalCompositeOperation = "source-over";
    },
  },
  etoiles: {
    nom: "Hyperespace", desc: "étoiles qui foncent vers toi",
    init(L, H, d) {
      return Array.from({ length: Math.round(260 * d) }, () => ({ x: alea(-1, 1), y: alea(-1, 1), z: alea(.05, 1), o: Math.random() < .3 }));
    },
    dessine(x, st, L, H, dt, m) {
      x.fillStyle = "rgba(7,7,7,.35)"; x.fillRect(0, 0, L, H);
      const cx = L / 2 + (m.x > -999 ? (m.x - L / 2) * .05 : 0), cy = H / 2 + (m.y > -999 ? (m.y - H / 2) * .05 : 0);
      const k = Math.max(L, H) * .5;
      for (const s of st) {
        const px = cx + s.x / s.z * k, py = cy + s.y / s.z * k;
        s.z -= .006 * dt;
        if (s.z <= .02) { s.x = alea(-1, 1); s.y = alea(-1, 1); s.z = 1; continue; }
        const nx = cx + s.x / s.z * k, ny = cy + s.y / s.z * k;
        if (nx < 0 || nx > L || ny < 0 || ny > H) { s.z = 1; s.x = alea(-1, 1); s.y = alea(-1, 1); continue; }
        x.strokeStyle = s.o ? OR(1 - s.z) : BL(1 - s.z);
        x.lineWidth = (1 - s.z) * 2.4 + .3;
        x.beginPath(); x.moveTo(px, py); x.lineTo(nx, ny); x.stroke();
      }
    },
  },
  //  « pluie » (Pluie de code) retirée à la demande d'Alex (2026-10-22).
  vagues: {
    nom: "Vagues", desc: "lignes qui ondulent",
    init(L, H, d) { return { t: 0, n: Math.max(4, Math.round(9 * d)) }; },
    dessine(x, e, L, H, dt, m) {
      e.t += .012 * dt;
      x.clearRect(0, 0, L, H);
      for (let i = 0; i < e.n; i++) {
        const base = H * (.25 + .6 * i / e.n), amp = H * .05 * (1 + Math.sin(e.t * .3 + i));
        x.beginPath();
        for (let px = 0; px <= L; px += 8) {
          const prox = m.x > -999 ? Math.exp(-((px - m.x) ** 2) / 20000) * 30 * Math.sign(m.y - base || 1) : 0;
          const py = base + Math.sin(px * .006 + e.t + i * .7) * amp + Math.sin(px * .013 - e.t * 1.3) * amp * .4 - prox;
          px ? x.lineTo(px, py) : x.moveTo(px, py);
        }
        x.strokeStyle = i % 3 === 1 ? BL(.18) : OR(.15 + .25 * (i / e.n));
        x.lineWidth = 1.5; x.stroke();
      }
    },
  },
  braises: {
    nom: "Braises", desc: "étincelles qui montent",
    init(L, H, d) {
      return Array.from({ length: Math.round(140 * d) }, () => ({ x: alea(0, L), y: alea(0, H), v: alea(.3, 1.3), r: alea(.6, 2.6), p: alea(0, 6) }));
    },
    dessine(x, b, L, H, dt) {
      x.clearRect(0, 0, L, H);
      const g = x.createLinearGradient(0, H, 0, H * .5);
      g.addColorStop(0, OR(.18)); g.addColorStop(1, "rgba(0,0,0,0)");
      x.fillStyle = g; x.fillRect(0, H * .5, L, H * .5);
      for (const e of b) {
        e.y -= e.v * dt; e.p += .05 * dt; e.x += Math.sin(e.p) * .4 * dt;
        if (e.y < -10) { e.y = H + 10; e.x = alea(0, L); }
        const a = Math.max(0, Math.min(1, e.y / H)) * (.6 + .4 * Math.sin(e.p * 3));
        x.beginPath(); x.arc(e.x, e.y, e.r, 0, 7);
        x.fillStyle = e.r > 2.2 ? BL(a) : OR(a); x.shadowColor = THEME.hex; x.shadowBlur = 8; x.fill();
      }
      x.shadowBlur = 0;
    },
  },
  aucun: {
    nom: "Noir pur", desc: "aucune animation",
    init() { return null; },
    dessine(x, e, L, H) { x.clearRect(0, 0, L, H); },
  },
};

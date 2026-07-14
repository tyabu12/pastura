// Generates the pastura.app Open Graph cards (web/public/img/og-card{,-ja}.png,
// 1200×630) that BaseLayout.astro references. This script is the SOURCE OF TRUTH
// for that artwork — to tweak the card (copy, colours, sheep, hill), edit here
// and re-run, rather than editing the PNGs by hand.
//
// Usage (from anywhere):
//   node web/tools/og-card/generate-og.mjs
//
// Requirements:
//   - Node 18+ (uses node: builtins only, no npm deps)
//   - Google Chrome, for headless rasterisation of the HTML card
//   - Network access at run time (the card pulls Noto Sans JP + JetBrains Mono
//     from Google Fonts; --virtual-time-budget waits for them before shooting)
//
// Env overrides:
//   PASTURA_CHROME       path to the Chrome binary (default: macOS location)
//   PASTURA_OG_OUTDIR    output directory (default: web/public/img)
//
// Design notes:
//   - Copy lives in COPY. The genre word (AIgazing / AI観測) is hand-crafted per
//     language and must NOT be machine-translated — see .claude/rules/lp-content.md.
//   - Sheep bodies use the app's SheepAvatar palette (base.css --avatar-body-*);
//     the shared moss ear colour and the khaki hill are sampled from app-icon.png.

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, '..', '..'); // web/
const iconPath = join(webRoot, 'public', 'img', 'app-icon.png');
const outDir = process.env.PASTURA_OG_OUTDIR ?? join(webRoot, 'public', 'img');
const chrome =
  process.env.PASTURA_CHROME ??
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const icon = readFileSync(iconPath).toString('base64');

// Per-locale copy. Genre word is hand-crafted per language (see lp-content.md).
const COPY = {
  en: {
    genre: 'AIgazing.',
    line: 'Like stargazing,<br>but for local&nbsp;LLMs.',
    lang: 'en',
    out: 'og-card.png',
  },
  ja: {
    genre: 'AI観測。',
    line: '天体観測のように、<br>ローカルLLMを眺める。',
    lang: 'ja',
    out: 'og-card-ja.png',
  },
};

// A single sheep, faithful to the app icon: a front-facing plump egg body in a
// pastel avatar colour, plus two floppy ears in a *shared* moss tone (the icon
// uses one ear colour for all three bodies, and the bodies are flat — no inner
// face patch). Dog-like ears are splayed outward (near-horizontal) and peek out
// from BEHIND the body sides (drawn before the body, so only the part past the
// silhouette shows). cx/cy = body centre.
const EAR = '#7C7F54';
const FLOCK = {
  alice: '#e3d0aa', // cream
  bob: '#d3cea7', // moss
  carol: '#e9d1bd', // pink
};
const sheep = (cx, cy, s, body) => `
  <g transform="translate(${cx},${cy}) scale(${s})">
    <ellipse cx="-25" cy="-6" rx="7.5" ry="14" fill="${EAR}" transform="rotate(52 -25 -6)"/>
    <ellipse cx="25" cy="-6" rx="7.5" ry="14" fill="${EAR}" transform="rotate(-52 25 -6)"/>
    <ellipse cx="0" cy="0" rx="27" ry="31" fill="${body}"/>
  </g>`;

function page(c) {
  return `<!doctype html><html lang="${c.lang}"><head><meta charset="utf-8">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400;500;700&family=JetBrains+Mono:wght@500&display=swap" rel="stylesheet">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html,body { width:1200px; height:630px; }
  .card {
    position:relative; width:1200px; height:630px; overflow:hidden;
    background:
      radial-gradient(120% 140% at 100% 100%, rgba(138,154,108,0.16), transparent 55%),
      #FCFAF4;
    font-family:"Noto Sans JP",-apple-system,system-ui,sans-serif;
    color:#2D2E26;
  }
  /* Clip the hill to the frame interior so grass never spills past the border. */
  .hillclip { position:absolute; inset:20px; border-radius:27px; overflow:hidden; }
  .hills { position:absolute; right:0; bottom:0; }
  .frame { position:absolute; inset:20px; border:1px solid #E4E7D2; border-radius:28px; pointer-events:none; }
  .pad { position:absolute; inset:0; padding:74px 84px; display:flex; flex-direction:column; }
  .top { display:flex; align-items:center; justify-content:space-between; }
  .brand { display:flex; align-items:center; gap:22px; }
  .brand img { width:88px; height:88px; border-radius:20px;
    box-shadow:0 6px 18px rgba(60,62,48,0.12); }
  .brand .name { font-weight:700; font-size:48px; letter-spacing:-0.01em; color:#2D2E26; }
  .url { font-family:"JetBrains Mono",monospace; font-weight:500; font-size:22px;
    letter-spacing:0.06em; color:#6B7852; }
  .tagwrap { flex:1; display:flex; align-items:center; }
  .genre { font-weight:500; font-size:72px; line-height:1.06; letter-spacing:-0.02em;
    color:#6B7852; }
  .line { margin-top:30px; font-weight:400; font-size:42px; line-height:1.32;
    letter-spacing:-0.012em; color:#2D2E26; }
</style></head>
<body>
  <div class="card">
    <div class="hillclip">
      <svg class="hills" width="600" height="340" viewBox="0 0 600 340">
        ${sheep(350, 138, 1.15, FLOCK.alice)}
        ${sheep(452, 138, 1.22, FLOCK.bob)}
        ${sheep(554, 138, 1.15, FLOCK.carol)}
        <path d="M0 340 L0 230 C 130 175, 320 150, 470 156 C 530 159, 570 164, 600 168 L600 340 Z" fill="#cbc79e"/>
      </svg>
    </div>
    <div class="frame"></div>
    <div class="pad">
      <div class="top">
        <div class="brand">
          <img src="data:image/png;base64,${icon}" alt="">
          <span class="name">Pastura</span>
        </div>
        <span class="url">pastura.app</span>
      </div>
      <div class="tagwrap">
        <div class="tag">
          <div class="genre">${c.genre}</div>
          <div class="line">${c.line}</div>
        </div>
      </div>
    </div>
  </div>
</body></html>`;
}

const work = mkdtempSync(join(tmpdir(), 'og-card-'));
try {
  for (const c of Object.values(COPY)) {
    const html = join(work, `${c.lang}.html`);
    const png = join(outDir, c.out);
    writeFileSync(html, page(c));
    execFileSync(
      chrome,
      [
        '--headless=new',
        '--disable-gpu',
        '--hide-scrollbars',
        '--force-device-scale-factor=1',
        '--window-size=1200,630',
        `--screenshot=${png}`,
        '--virtual-time-budget=2500',
        `file://${html}`,
      ],
      { stdio: 'ignore' },
    );
    console.log(`wrote ${png}`);
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}

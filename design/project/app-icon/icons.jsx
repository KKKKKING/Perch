/* Perch — app icon explorations.
   Every concept is a self-contained, resolution-independent SVG drawn on a
   1024 canvas and clipped to the macOS "squircle" (Big Sur superellipse), so
   it stays crisp from 1024px down to a 16px menu-bar glyph.
   Palette is locked to Perch's brand DNA: blue-900 -> purple, Spectrum 2 tokens. */

const { useId } = React;

/* ---- macOS superellipse (continuous-curvature squircle) ---------------- */
function superPath(n = 5, size = 1024) {
  const a = size / 2, cx = a, cy = a, N = 220;
  let d = '';
  for (let i = 0; i <= N; i++) {
    const t = (2 * Math.PI * i) / N;
    const ct = Math.cos(t), st = Math.sin(t);
    const x = cx + a * Math.sign(ct) * Math.pow(Math.abs(ct), 2 / n);
    const y = cy + a * Math.sign(st) * Math.pow(Math.abs(st), 2 / n);
    d += (i === 0 ? 'M' : 'L') + x.toFixed(2) + ' ' + y.toFixed(2) + ' ';
  }
  return d + 'Z';
}
const SQUIRCLE = superPath(5);

/* macOS icon grid: the art lives in an 824/1024 footprint (≈0.80), leaving the
   standard transparent margin so Perch sits at the same scale as App Store /
   Finder icons. The whole tray + its contents are scaled by this; bird scales
   are pre-multiplied so the bird keeps its ABSOLUTE size while the tray shrinks
   (birdScale 3.75 × 0.80 = 3.0 effective → bird fills ~68% of the tray width). */
const DOCK_TRAY_SCALE = 0.80;

/* Brand gradient stops — softened sky-blue family (old-Twitter direction:
   lighter and less saturated than the original vivid indigo accent).
   The gradient now stays within blue: sky -> ocean, no purple. */
const G = {
  blue: '#4FAEEE',     // soft sky blue — new primary/accent (top of gradient)
  blueDk: '#2E8FDB',
  indigo: '#2F97E2',   // mid sky blue
  purple: '#1C81CF',   // deep ocean blue — bottom of gradient (stays in-family)
  purpleLt: '#5DB6F2',
  ink: '#15141a',
};

/* Shared frame: gradient (or custom) squircle + top sheen + inner hairline. */
function Frame({ uid, from = G.blue, to = G.purple, angle = 150, sheen = true, tray = false, children }) {
  const gid = uid + '-bg', sid = uid + '-sheen', cid = uid + '-clip';
  const rad = (angle - 90) * Math.PI / 180;
  const x2 = 0.5 + Math.cos(rad) / 2, y2 = 0.5 + Math.sin(rad) / 2;
  const x1 = 1 - x2, y1 = 1 - y2;
  return (
    <svg viewBox="0 0 1024 1024" width="100%" height="100%" style={{ display: 'block' }}>
      <defs>
        <clipPath id={cid}><path d={SQUIRCLE} /></clipPath>
        <linearGradient id={gid} x1={x1} y1={y1} x2={x2} y2={y2}>
          <stop offset="0" stopColor={from} />
          <stop offset="1" stopColor={to} />
        </linearGradient>
        <linearGradient id={sid} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#fff" stopOpacity={tray ? 0.0 : 0.22} />
          <stop offset="0.5" stopColor="#fff" stopOpacity="0" />
          <stop offset="1" stopColor="#000" stopOpacity={tray ? 0.05 : 0.12} />
        </linearGradient>
      </defs>
      <g transform={`translate(512 512) scale(${DOCK_TRAY_SCALE}) translate(-512 -512)`}>
        <g clipPath={`url(#${cid})`}>
          <path d={SQUIRCLE} fill={tray ? 'none' : `url(#${gid})`} />
          {tray && <rect x="0" y="0" width="1024" height="1024" fill="#f4f3f7" />}
          {children}
          {sheen && <path d={SQUIRCLE} fill={`url(#${sid})`} />}
        </g>
        {/* inner hairline for that pressed-glass S2 edge */}
        <path d={SQUIRCLE} fill="none" stroke={tray ? 'rgba(0,0,0,.08)' : 'rgba(255,255,255,.20)'} strokeWidth="6" transform="translate(512 512) scale(0.985) translate(-512 -512)" />
      </g>
    </svg>
  );
}

/* A friendly geometric songbird, perched & facing right. Built from primitives
   so it stays clean at any size. Origin is the perch point (feet) at (px,py);
   `s` scales, `fill` colors the body, `accent` the wing/beak detail. */
function Bird({ px, py, s = 1, fill = '#fff', accent = 'rgba(255,255,255,.42)', eye = '#3b63fb' }) {
  // local design space ~ 200 wide; feet land near (95, 168)
  const T = `translate(${px} ${py}) scale(${s}) translate(-95 -168)`;
  return (
    <g transform={T}>
      {/* body + tail as ONE fused silhouette: the tail's upper edge continues
          the back line and its lower edge continues the belly, so the rump
          flows into the tail with no seam */}
      <path d="M128 46
        C104 50 82 64 68 88
        C60 100 56 108 54 116
        C40 128 26 144 16 156
        C30 158 46 157 62 153
        C68 152 72 151 78 150
        C100 162 122 162 140 150
        C152 132 154 116 152 98 Z" fill={fill} />
      {/* head rounding into the body (overlap keeps it seamless) */}
      <circle cx="132" cy="70" r="40" fill={fill} />
      {/* beak — short wedge pointing right */}
      <path d="M168 66 L196 74 L168 86 Z" fill={accent === 'tray' ? '#f6b73c' : '#ffce5c'} />
      {/* eye */}
      <circle cx="146" cy="64" r="7.5" fill={eye} />
      {/* legs */}
      <path d="M104 150 L104 176 M124 148 L124 176" stroke={fill} strokeWidth="7" strokeLinecap="round" />
    </g>
  );
}

/* =====================================================================
   CONCEPT 1 — Monogram (the refined baseline; elevates the current mark)
   ===================================================================== */
function IconMonogram({ uid }) {
  return (
    <Frame uid={uid} from={G.blue} to={G.purple} angle={150}>
      <text x="512" y="512" textAnchor="middle" dominantBaseline="central"
        fontFamily='"Source Serif 4", Georgia, serif' fontWeight="700" fontSize="660"
        fill="rgba(0,0,0,.18)" dy="14">P</text>
      <text x="512" y="512" textAnchor="middle" dominantBaseline="central"
        fontFamily='"Source Serif 4", Georgia, serif' fontWeight="700" fontSize="660"
        fill="#fff">P</text>
    </Frame>
  );
}

/* =====================================================================
   CONCEPT 2 — Perched bird (the literal Perch metaphor, white on gradient)
   ===================================================================== */
function IconBird({ uid }) {
  return (
    <Frame uid={uid} from={G.blue} to={G.purple} angle={155}>
      {/* branch — short perch, proportioned to the bird (matches concept E) */}
      <path d="M412 810 H706" stroke="rgba(255,255,255,.5)" strokeWidth="32" strokeLinecap="round" />
      <Bird px={467} py={764} s={4.1} eye={G.purple} accent="rgba(255,255,255,.40)" />
    </Frame>
  );
}

/* =====================================================================
   CONCEPT 3 — "P-perch": the monogram's stem becomes a branch a bird sits on
   ===================================================================== */
function IconPPerch({ uid }) {
  return (
    <Frame uid={uid} from={G.indigo} to={G.purple} angle={150}>
      {/* a geometric P drawn as strokes: stem + bowl */}
      <g fill="none" stroke="#fff" strokeWidth="84" strokeLinecap="round">
        <path d="M352 250 V792" />
        <path d="M352 250 H560 a168 168 0 0 1 0 336 H352" />
      </g>
      {/* little bird perched on top of the stem */}
      <Bird px={352} py={250} s={1.7} fill="#fff" eye={G.purple} accent="rgba(255,255,255,.0)" />
    </Frame>
  );
}

/* =====================================================================
   CONCEPT 4 — Columns: the multi-column reader, with a bird on the railing
   ===================================================================== */
function IconColumns({ uid }) {
  const col = (x, h) => <rect x={x} y={760 - h} width="150" height={h} rx="40" fill="rgba(255,255,255,.92)" />;
  return (
    <Frame uid={uid} from={G.blue} to={G.purple} angle={150}>
      {col(214, 300)}
      {col(437, 470)}
      {col(660, 360)}
      {/* railing the columns sit under doubles as a perch */}
      <Bird px={512} py={250} s={1.85} fill="#fff" eye={G.blue} accent="rgba(59,99,251,.0)" />
    </Frame>
  );
}

/* =====================================================================
   CONCEPT 5 — Light tray: gradient bird + branch on a soft neutral tile
   (shows the alternate macOS "object on a light tray" icon style)
   ===================================================================== */
function IconTray({ uid }) {
  const gid = uid + '-bird';
  return (
    <Frame uid={uid} tray sheen={false}>
      <defs>
        <linearGradient id={gid} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={G.blue} />
          <stop offset="1" stopColor={G.purple} />
        </linearGradient>
      </defs>
      <path d="M412 810 H706" stroke="#d3d2da" strokeWidth="32" strokeLinecap="round" />
      <g style={{ color: `url(#${gid})` }}>
        <Bird px={467} py={764} s={4.1} fill={`url(#${gid})`} eye="#fff" accent="rgba(255,255,255,.5)" />
      </g>
    </Frame>
  );
}

/* =====================================================================
   CONCEPT 6 — Chirp: a bird nested inside a speech bubble (posts = chirps)
   ===================================================================== */
function IconChirp({ uid }) {
  return (
    <Frame uid={uid} from={G.blue} to={G.purple} angle={150}>
      {/* speech bubble */}
      <path d="M512 226 C306 226 196 350 196 486 C196 600 286 700 430 726 L430 838 L548 720 C720 706 828 600 828 486 C828 350 718 226 512 226 Z"
        fill="#fff" />
      <Bird px={470} py={600} s={2.05} fill={G.purple} eye="#fff" accent="rgba(115,38,211,.18)" />
    </Frame>
  );
}

Object.assign(window, {
  IconMonogram, IconBird, IconPPerch, IconColumns, IconTray, IconChirp, Frame, Bird, SQUIRCLE,
});

/* Perch app icon — the refined "Perched" bird mark (concept B) on the soft
   sky-blue brand gradient, clipped to the macOS squircle. Shared by the app
   (Settings ▸ About, favicon) and the welcome screen so the brand stays
   consistent. Resolution-independent SVG: crisp from 80px down to 16px. */

const _superPath = (n = 5, size = 1024) => {
  const a = size / 2, N = 200;
  let d = '';
  for (let i = 0; i <= N; i++) {
    const t = (2 * Math.PI * i) / N, ct = Math.cos(t), st = Math.sin(t);
    const x = a + a * Math.sign(ct) * Math.pow(Math.abs(ct), 2 / n);
    const y = a + a * Math.sign(st) * Math.pow(Math.abs(st), 2 / n);
    d += (i === 0 ? 'M' : 'L') + x.toFixed(1) + ' ' + y.toFixed(1) + ' ';
  }
  return d + 'Z';
};
const PERCH_SQUIRCLE = _superPath(5);

/* sky -> ocean, soft (old-Twitter direction) */
const PERCH_SKY = '#4FAEEE';
const PERCH_OCEAN = '#1C81CF';

function PerchIcon({ size = 80, glow = true }) {
  const raw = (React.useId ? React.useId() : 'p' + Math.random()).replace(/[^a-z0-9]/gi, '');
  const bg = raw + 'bg', sh = raw + 'sh', cl = raw + 'cl';
  return (
    <svg width={size} height={size} viewBox="0 0 1024 1024" style={{ display: 'block', flex: 'none',
      filter: glow ? `drop-shadow(0 ${size * 0.07}px ${size * 0.16}px rgba(28,129,207,.34))` : 'none' }}>
      <defs>
        <clipPath id={cl}><path d={PERCH_SQUIRCLE} /></clipPath>
        <linearGradient id={bg} x1="0.18" y1="0" x2="0.82" y2="1">
          <stop offset="0" stopColor={PERCH_SKY} />
          <stop offset="1" stopColor={PERCH_OCEAN} />
        </linearGradient>
        <linearGradient id={sh} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#fff" stopOpacity="0.22" />
          <stop offset="0.5" stopColor="#fff" stopOpacity="0" />
          <stop offset="1" stopColor="#000" stopOpacity="0.12" />
        </linearGradient>
      </defs>
      <g clipPath={`url(#${cl})`}>
        <path d={PERCH_SQUIRCLE} fill={`url(#${bg})`} />
        {/* branch — single horizontal line */}
        <path d="M150 720 H874" stroke="rgba(255,255,255,.5)" strokeWidth="26" strokeLinecap="round" />
        {/* bird (white), feet land on the branch */}
        <g transform="translate(470 720) scale(2.7) translate(-95 -168)">
          <path d="M128 46 C104 50 82 64 68 88 C60 100 56 108 54 116 C40 128 26 144 16 156 C30 158 46 157 62 153 C68 152 72 151 78 150 C100 162 122 162 140 150 C152 132 154 116 152 98 Z" fill="#fff" />
          <circle cx="132" cy="70" r="40" fill="#fff" />
          <path d="M168 66 L196 74 L168 86 Z" fill="#ffce5c" />
          <circle cx="146" cy="64" r="7.5" fill={PERCH_OCEAN} />
          <path d="M104 150 L104 176 M124 148 L124 176" stroke="#fff" strokeWidth="7" strokeLinecap="round" />
        </g>
        <path d={PERCH_SQUIRCLE} fill={`url(#${sh})`} />
      </g>
      <path d={PERCH_SQUIRCLE} fill="none" stroke="rgba(255,255,255,.20)" strokeWidth="6"
        transform="translate(512 512) scale(0.985) translate(-512 -512)" />
    </svg>
  );
}

window.PerchIcon = PerchIcon;
window.PERCH_SKY = PERCH_SKY;
window.PERCH_OCEAN = PERCH_OCEAN;

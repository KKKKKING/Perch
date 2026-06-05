/* Compose kit — the building blocks for the rich compose sheet:
   @/# autocomplete, image attachments, polls (with image options),
   who-can-reply, scheduling, content disclosure, and the drafts window.
   All pieces are platform-aware (X English / Weibo 中文) and use S2 tokens
   so they track light & dark themes. Exported on window for compose.jsx. */

/* ── tiny inline icons not in the shared glyph set ── */
function KitIcon({ d, size = 20, vb = 20, stroke }) {
  return (
    <span style={{ display: 'inline-flex', width: size, height: size, color: 'currentColor', flex: 'none' }}>
      <svg width="100%" height="100%" viewBox={`0 0 ${vb} ${vb}`} style={{ display: 'block' }}>{d}</svg>
    </span>
  );
}
const AtGlyph = ({ size = 20 }) => <KitIcon size={size} d={<path fill="currentColor" d="M10 1.9a8.1 8.1 0 1 0 4.7 14.7.85.85 0 1 0-1-1.38A6.4 6.4 0 1 1 16.4 10v.7a1.15 1.15 0 0 1-2.3 0V6.6a.85.85 0 0 0-1.66-.26 4 4 0 1 0 .28 5.48 2.85 2.85 0 0 0 5.08-1.82V10A8.1 8.1 0 0 0 10 1.9Zm0 10.45A2.35 2.35 0 1 1 10 7.65a2.35 2.35 0 0 1 0 4.7Z" />} />;
const FollowGlyph = ({ size = 20 }) => <KitIcon size={size} d={<g fill="currentColor"><path d="M8 10.4c-2.1 0-3.8-1.85-3.8-4.1S5.9 2.2 8 2.2s3.8 1.85 3.8 4.1-1.7 4.1-3.8 4.1Zm0-6.7c-1.2 0-2.2 1.16-2.2 2.6S6.8 8.9 8 8.9s2.2-1.16 2.2-2.6S9.2 3.7 8 3.7Z" /><path d="M13.5 16.9a.78.78 0 0 1-.77-.69C12.5 14.3 10.45 12.9 8 12.9s-4.5 1.4-4.73 3.32a.78.78 0 1 1-1.54-.18C2.06 13.2 4.74 11.4 8 11.4s5.94 1.8 6.27 4.54a.78.78 0 0 1-.69.86Z" /><path d="M16.2 8.9 14.6 7.3a.7.7 0 0 1 1-1l1.05 1.05 2.2-2.45a.7.7 0 1 1 1.04.94l-2.7 3a.7.7 0 0 1-1.02.05Z" /></g>} />;
const BadgeGlyph = ({ size = 20 }) => (
  <span style={{ display: 'inline-flex', width: size, height: size, flex: 'none', color: 'currentColor' }}>
    <svg viewBox="0 0 22 22" width="100%" height="100%" style={{ display: 'block' }}>
      <path fill="currentColor" d="M11 1.5l2.2 1.9 2.9-.3 1.2 2.7 2.6 1.3-.3 2.9 1.9 2.2-1.9 2.2.3 2.9-2.6 1.3-1.2 2.7-2.9-.3L11 20.5l-2.2-1.9-2.9.3-1.2-2.7-2.6-1.3.3-2.9L.5 11l1.9-2.2-.3-2.9 2.6-1.3 1.2-2.7 2.9.3L11 1.5z" />
      <path d="M7.3 11.1l2.5 2.5 4.9-5.2" stroke="var(--bg-elevated)" strokeWidth="1.9" fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  </span>
);
const GifGlyph = ({ size = 20 }) => <KitIcon size={size} d={<g fill="none" stroke="currentColor" strokeWidth="1.4"><rect x="2.3" y="4.3" width="15.4" height="11.4" rx="2.2" /><path d="M8 8.1a1.9 1.9 0 1 0 0 3.8c1 0 1.6-.5 1.6-1.5V10H8.1" strokeLinecap="round" strokeLinejoin="round" /><path d="M11.7 7.9v4.2" strokeLinecap="round" /><path d="M14 12.1V7.9h2.1M14 10.1h1.7" strokeLinecap="round" strokeLinejoin="round" /></g>} />;
const ClockGlyph = ({ size = 20 }) => <KitIcon size={size} d={<g fill="none" stroke="currentColor" strokeWidth="1.5"><circle cx="10" cy="10" r="7.4" /><path d="M10 5.6V10l3 2" strokeLinecap="round" strokeLinejoin="round" /></g>} />;
const SchedGlyph = ({ size = 20 }) => <KitIcon size={size} d={<g fill="none" stroke="currentColor" strokeWidth="1.5"><rect x="2.6" y="3.8" width="11" height="11" rx="2" /><path d="M2.6 7h11M5.4 2.6v2.2M10.8 2.6v2.2" strokeLinecap="round" /><circle cx="14.4" cy="14.4" r="3.4" fill="var(--bg-base)" /><path d="M14.4 12.7v1.7l1.1 1.1" strokeLinecap="round" strokeLinejoin="round" /></g>} />;

/* ── scheduled-posts store (persists across sessions) ── */
const SCHED_LS = 'perch.scheduled.v1';
const ScheduleStore = {
  all() { try { return (JSON.parse(localStorage.getItem(SCHED_LS)) || []).sort((a, b) => new Date(a.when) - new Date(b.when)); } catch (e) { return []; } },
  add(item) { const a = this.all(); a.push(item); localStorage.setItem(SCHED_LS, JSON.stringify(a)); return item; },
  remove(id) { localStorage.setItem(SCHED_LS, JSON.stringify(this.all().filter(x => x.id !== id))); },
};

/* ── @mention / #topic data + token logic ── */
const KIT_TOPICS = {
  x: [
    { tag: 'DesignSystems', posts: '12.4K' }, { tag: 'SwiftUI', posts: '48.1K' },
    { tag: 'WWDC26', posts: '203K' }, { tag: 'MacApps', posts: '8,920' },
    { tag: 'Spectrum2', posts: '3,140' }, { tag: 'Typography', posts: '21.7K' },
    { tag: 'DarkMode', posts: '9,560' }, { tag: 'IndieDev', posts: '34.2K' },
    { tag: 'UIDesign', posts: '88.3K' }, { tag: 'ProductDesign', posts: '15.9K' },
  ],
  weibo: [
    { tag: '设计系统', posts: '1.2万' }, { tag: '胶片摄影', posts: '8.9万' },
    { tag: '深夜放毒', posts: '23万' }, { tag: 'Mac效率', posts: '4,210' },
    { tag: '深色模式', posts: '9,560' }, { tag: '字体排印', posts: '2.1万' },
    { tag: '在路上', posts: '15.6万' }, { tag: '独立开发', posts: '3.4万' },
    { tag: '城市摄影', posts: '6.7万' }, { tag: '极简设计', posts: '1.9万' },
  ],
};
function mentionCandidates(platform) {
  const seen = {}; const out = [];
  Object.values(window.P || {}).forEach(p => { if (p.platform === platform && !seen[p.handle]) { seen[p.handle] = 1; out.push(p); } });
  (window.ACCOUNTS || []).forEach(a => { if (a.platform === platform && !seen[a.handle]) { seen[a.handle] = 1; out.push(a); } });
  return out;
}
// the @/# token immediately before the caret, if any
function activeToken(value, caret) {
  const upto = value.slice(0, caret);
  const m = upto.match(/(^|\s)([@#＃])([^\s@#＃]*)$/);
  if (!m) return null;
  const sym = m[2], q = m[3];
  return { type: sym === '@' ? 'mention' : 'topic', query: q, start: caret - q.length - 1, end: caret };
}
function replaceToken(value, tok, insert) {
  return { text: value.slice(0, tok.start) + insert + ' ' + value.slice(tok.end), caret: tok.start + insert.length + 1 };
}
function matchesFor(tok, platform) {
  const q = (tok.query || '').toLowerCase();
  if (tok.type === 'mention') {
    return mentionCandidates(platform)
      .filter(p => !q || p.handle.toLowerCase().includes(q) || (p.name || '').toLowerCase().includes(q))
      .slice(0, 6);
  }
  return (KIT_TOPICS[platform] || [])
    .filter(t => !q || t.tag.toLowerCase().includes(q))
    .slice(0, 6);
}

/* ── autocomplete popover (presentational) ── */
function AutoComplete({ tok, platform, hi, onPick, onHover }) {
  const items = matchesFor(tok, platform);
  if (!items.length) return null;
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, top: 'calc(100% + 6px)', zIndex: 70, background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', borderRadius: 12, boxShadow: 'var(--shadow-elevated)', overflow: 'hidden', maxHeight: 268, overflowY: 'auto' }} className="col-scroll">
      {tok.type === 'mention' ? items.map((p, i) => (
        <button key={p.handle} onMouseDown={e => { e.preventDefault(); onPick('@' + p.handle); }} onMouseEnter={() => onHover(i)}
          style={{ display: 'flex', alignItems: 'center', gap: 11, width: '100%', padding: '9px 13px', border: 'none', background: i === hi ? 'var(--gray-100)' : 'transparent', cursor: 'pointer', textAlign: 'left' }}>
          <PAvatar person={p} size={38} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
              <span style={{ fontSize: 14.5, fontWeight: 700, color: 'var(--fg-heading)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', fontFamily: 'var(--font-sans)' }}>{p.name}</span>
              {p.verified && <Verified size={14} />}
            </div>
            <div style={{ fontSize: 13, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>@{p.handle}</div>
          </div>
        </button>
      )) : items.map((t, i) => (
        <button key={t.tag} onMouseDown={e => { e.preventDefault(); onPick('#' + t.tag); }} onMouseEnter={() => onHover(i)}
          style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', padding: '10px 13px', border: 'none', background: i === hi ? 'var(--gray-100)' : 'transparent', cursor: 'pointer', textAlign: 'left' }}>
          <span style={{ width: 38, height: 38, borderRadius: 10, flex: 'none', background: 'var(--gray-100)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: 'var(--fg-subdued)', fontSize: 19, fontWeight: 800, fontFamily: 'var(--font-sans)' }}>#</span>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 14.5, fontWeight: 700, color: 'var(--fg-heading)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', fontFamily: 'var(--font-sans)' }}>#{t.tag}</div>
            <div style={{ fontSize: 13, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>{platform === 'x' ? `${t.posts} posts` : `${t.posts} 讨论`}</div>
          </div>
        </button>
      ))}
    </div>
  );
}

/* ── attached-image grid (cells open the full media editor) ── */
function ImageGrid({ images, onRemove, onEdit, isX }) {
  const n = images.length;
  if (!n) return null;
  const cols = n === 1 ? 1 : 2;
  const tall = n === 3; // first image spans both rows
  return (
    <div style={{ marginTop: 12, display: 'grid', gridTemplateColumns: `repeat(${cols}, 1fr)`, gridAutoRows: n === 1 ? 'auto' : '128px', gap: 4, borderRadius: 16, overflow: 'hidden', border: '1px solid var(--border-default)' }}>
      {images.map((img, i) => {
        const warned = img.warn && Object.values(img.warn).some(Boolean);
        return (
          <div key={img.id} onClick={() => onEdit(img.id, 'crop')} title={isX ? 'Edit media' : '编辑'}
            style={{ position: 'relative', overflow: 'hidden', cursor: 'pointer', gridRow: tall && i === 0 ? 'span 2' : undefined, aspectRatio: n === 1 ? '16 / 10' : undefined, background: 'var(--gray-100)' }}>
            <img src={img.url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
            <button onClick={e => { e.stopPropagation(); onRemove(img.id); }} title={isX ? 'Remove' : '移除'}
              style={{ position: 'absolute', top: 7, right: 7, width: 28, height: 28, borderRadius: '50%', border: 'none', background: 'rgba(15,14,18,.72)', color: '#fff', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', backdropFilter: 'blur(4px)' }}>
              <Glyph name="close" size={15} />
            </button>
            <div style={{ position: 'absolute', bottom: 7, left: 7, display: 'flex', gap: 6 }}>
              <button onClick={e => { e.stopPropagation(); onEdit(img.id, 'crop'); }} title={isX ? 'Edit' : '编辑'}
                style={{ height: 26, padding: '0 10px', borderRadius: 8, border: 'none', background: 'rgba(15,14,18,.72)', color: '#fff', cursor: 'pointer', fontSize: 12, fontWeight: 800, fontFamily: 'var(--font-sans)', letterSpacing: '.02em', backdropFilter: 'blur(4px)' }}>{isX ? 'Edit' : '编辑'}</button>
              <button onClick={e => { e.stopPropagation(); onEdit(img.id, 'alt'); }} title={isX ? 'Add description' : '添加描述'}
                style={{ height: 26, padding: '0 9px', borderRadius: 8, border: 'none', background: img.alt ? 'var(--accent-bg)' : 'rgba(15,14,18,.72)', color: '#fff', cursor: 'pointer', fontSize: 12, fontWeight: 800, fontFamily: 'var(--font-sans)', letterSpacing: '.02em', backdropFilter: 'blur(4px)' }}>{isX ? 'ALT' : '描述'}</button>
            </div>
            {warned && (
              <div style={{ position: 'absolute', top: 7, left: 7, height: 26, padding: '0 9px', borderRadius: 8, background: 'rgba(15,14,18,.72)', color: '#fff', display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 11.5, fontWeight: 800, fontFamily: 'var(--font-sans)', backdropFilter: 'blur(4px)' }}>
                <span style={{ display: 'inline-flex', width: 13, height: 13 }}><svg viewBox="0 0 20 20" width="100%" height="100%"><g fill="currentColor"><path d="M5 2.5a.8.8 0 0 1 .8.8v.36c1.9-.83 3.45.55 5.12.55.86 0 1.62-.27 2.3-.66a.72.72 0 0 1 1.08.62v5.92a.72.72 0 0 1-.37.63c-.78.44-1.66.81-2.66.81-1.74 0-3.3-1.39-5.07-.58a.2.2 0 0 0-.13.18v5.84a.8.8 0 0 1-1.6 0V3.3A.8.8 0 0 1 5 2.5Z" /></g></svg></span>
                {isX ? 'Warning' : '警告'}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

/* ── media editor: Crop / ALT / Content-warning, with a real cropper ── */
const CROP_RATIOS = [
  { id: 'original', x: 'Original', w: '原始' },
  { id: 'wide', x: 'Wide', w: '宽屏', ar: 16 / 9 },
  { id: 'square', x: 'Square', w: '方形', ar: 1 },
];
function cropDims(nat, aspect, zoom) {
  const ar = aspect === 'wide' ? 16 / 9 : aspect === 'square' ? 1 : nat.w / nat.h;
  const baseW = Math.min(nat.w, nat.h * ar);
  const w = baseW / zoom;
  return { w, h: w / ar, ar };
}
function clampCrop(x, y, w, h, nat) {
  return { x: Math.max(0, Math.min(x, nat.w - w)), y: Math.max(0, Math.min(y, nat.h - h)) };
}

const WARN_CATS = [
  { id: 'nudity', x: 'Nudity', w: '裸露' },
  { id: 'violence', x: 'Violence', w: '暴力' },
  { id: 'sensitive', x: 'Sensitive', w: '敏感内容' },
  { id: 'ai', x: 'Generated with AI', w: 'AI 生成' },
];

function CropTab({ url, nat, aspect, setAspect, zoom, setZoom, crop, setCrop, imgRef }) {
  const vpRef = React.useRef(null);
  const drag = React.useRef(null);
  const { w, h } = nat ? cropDims(nat, aspect, zoom) : { w: 1, h: 1 };
  const ar = w / h;
  const onDown = (e) => {
    if (!nat) return;
    const pw = vpRef.current.clientWidth, ph = vpRef.current.clientHeight;
    drag.current = { sx: e.clientX, sy: e.clientY, x: crop.x, y: crop.y, pw, ph };
    e.preventDefault();
    const move = (ev) => {
      const d = drag.current; if (!d) return;
      const nx = d.x - ((ev.clientX - d.sx) / d.pw) * w;
      const ny = d.y - ((ev.clientY - d.sy) / d.ph) * h;
      setCrop(clampCrop(nx, ny, w, h, nat));
    };
    const up = () => { drag.current = null; window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up); };
    window.addEventListener('mousemove', move); window.addEventListener('mouseup', up);
  };
  const pct = nat ? { width: nat.w / w * 100 + '%', height: nat.h / h * 100 + '%', left: -crop.x / w * 100 + '%', top: -crop.y / h * 100 + '%' } : {};
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ flex: 1, minHeight: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 22, background: 'var(--bg-pasteboard, #0b0a0e)' }}>
        <div ref={vpRef} onMouseDown={onDown}
          style={{ position: 'relative', maxWidth: '100%', maxHeight: 420, width: `min(100%, ${(420 * ar).toFixed(1)}px)`, aspectRatio: `${w} / ${h}`, overflow: 'hidden', cursor: 'grab', border: '2px solid var(--accent)', borderRadius: 4, background: '#000', userSelect: 'none' }}>
          {nat && <img ref={imgRef} src={url} alt="" draggable={false} style={{ position: 'absolute', ...pct, maxWidth: 'none', pointerEvents: 'none' }} />}
          {/* rule-of-thirds */}
          <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
            {[1, 2].map(i => <div key={'v' + i} style={{ position: 'absolute', top: 0, bottom: 0, left: `${i * 33.333}%`, width: 1, background: 'rgba(255,255,255,.28)' }} />)}
            {[1, 2].map(i => <div key={'h' + i} style={{ position: 'absolute', left: 0, right: 0, top: `${i * 33.333}%`, height: 1, background: 'rgba(255,255,255,.28)' }} />)}
          </div>
        </div>
      </div>
      {/* toolbar: aspect presets + zoom */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '14px 22px', borderTop: '1px solid var(--border-default)' }}>
        <div style={{ display: 'flex', gap: 8 }}>
          {CROP_RATIOS.map(r => {
            const on = aspect === r.id;
            const box = r.id === 'wide' ? { w: 24, h: 15 } : r.id === 'square' ? { w: 19, h: 19 } : { w: 16, h: 21 };
            return (
              <button key={r.id} onClick={() => setAspect(r.id)} title={(window.__isX ? r.x : r.w)}
                style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, border: 'none', background: 'transparent', cursor: 'pointer', padding: '4px 6px', borderRadius: 8 }}>
                <span style={{ width: 30, height: 26, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
                  <span style={{ width: box.w, height: box.h, borderRadius: 3, border: `2px solid ${on ? 'var(--accent)' : 'var(--fg-subdued)'}` }} />
                </span>
                <span style={{ fontSize: 11, fontWeight: 700, color: on ? 'var(--accent)' : 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>{window.__isX ? r.x : r.w}</span>
              </button>
            );
          })}
        </div>
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 10 }}>
          <button onClick={() => setZoom(z => Math.max(1, +(z - 0.2).toFixed(2)))} style={{ width: 30, height: 30, borderRadius: '50%', border: 'none', background: 'var(--gray-100)', color: 'var(--fg-body)', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}><span style={{ fontSize: 20, fontWeight: 700, lineHeight: 1 }}>−</span></button>
          <input type="range" min="1" max="4" step="0.01" value={zoom} onChange={e => setZoom(+e.target.value)} style={{ flex: 1, accentColor: 'var(--accent)' }} />
          <button onClick={() => setZoom(z => Math.min(4, +(z + 0.2).toFixed(2)))} style={{ width: 30, height: 30, borderRadius: '50%', border: 'none', background: 'var(--gray-100)', color: 'var(--fg-body)', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}><span style={{ fontSize: 18, fontWeight: 700, lineHeight: 1 }}>+</span></button>
        </div>
      </div>
    </div>
  );
}

function MediaEditor({ image, isX, onSave, onClose }) {
  const [tab, setTab] = React.useState(image._tab || 'crop');
  const [nat, setNat] = React.useState(null);
  const [aspect, setAspect] = React.useState('original');
  const [zoom, setZoom] = React.useState(1);
  const [crop, setCrop] = React.useState({ x: 0, y: 0 });
  const [dirtyCrop, setDirtyCrop] = React.useState(false);
  const [alt, setAlt] = React.useState(image.alt || '');
  const [warn, setWarn] = React.useState(image.warn || { nudity: false, violence: false, sensitive: false, ai: false });
  const [blockAI, setBlockAI] = React.useState(!!image.blockAI);
  const imgRef = React.useRef(null);
  window.__isX = isX;

  React.useEffect(() => {
    const im = new Image();
    im.onload = () => { const n = { w: im.naturalWidth, h: im.naturalHeight }; setNat(n); const d = cropDims(n, 'original', 1); setCrop({ x: (n.w - d.w) / 2, y: (n.h - d.h) / 2 }); };
    im.src = image.url;
  }, [image.url]);

  // recenter / reclamp when aspect or zoom changes
  const setAspectM = (a) => { setAspect(a); setDirtyCrop(true); if (nat) { const d = cropDims(nat, a, zoom); setCrop({ x: (nat.w - d.w) / 2, y: (nat.h - d.h) / 2 }); } };
  const setZoomM = (z) => { const nz = typeof z === 'function' ? z(zoom) : z; setZoom(nz); setDirtyCrop(true); if (nat) { const d = cropDims(nat, aspect, nz); setCrop(c => clampCrop(c.x, c.y, d.w, d.h, nat)); } };
  const setCropM = (c) => { setCrop(c); setDirtyCrop(true); };

  React.useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') { e.stopPropagation(); onClose(); } };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, []);

  const save = () => {
    const patch = { alt, warn, blockAI };
    if (dirtyCrop && nat && imgRef.current) {
      const d = cropDims(nat, aspect, zoom);
      const cw = Math.round(d.w), ch = Math.round(d.h);
      const c = document.createElement('canvas'); c.width = cw; c.height = ch;
      const ctx = c.getContext('2d');
      try { ctx.drawImage(imgRef.current, crop.x, crop.y, d.w, d.h, 0, 0, cw, ch); patch.url = c.toDataURL('image/jpeg', 0.92); } catch (e) { /* keep original */ }
    }
    onSave(patch);
  };

  const title = tab === 'crop' ? (isX ? 'Crop media' : '裁剪图片') : tab === 'alt' ? (isX ? 'Edit image description' : '编辑图片描述') : (isX ? 'Content warning' : '内容警告');
  const tabs = [
    { id: 'crop', icon: <Glyph name="image" size={20} /> },
    { id: 'alt', label: isX ? 'ALT' : '描述' },
    { id: 'flag', icon: <span style={{ display: 'inline-flex', width: 20, height: 20 }}><svg viewBox="0 0 20 20" width="100%" height="100%"><g fill="none" stroke="currentColor" strokeWidth="1.6"><path d="M5 2.6v15" strokeLinecap="round" /><path d="M5 3.4c2-1 3.6.6 5.4.6.9 0 1.7-.3 2.4-.7v6.3c-.7.4-1.5.7-2.4.7-1.8 0-3.4-1.5-5.4-.6" strokeLinejoin="round" /></g></svg></span> },
  ];

  return (
    <React.Fragment>
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, background: 'rgba(8,7,11,.6)', zIndex: 100 }} />
      <div style={{ position: 'fixed', left: '50%', top: '50%', transform: 'translate(-50%,-50%)', width: 640, maxWidth: '94vw', height: 700, maxHeight: '90vh', zIndex: 101, background: 'var(--bg-elevated)', borderRadius: 16, border: '1px solid var(--border-default)', boxShadow: '0 0 0 1px rgba(0,0,0,.28), 0 32px 84px rgba(0,0,0,.52)', display: 'flex', flexDirection: 'column', overflow: 'hidden', animation: 'winPop .2s var(--ease-default)' }}>
        {/* header */}
        <div style={{ height: 58, flex: 'none', display: 'flex', alignItems: 'center', gap: 12, padding: '0 18px' }}>
          <button onClick={onClose} title={isX ? 'Back' : '返回'} style={{ width: 34, height: 34, marginLeft: -6, borderRadius: '50%', border: 'none', background: 'transparent', color: 'var(--fg-heading)', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', transform: 'rotate(90deg)' }}
            onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-100)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}><Glyph name="chevron-down" size={20} /></button>
          <div style={{ flex: 1, fontSize: 20, fontWeight: 800, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', letterSpacing: '-.01em' }}>{title}</div>
          <button onClick={save} style={{ height: 36, padding: '0 18px', borderRadius: 9999, border: 'none', cursor: 'pointer', fontSize: 15, fontWeight: 700, fontFamily: 'var(--font-sans)', background: 'var(--fg-heading)', color: 'var(--bg-base)' }}>{isX ? 'Save' : '保存'}</button>
        </div>
        {/* tab strip */}
        <div style={{ display: 'flex', borderBottom: '1px solid var(--border-default)' }}>
          {tabs.map(t => {
            const on = tab === t.id;
            return (
              <button key={t.id} onClick={() => setTab(t.id)} style={{ flex: 1, height: 50, border: 'none', background: 'transparent', cursor: 'pointer', position: 'relative', color: on ? 'var(--accent)' : 'var(--fg-subdued)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 14, fontWeight: 800, fontFamily: 'var(--font-sans)' }}>
                {t.icon || t.label}
                {on && <span style={{ position: 'absolute', bottom: 0, left: '50%', transform: 'translateX(-50%)', width: 56, height: 3.5, borderRadius: 9999, background: 'var(--accent)' }} />}
              </button>
            );
          })}
        </div>
        {/* body */}
        <div className="col-scroll" style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', overflowY: tab === 'crop' ? 'hidden' : 'auto' }}>
          {tab === 'crop' && <CropTab url={image.url} nat={nat} aspect={aspect} setAspect={setAspectM} zoom={zoom} setZoom={setZoomM} crop={crop} setCrop={setCropM} imgRef={imgRef} />}
          {tab === 'alt' && (
            <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
              <div style={{ flex: 1, minHeight: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 22, background: 'var(--bg-pasteboard, #0b0a0e)' }}>
                <img src={image.url} alt="" style={{ maxWidth: '100%', maxHeight: 380, borderRadius: 8, display: 'block' }} />
              </div>
              <div style={{ padding: '16px 22px', borderTop: '1px solid var(--border-default)' }}>
                <div style={{ position: 'relative', border: '2px solid var(--accent)', borderRadius: 10, padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
                    <span style={{ fontSize: 13, color: 'var(--accent)', fontWeight: 600, fontFamily: 'var(--font-sans)' }}>{isX ? 'Description' : '描述'}</span>
                    <span style={{ fontSize: 13, color: 'var(--fg-subdued)', fontVariantNumeric: 'tabular-nums', fontFamily: 'var(--font-sans)' }}>{alt.length} / 1,000</span>
                  </div>
                  <textarea autoFocus value={alt} maxLength={1000} onChange={e => setAlt(e.target.value)} rows={3}
                    placeholder={isX ? 'Describe this image for people who are blind or have low vision…' : '为视障人士描述这张图片…'}
                    style={{ width: '100%', boxSizing: 'border-box', resize: 'none', border: 'none', outline: 'none', background: 'none', fontSize: 16, lineHeight: 1.5, fontFamily: 'var(--font-sans)', color: 'var(--fg-body)' }} />
                </div>
                <button style={{ marginTop: 12, border: 'none', background: 'transparent', color: 'var(--accent)', cursor: 'pointer', fontSize: 14, fontWeight: 600, fontFamily: 'var(--font-sans)', padding: 0 }}>{isX ? 'What is alt text?' : '什么是替代文本？'}</button>
              </div>
            </div>
          )}
          {tab === 'flag' && (
            <div>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 22, background: 'var(--bg-pasteboard, #0b0a0e)' }}>
                <img src={image.url} alt="" style={{ maxWidth: 340, maxHeight: 300, borderRadius: 8, display: 'block' }} />
              </div>
              <div style={{ padding: '18px 22px 8px' }}>
                <div style={{ fontSize: 19, fontWeight: 800, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', letterSpacing: '-.01em', marginBottom: 6 }}>{isX ? 'Put a content warning on this post' : '为此帖子添加内容警告'}</div>
                <div style={{ fontSize: 14, color: 'var(--fg-subdued)', lineHeight: 1.45, fontFamily: 'var(--font-sans)' }}>{isX ? 'Select a category, and we’ll add a content warning. This helps people avoid content they don’t want to see.' : '选择一个类别，我们会为此帖子添加内容警告，帮助他人避开不想看到的内容。'}</div>
              </div>
              {WARN_CATS.map(c => (
                <button key={c.id} onClick={() => setWarn(w => ({ ...w, [c.id]: !w[c.id] }))}
                  style={{ display: 'flex', alignItems: 'center', gap: 14, width: '100%', padding: '16px 22px', border: 'none', borderTop: '1px solid var(--border-default)', background: 'transparent', cursor: 'pointer', textAlign: 'left' }}
                  onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-75)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
                  <span style={{ flex: 1, fontSize: 16, fontWeight: 600, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)' }}>{isX ? c.x : c.w}</span>
                  <span style={{ width: 24, height: 24, borderRadius: 6, flex: 'none', border: warn[c.id] ? 'none' : '2px solid var(--gray-400)', background: warn[c.id] ? 'var(--accent-bg)' : 'transparent', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}>{warn[c.id] && <Glyph name="checkmark" size={15} />}</span>
                </button>
              ))}
              <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '18px 22px', borderTop: '1px solid var(--border-default)' }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)' }}>{isX ? 'Block AI modifications' : '禁止 AI 修改'}</div>
                  <div style={{ marginTop: 4, fontSize: 14, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>{isX ? 'Prevent AI tools from altering this media.' : '禁止 AI 工具修改此媒体。'}</div>
                </div>
                <ToggleSwitch on={blockAI} onChange={setBlockAI} />
              </div>
            </div>
          )}
        </div>
      </div>
    </React.Fragment>
  );
}

/* ── poll editor (add/remove options, image options, length) ── */
function PollChoiceImg({ choice, onPick, onClear, isX }) {
  const ref = React.useRef(null);
  const handle = (e) => { const f = e.target.files && e.target.files[0]; if (!f) return; const r = new FileReader(); r.onload = () => onPick(r.result); r.readAsDataURL(f); e.target.value = ''; };
  if (choice.img) {
    return (
      <div style={{ position: 'relative', width: 88, height: 88, flex: 'none', borderRadius: 10, overflow: 'hidden', border: '1px solid var(--border-default)' }}>
        <img src={choice.img} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
        <button onClick={onClear} style={{ position: 'absolute', top: 5, right: 5, width: 24, height: 24, borderRadius: '50%', border: 'none', background: 'rgba(15,14,18,.72)', color: '#fff', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}><Glyph name="close" size={13} /></button>
      </div>
    );
  }
  return (
    <button onClick={() => ref.current && ref.current.click()} title={isX ? 'Add image' : '添加图片'}
      style={{ width: 44, height: 44, flex: 'none', alignSelf: 'center', borderRadius: 10, border: '1.5px dashed var(--gray-400)', background: 'transparent', color: 'var(--fg-subdued)', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}
      onMouseEnter={e => { e.currentTarget.style.background = 'var(--gray-75)'; e.currentTarget.style.color = 'var(--accent)'; }}
      onMouseLeave={e => { e.currentTarget.style.background = 'transparent'; e.currentTarget.style.color = 'var(--fg-subdued)'; }}>
      <Glyph name="image" size={20} />
      <input ref={ref} type="file" accept="image/*" onChange={handle} style={{ display: 'none' }} />
    </button>
  );
}

function PollField({ choice, idx, total, onText, onImg, onClearImg, onRemove, isX }) {
  return (
    <div style={{ display: 'flex', alignItems: 'stretch', gap: 12 }}>
      <PollChoiceImg choice={choice} onPick={onImg} onClear={onClearImg} isX={isX} />
      <div style={{ position: 'relative', flex: 1, minWidth: 0 }}>
        <label style={{ position: 'absolute', top: 9, left: 13, fontSize: 12.5, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', pointerEvents: 'none' }}>{isX ? `Choice ${idx + 1}` : `选项 ${idx + 1}`}{idx >= 2 ? (isX ? ' (optional)' : '（选填）') : ''}</label>
        <input value={choice.text} maxLength={25} onChange={e => onText(e.target.value)}
          style={{ width: '100%', boxSizing: 'border-box', height: 64, padding: '26px 64px 8px 13px', borderRadius: 8, border: '1px solid var(--border-default)', background: 'var(--bg-base)', color: 'var(--fg-body)', fontSize: 16, fontFamily: 'var(--font-sans)', outline: 'none' }}
          onFocus={e => e.currentTarget.style.borderColor = 'var(--accent)'} onBlur={e => e.currentTarget.style.borderColor = 'var(--border-default)'} />
        <span style={{ position: 'absolute', right: total > 2 ? 44 : 13, top: '50%', transform: 'translateY(-50%)', fontSize: 12, color: 'var(--fg-disabled)', fontVariantNumeric: 'tabular-nums' }}>{choice.text.length}/25</span>
        {total > 2 && (
          <button onClick={onRemove} title={isX ? 'Remove choice' : '删除选项'}
            style={{ position: 'absolute', right: 9, top: '50%', transform: 'translateY(-50%)', width: 28, height: 28, borderRadius: 8, border: 'none', background: 'transparent', color: 'var(--fg-subdued)', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}
            onMouseEnter={e => { e.currentTarget.style.background = 'color-mix(in srgb, var(--negative) 14%, transparent)'; e.currentTarget.style.color = 'var(--negative)'; }}
            onMouseLeave={e => { e.currentTarget.style.background = 'transparent'; e.currentTarget.style.color = 'var(--fg-subdued)'; }}>
            <Glyph name="close" size={16} />
          </button>
        )}
      </div>
    </div>
  );
}

function PollEditor({ poll, setPoll, onRemove, isX }) {
  const setChoice = (id, patch) => setPoll(p => ({ ...p, choices: p.choices.map(c => c.id === id ? { ...c, ...patch } : c) }));
  const addChoice = () => setPoll(p => p.choices.length >= 4 ? p : ({ ...p, choices: [...p.choices, { id: 'ch' + Date.now(), text: '', img: null }] }));
  const removeChoice = (id) => setPoll(p => ({ ...p, choices: p.choices.filter(c => c.id !== id) }));
  const DAYS = Array.from({ length: 8 }, (_, i) => ({ value: i, label: String(i) }));
  const HOURS = Array.from({ length: 24 }, (_, i) => ({ value: i, label: String(i) }));
  const MINS = Array.from({ length: 60 }, (_, i) => ({ value: i, label: String(i) }));
  return (
    <div style={{ marginTop: 12, borderRadius: 16, border: '1px solid var(--border-default)', overflow: 'hidden' }}>
      <div style={{ padding: 16, display: 'flex', flexDirection: 'column', gap: 12 }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
          <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 12 }}>
            {poll.choices.map((c, i) => (
              <PollField key={c.id} choice={c} idx={i} total={poll.choices.length} isX={isX}
                onText={v => setChoice(c.id, { text: v })} onImg={url => setChoice(c.id, { img: url })}
                onClearImg={() => setChoice(c.id, { img: null })} onRemove={() => removeChoice(c.id)} />
            ))}
          </div>
          {poll.choices.length < 4 && (
            <button onClick={addChoice} title={isX ? 'Add a choice' : '添加选项'}
              style={{ width: 34, height: 34, flex: 'none', alignSelf: 'center', borderRadius: '50%', border: 'none', background: 'transparent', color: 'var(--accent)', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}
              onMouseEnter={e => e.currentTarget.style.background = 'color-mix(in srgb, var(--accent) 14%, transparent)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
              <Glyph name="add" size={21} />
            </button>
          )}
        </div>
      </div>
      <div style={{ borderTop: '1px solid var(--border-default)', padding: 16, display: 'flex', flexDirection: 'column', gap: 12 }}>
        <div style={{ fontSize: 15, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)' }}>{isX ? 'Poll length' : '投票时长'}</div>
        <div style={{ display: 'flex', gap: 12 }}>
          <BoxSelect label={isX ? 'Days' : '天'} value={poll.days} options={DAYS} onChange={v => setPoll(p => ({ ...p, days: v }))} />
          <BoxSelect label={isX ? 'Hours' : '小时'} value={poll.hours} options={HOURS} onChange={v => setPoll(p => ({ ...p, hours: v }))} />
          <BoxSelect label={isX ? 'Minutes' : '分钟'} value={poll.minutes} options={MINS} onChange={v => setPoll(p => ({ ...p, minutes: v }))} />
        </div>
      </div>
      <button onClick={onRemove}
        style={{ width: '100%', height: 50, border: 'none', borderTop: '1px solid var(--border-default)', background: 'transparent', color: 'var(--negative)', cursor: 'pointer', fontSize: 15, fontWeight: 700, fontFamily: 'var(--font-sans)' }}
        onMouseEnter={e => e.currentTarget.style.background = 'color-mix(in srgb, var(--negative) 10%, transparent)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
        {isX ? 'Remove poll' : '移除投票'}
      </button>
    </div>
  );
}

/* ── boxed floating-label select (used by poll + schedule) ── */
function BoxSelect({ label, value, options, onChange, width }) {
  const cur = options.find(o => String(o.value) === String(value));
  return (
    <label style={{ position: 'relative', flex: width ? 'none' : 1, width, minWidth: 0, height: 64, borderRadius: 8, border: '1px solid var(--border-default)', background: 'var(--bg-base)', padding: '0 14px', display: 'flex', flexDirection: 'column', justifyContent: 'center', cursor: 'pointer' }}>
      <span style={{ fontSize: 12.5, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>{label}</span>
      <span style={{ fontSize: 18, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', paddingRight: 18 }}>{cur ? cur.label : ''}</span>
      <span style={{ position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%)', color: 'var(--fg-subdued)', pointerEvents: 'none', display: 'inline-flex', width: 18, height: 18 }}><Glyph name="chevron-down" size={18} /></span>
      <select value={value} onChange={e => onChange(isNaN(+e.target.value) ? e.target.value : +e.target.value)}
        style={{ position: 'absolute', inset: 0, opacity: 0, width: '100%', height: '100%', border: 'none', cursor: 'pointer', fontFamily: 'var(--font-sans)' }}>
        {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
    </label>
  );
}

/* ── who can reply ── */
const REPLY_SCOPES = [
  { id: 'everyone', icon: 'globe', x: 'Everyone', w: '所有人' },
  { id: 'following', icon: 'follow', x: 'Accounts you follow', w: '你关注的账号' },
  { id: 'mentioned', icon: 'at', x: 'Only accounts you mention', w: '仅提及的账号' },
  { id: 'verified', icon: 'badge', x: 'Verified accounts', w: '认证账号' },
];
function scopeIcon(name, size) {
  if (name === 'at') return <AtGlyph size={size} />;
  if (name === 'follow') return <FollowGlyph size={size} />;
  if (name === 'badge') return <BadgeGlyph size={size} />;
  return <Glyph name="globe" size={size} />;
}
function scopeLabel(id, isX) { const s = REPLY_SCOPES.find(x => x.id === id) || REPLY_SCOPES[0]; return isX ? s.x : s.w; }

function ReplyScopeMenu({ value, onPick, onClose, isX }) {
  return (
    <React.Fragment>
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 64 }} />
      <div style={{ position: 'absolute', top: 34, left: 0, width: 340, maxWidth: '88vw', background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', borderRadius: 16, boxShadow: 'var(--shadow-elevated)', padding: '14px 6px 8px', zIndex: 65 }}>
        <div style={{ fontSize: 19, fontWeight: 800, color: 'var(--fg-heading)', padding: '0 14px 8px', fontFamily: 'var(--font-sans)', letterSpacing: '-.01em' }}>{isX ? 'Who can reply?' : '谁可以回复？'}</div>
        {REPLY_SCOPES.map(s => {
          const on = s.id === value;
          return (
            <button key={s.id} onClick={() => { onPick(s.id); onClose(); }}
              style={{ display: 'flex', alignItems: 'center', gap: 14, width: '100%', padding: '11px 14px', border: 'none', background: 'transparent', cursor: 'pointer', textAlign: 'left', borderRadius: 10 }}
              onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-75)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
              <span style={{ width: 40, height: 40, borderRadius: '50%', flex: 'none', background: on ? 'var(--accent-bg)' : 'var(--gray-200)', color: on ? '#fff' : 'var(--fg-heading)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>{scopeIcon(s.icon, 21)}</span>
              <span style={{ flex: 1, fontSize: 16, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)' }}>{isX ? s.x : s.w}</span>
              <span style={{ width: 24, height: 24, borderRadius: '50%', flex: 'none', border: on ? 'none' : '2px solid var(--gray-400)', background: on ? 'var(--accent-bg)' : 'transparent', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}>{on && <Glyph name="checkmark" size={15} />}</span>
            </button>
          );
        })}
      </div>
    </React.Fragment>
  );
}

/* ── generic centered dialog shell (header action + body) ── */
function SheetDialog({ title, action, onAction, actionDisabled, onClose, leadingClose, width = 560, children }) {
  return (
    <React.Fragment>
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, background: 'rgba(8,7,11,.55)', zIndex: 96 }} />
      <div style={{ position: 'fixed', left: '50%', top: '50%', transform: 'translate(-50%,-50%)', width, maxWidth: '94vw', maxHeight: '88vh', zIndex: 97, background: 'var(--bg-elevated)', borderRadius: 16, border: '1px solid var(--border-default)', boxShadow: '0 0 0 1px rgba(0,0,0,.28), 0 32px 84px rgba(0,0,0,.52)', display: 'flex', flexDirection: 'column', overflow: 'hidden', animation: 'winPop .2s var(--ease-default)' }}>
        <div style={{ height: 58, flex: 'none', display: 'flex', alignItems: 'center', gap: 14, padding: '0 18px', borderBottom: '1px solid var(--border-default)' }}>
          {leadingClose && (
            <button onClick={onClose} style={{ width: 34, height: 34, marginLeft: -6, borderRadius: '50%', border: 'none', background: 'transparent', color: 'var(--fg-heading)', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}
              onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-100)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}><Glyph name="close" size={19} /></button>
          )}
          <div style={{ flex: 1, fontSize: 20, fontWeight: 800, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', letterSpacing: '-.01em' }}>{title}</div>
          {action && (
            <button onClick={onAction} disabled={actionDisabled}
              style={{ height: 36, padding: '0 18px', borderRadius: 9999, border: 'none', cursor: actionDisabled ? 'default' : 'pointer', fontSize: 15, fontWeight: 700, fontFamily: 'var(--font-sans)',
                background: action.solid ? (actionDisabled ? 'var(--gray-100)' : 'var(--fg-heading)') : 'transparent',
                color: action.solid ? (actionDisabled ? 'var(--fg-disabled)' : 'var(--bg-base)') : (actionDisabled ? 'var(--fg-disabled)' : 'var(--accent)') }}>{action.label}</button>
          )}
        </div>
        <div className="col-scroll" style={{ flex: 1, minHeight: 0, overflowY: 'auto' }}>{children}</div>
      </div>
    </React.Fragment>
  );
}

/* ── schedule dialog ── */
const MONTHS_X = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const MONTHS_W = ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'];
function daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate(); }
function partsToDate(p) { let h = p.h % 12; if (p.ap === 'PM') h += 12; return new Date(p.y, p.mo, p.d, h, p.mi); }
function fmtWhen(date, isX) {
  if (isX) return date.toLocaleString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true });
  return date.toLocaleString('zh-CN', { month: 'long', day: 'numeric', weekday: 'short', hour: '2-digit', minute: '2-digit', hour12: false });
}
function tzName() { try { return new Intl.DateTimeFormat('en-US', { timeZoneName: 'long' }).formatToParts(new Date()).find(p => p.type === 'timeZoneName').value; } catch (e) { return 'Local time'; } }

function ScheduleDialog({ isX, initial, onConfirm, onClose, onOpenDrafts }) {
  const base = initial || new Date(Date.now() + 60 * 60 * 1000);
  const h24 = base.getHours();
  const [p, setP] = React.useState({ mo: base.getMonth(), d: base.getDate(), y: base.getFullYear(), h: ((h24 % 12) || 12), mi: base.getMinutes(), ap: h24 >= 12 ? 'PM' : 'AM' });
  const thisYear = new Date().getFullYear();
  const date = partsToDate(p);
  const valid = date.getTime() > Date.now() + 60 * 1000;
  const set = (patch) => setP(prev => { const next = { ...prev, ...patch }; const dim = daysInMonth(next.y, next.mo); if (next.d > dim) next.d = dim; return next; });
  const MO = MONTHS_X.map((m, i) => ({ value: i, label: isX ? m : MONTHS_W[i] }));
  const DD = Array.from({ length: daysInMonth(p.y, p.mo) }, (_, i) => ({ value: i + 1, label: String(i + 1) }));
  const YY = [thisYear, thisYear + 1].map(y => ({ value: y, label: String(y) }));
  const HH = Array.from({ length: 12 }, (_, i) => ({ value: i + 1, label: String(i + 1) }));
  const MM = Array.from({ length: 60 }, (_, i) => ({ value: i, label: String(i).padStart(2, '0') }));
  const AP = [{ value: 'AM', label: 'AM' }, { value: 'PM', label: 'PM' }];
  return (
    <SheetDialog title={isX ? 'Schedule' : '定时发布'} leadingClose onClose={onClose}
      action={{ label: isX ? 'Confirm' : '确定', solid: true }} actionDisabled={!valid} onAction={() => onConfirm(date)} width={620}>
      <div style={{ padding: '18px 22px 22px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 9, color: valid ? 'var(--fg-subdued)' : 'var(--negative)', marginBottom: 22 }}>
          <SchedGlyph size={20} />
          <span style={{ fontSize: 15, fontFamily: 'var(--font-sans)' }}>{valid ? (isX ? `Will send on ${fmtWhen(date, true)}` : `将于 ${fmtWhen(date, false)} 发送`) : (isX ? 'Pick a time in the future' : '请选择未来的时间')}</span>
        </div>
        <div style={{ fontSize: 14, color: 'var(--fg-subdued)', marginBottom: 8, fontFamily: 'var(--font-sans)' }}>{isX ? 'Date' : '日期'}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 22 }}>
          <BoxSelect label={isX ? 'Month' : '月'} value={p.mo} options={MO} onChange={v => set({ mo: v })} />
          <BoxSelect label={isX ? 'Day' : '日'} value={p.d} options={DD} onChange={v => set({ d: v })} width={120} />
          <BoxSelect label={isX ? 'Year' : '年'} value={p.y} options={YY} onChange={v => set({ y: v })} width={150} />
          <span style={{ color: 'var(--fg-subdued)', flex: 'none' }}><Glyph name="calendar" size={26} /></span>
        </div>
        <div style={{ fontSize: 14, color: 'var(--fg-subdued)', marginBottom: 8, fontFamily: 'var(--font-sans)' }}>{isX ? 'Time' : '时间'}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 22 }}>
          <BoxSelect label={isX ? 'Hour' : '时'} value={p.h} options={HH} onChange={v => set({ h: v })} />
          <BoxSelect label={isX ? 'Minute' : '分'} value={p.mi} options={MM} onChange={v => set({ mi: v })} />
          <BoxSelect label="AM/PM" value={p.ap} options={AP} onChange={v => set({ ap: v })} />
          <span style={{ color: 'var(--fg-subdued)', flex: 'none' }}><ClockGlyph size={26} /></span>
        </div>
        <div style={{ fontSize: 14, color: 'var(--fg-subdued)', marginBottom: 4, fontFamily: 'var(--font-sans)' }}>{isX ? 'Time zone' : '时区'}</div>
        <div style={{ fontSize: 20, color: 'var(--fg-heading)', fontWeight: 600, fontFamily: 'var(--font-sans)' }}>{tzName()}</div>
      </div>
      <button onClick={onOpenDrafts}
        style={{ width: '100%', textAlign: 'left', padding: '16px 22px', border: 'none', borderTop: '1px solid var(--border-default)', background: 'transparent', color: 'var(--accent)', cursor: 'pointer', fontSize: 15, fontWeight: 700, fontFamily: 'var(--font-sans)' }}
        onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-75)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
        {isX ? 'Scheduled posts' : '查看定时任务'}
      </button>
    </SheetDialog>
  );
}

/* ── content disclosure ── */
function ToggleSwitch({ on, onChange }) {
  return (
    <button onClick={() => onChange(!on)} role="switch" aria-checked={on}
      style={{ width: 50, height: 30, flex: 'none', borderRadius: 9999, border: 'none', cursor: 'pointer', padding: 3, background: on ? 'var(--accent-bg)' : 'var(--gray-400)', transition: 'background .15s var(--ease-default)', display: 'inline-flex', justifyContent: on ? 'flex-end' : 'flex-start' }}>
      <span style={{ width: 24, height: 24, borderRadius: '50%', background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,.3)', transition: 'all .15s var(--ease-default)' }} />
    </button>
  );
}
function DisclosureRow({ title, desc, learn, on, onChange, isX }) {
  return (
    <div style={{ padding: '18px 0' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
        <div style={{ flex: 1, fontSize: 17, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)' }}>{title}</div>
        <ToggleSwitch on={on} onChange={onChange} />
      </div>
      <div style={{ marginTop: 6, fontSize: 14, color: 'var(--fg-subdued)', lineHeight: 1.45, fontFamily: 'var(--font-sans)', maxWidth: 520 }}>
        {desc}{learn && <span style={{ color: 'var(--accent)', cursor: 'pointer' }}> {isX ? 'Learn more' : '了解更多'}</span>}
      </div>
    </div>
  );
}
function DisclosureDialog({ isX, value, onChange, onClose }) {
  return (
    <SheetDialog title={isX ? 'Content disclosure' : '内容披露'} action={{ label: isX ? 'Done' : '完成' }} onAction={onClose} onClose={onClose} width={580}>
      <div style={{ padding: '6px 22px 18px' }}>
        <DisclosureRow isX={isX} on={value.paid} onChange={v => onChange({ ...value, paid: v })}
          title={isX ? 'Paid partnership' : '付费合作'} learn
          desc={isX ? 'Let others know this post promotes a brand or business.' : '让他人知道该帖子在推广某个品牌或商家。'} />
        <div style={{ height: 1, background: 'var(--border-default)' }} />
        <DisclosureRow isX={isX} on={value.ai} onChange={v => onChange({ ...value, ai: v })}
          title={isX ? 'Made with AI' : 'AI 生成'}
          desc={isX ? 'Mark this post as containing synthetically generated content.' : '标记该帖子包含由 AI 合成生成的内容。'} />
      </div>
    </SheetDialog>
  );
}

/* ── drafts / scheduled window ── */
function DraftsDialog({ isX, onClose, onEdit }) {
  const [tab, setTab] = React.useState('scheduled');
  const [, force] = React.useReducer(x => x + 1, 0);
  const items = ScheduleStore.all();
  const del = (id) => { ScheduleStore.remove(id); force(); };
  return (
    <React.Fragment>
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, background: 'rgba(8,7,11,.55)', zIndex: 98 }} />
      <div style={{ position: 'fixed', left: '50%', top: '50%', transform: 'translate(-50%,-50%)', width: 600, maxWidth: '94vw', height: 560, maxHeight: '88vh', zIndex: 99, background: 'var(--bg-elevated)', borderRadius: 16, border: '1px solid var(--border-default)', boxShadow: '0 0 0 1px rgba(0,0,0,.28), 0 32px 84px rgba(0,0,0,.52)', display: 'flex', flexDirection: 'column', overflow: 'hidden', animation: 'winPop .2s var(--ease-default)' }}>
        <div style={{ height: 58, flex: 'none', display: 'flex', alignItems: 'center', gap: 12, padding: '0 18px' }}>
          <button onClick={onClose} title={isX ? 'Back' : '返回'} style={{ width: 34, height: 34, marginLeft: -6, borderRadius: '50%', border: 'none', background: 'transparent', color: 'var(--fg-heading)', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', transform: 'rotate(90deg)' }}
            onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-100)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}><Glyph name="chevron-down" size={20} /></button>
          <div style={{ flex: 1, fontSize: 20, fontWeight: 800, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', letterSpacing: '-.01em' }}>{isX ? 'Drafts' : '草稿箱'}</div>
        </div>
        <div style={{ display: 'flex', borderBottom: '1px solid var(--border-default)' }}>
          {[['unsent', isX ? 'Unsent posts' : '草稿'], ['scheduled', isX ? 'Scheduled' : '定时任务']].map(([id, lbl]) => {
            const on = tab === id;
            return (
              <button key={id} onClick={() => setTab(id)} style={{ flex: 1, height: 50, border: 'none', background: 'transparent', cursor: 'pointer', position: 'relative', fontSize: 15, fontWeight: on ? 800 : 600, color: on ? 'var(--fg-heading)' : 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>
                {lbl}
                {on && <span style={{ position: 'absolute', bottom: 0, left: '50%', transform: 'translateX(-50%)', width: 52, height: 3.5, borderRadius: 9999, background: 'var(--accent)' }} />}
              </button>
            );
          })}
        </div>
        <div className="col-scroll" style={{ flex: 1, minHeight: 0, overflowY: 'auto' }}>
          {tab === 'unsent' || items.length === 0 ? (
            <div style={{ padding: '52px 40px', textAlign: 'center' }}>
              <div style={{ fontFamily: 'var(--font-serif)', fontSize: 30, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.02em', marginBottom: 10 }}>{tab === 'unsent' ? (isX ? 'Hold that thought' : '先放一放') : (isX ? 'Nothing scheduled' : '没有定时任务')}</div>
              <div style={{ fontSize: 15, color: 'var(--fg-subdued)', lineHeight: 1.5, fontFamily: 'var(--font-sans)', maxWidth: 360, margin: '0 auto' }}>{tab === 'unsent' ? (isX ? 'Not ready to post just yet? Save it to your drafts or schedule it for later.' : '还没想好就先存草稿，或定时稍后发布。') : (isX ? 'Posts you schedule will show up here until they send.' : '你设置的定时帖子会显示在这里，直到发送。')}</div>
            </div>
          ) : (
            items.map(it => {
              const itx = it.platform === 'x';
              return (
                <div key={it.id} style={{ padding: '14px 18px', borderBottom: '1px solid var(--border-default)', display: 'flex', gap: 12, alignItems: 'flex-start' }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: 'var(--fg-subdued)', marginBottom: 6 }}>
                      <SchedGlyph size={17} />
                      <span style={{ fontSize: 13.5, fontFamily: 'var(--font-sans)' }}>{itx ? `Will send on ${fmtWhen(new Date(it.when), true)}` : `将于 ${fmtWhen(new Date(it.when), false)} 发送`}</span>
                    </div>
                    <div style={{ fontSize: 15.5, color: 'var(--fg-body)', lineHeight: 1.5, fontFamily: 'var(--font-sans)', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>{it.text || (it.hasPoll ? (itx ? '(poll)' : '（投票）') : (itx ? '(media post)' : '（图片）'))}</div>
                    {it.images ? <div style={{ marginTop: 8, fontSize: 12.5, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>{itx ? `${it.images} image${it.images > 1 ? 's' : ''} attached` : `已附带 ${it.images} 张图片`}</div> : null}
                  </div>
                  <button onClick={() => del(it.id)} title={isX ? 'Delete' : '删除'}
                    style={{ width: 32, height: 32, flex: 'none', borderRadius: 8, border: 'none', background: 'var(--gray-100)', color: 'var(--fg-subdued)', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}
                    onMouseEnter={e => { e.currentTarget.style.background = 'color-mix(in srgb, var(--negative) 14%, transparent)'; e.currentTarget.style.color = 'var(--negative)'; }}
                    onMouseLeave={e => { e.currentTarget.style.background = 'var(--gray-100)'; e.currentTarget.style.color = 'var(--fg-subdued)'; }}>
                    <span style={{ display: 'inline-flex', width: 16, height: 16 }}><svg viewBox="0 0 20 20" width="100%" height="100%"><g fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d="M4 5.5h12M8 5.5V4a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v1.5M6.2 5.5l.6 9.2a1.5 1.5 0 0 0 1.5 1.4h3.4a1.5 1.5 0 0 0 1.5-1.4l.6-9.2" /></g></svg></span>
                  </button>
                </div>
              );
            })
          )}
        </div>
      </div>
    </React.Fragment>
  );
}

Object.assign(window, {
  ScheduleStore, activeToken, replaceToken, matchesFor, AutoComplete,
  ImageGrid, PollEditor, BoxSelect, REPLY_SCOPES, scopeIcon, scopeLabel, ReplyScopeMenu,
  ScheduleDialog, DisclosureDialog, DraftsDialog, ToggleSwitch, fmtWhen, MediaEditor,
  AtGlyph, FollowGlyph, BadgeGlyph, GifGlyph, ClockGlyph, SchedGlyph,
});

/* App shell: macOS window + icon rail + multi-column canvas + state. */
const { useState, useEffect, useRef } = React;

const LS = 'perch.v1';
const loadState = () => { try { return JSON.parse(localStorage.getItem(LS)) || {}; } catch (e) { return {}; } };

// Debug tweaks for the timeline lifecycle (loading / error / empty / refresh).
const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "tlState": "auto",
  "autoRefresh": true,
  "refreshSecs": 12,
  "failNext": false,
  "newPerTick": 6,
  "pageSize": 8,
  "loadMs": 900,
  "bmShape": "square",
  "bmCounts": true
}/*EDITMODE-END*/;

function TrafficLights() {
  const dot = (bg) => <span style={{ width: 12, height: 12, borderRadius: '50%', background: bg, boxShadow: 'inset 0 0 0 .5px rgba(0,0,0,.18)' }} />;
  return <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>{dot('#ff5f57')}{dot('#febc2e')}{dot('#28c840')}</div>;
}

function PlatformBadge({ platform, size = 16 }) {
  const isX = platform === 'x';
  return (
    <span style={{
      width: size, height: size, borderRadius: '50%', flex: 'none',
      background: isX ? 'var(--gray-1000)' : '#e6162d', color: '#fff',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontSize: isX ? size * 0.6 : size * 0.56, fontWeight: 800, fontFamily: 'var(--font-sans)',
      boxShadow: '0 0 0 2px var(--bg-layer-1)',
    }}>{isX ? '𝕏' : '微'}</span>
  );
}

/* Unread-count pill. `dot` renders a tiny ring-less dot when count is unknown but >0. */
function NotifBadge({ count, max = 99, ring = 'var(--bg-layer-1)', style, mini = false }) {
  if (!count) return null;
  const txt = count > max ? max + '+' : String(count);
  const wide = txt.length > 1;
  const h = mini ? 15 : 17;
  return (
    <span style={{
      minWidth: h, height: h, padding: wide ? `0 ${mini ? 3.5 : 4.5}px` : 0, borderRadius: 9999,
      background: 'var(--negative-bg)', color: '#fff',
      fontSize: mini ? 9.5 : 10.5, fontWeight: 800, fontFamily: 'var(--font-sans)', letterSpacing: '-.02em', lineHeight: 1,
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none',
      boxShadow: ring ? `0 0 0 2px ${ring}` : 'none', ...style,
    }}>{txt}</span>
  );
}

function RailAvatar({ account, active, onClick }) {
  const [h, setH] = useState(false);
  const sz = active ? 42 : 36;
  return (
    <button onClick={onClick} title={account.name} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ position: 'relative', border: 'none', background: 'none', padding: 0, cursor: 'pointer', display: 'flex', justifyContent: 'center', width: '100%', transition: 'transform .12s', transform: h && !active ? 'scale(1.06)' : 'scale(1)' }}>
      <span style={{ position: 'relative', display: 'inline-flex', borderRadius: '50%', padding: active ? 2 : 0, background: active ? 'var(--accent)' : 'transparent', opacity: active ? 1 : 0.62, filter: active ? 'none' : 'saturate(.85)', transition: 'opacity .12s' }}>
        <PAvatar person={account} size={sz} />
        <span style={{ position: 'absolute', right: -2, bottom: -2 }}><PlatformBadge platform={account.platform} size={active ? 17 : 15} /></span>
      </span>
    </button>
  );
}

function RailIcon({ name, active, onClick, title, accent, badge, dot }) {
  const [h, setH] = useState(false);
  return (
    <button onClick={onClick} title={title} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ position: 'relative', width: 44, height: 44, borderRadius: 12, border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', transition: 'background .12s, color .12s',
        background: accent ? 'var(--accent-bg)' : active ? 'var(--gray-200)' : h ? 'var(--gray-100)' : 'transparent',
        color: accent ? '#fff' : active ? 'var(--fg-heading)' : 'var(--fg-subdued)' }}>
      <span style={{ display: 'inline-flex', width: 22, height: 22 }}><Glyph name={name} size={22} /></span>
      {badge ? <span style={{ position: 'absolute', top: 1, right: 1 }}><NotifBadge count={badge} ring="var(--bg-layer-1)" /></span> : null}
      {dot && !badge ? <span style={{ position: 'absolute', top: 6, right: 6, width: 7, height: 7, borderRadius: '50%', background: 'var(--accent)', boxShadow: '0 0 0 2px var(--bg-layer-1)' }} /> : null}
    </button>
  );
}

const ADDABLE = ['home', 'mentions', 'search', 'bookmarks', 'likes', 'lists', 'profile'];

const EDIT_SEL = { height: 30, borderRadius: 8, border: '1px solid var(--border-default)', background: 'var(--bg-base)', color: 'var(--fg-body)', fontSize: 13, fontFamily: 'var(--font-sans)', fontWeight: 600, padding: '0 6px', cursor: 'pointer', minWidth: 0 };

function EditBtn({ icon, onClick, disabled, title, danger, rot }) {
  const [h, setH] = useState(false);
  return (
    <button title={title} onClick={onClick} disabled={disabled} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ width: 28, height: 28, borderRadius: 7, border: 'none', flex: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', cursor: disabled ? 'default' : 'pointer', background: h && !disabled ? 'var(--gray-200)' : 'var(--gray-100)', color: disabled ? 'var(--fg-disabled)' : danger ? 'var(--negative)' : 'var(--fg-subdued)' }}>
      <span style={{ display: 'inline-flex', width: 15, height: 15, transform: rot ? `rotate(${rot}deg)` : 'none' }}><Glyph name={icon} size={15} /></span>
    </button>
  );
}

const CARD_W = 210;

/* Type + account selectors shared by the fixed card and editable cards. */
function CardControls({ type, accountId, fallback, isX, cIsX, onType, onAccount }) {
  const acct = ACCOUNTS.find(a => a.id === accountId) || fallback;
  return (
    <div style={{ padding: 10, display: 'flex', flexDirection: 'column', gap: 8 }}>
      <label style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <span style={{ fontSize: 10.5, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.05em', color: 'var(--fg-subdued)' }}>{isX ? 'Type' : '类型'}</span>
        <select value={type} onChange={e => onType(e.target.value)} style={{ ...EDIT_SEL, width: '100%', height: 34 }}>
          {ADDABLE.map(t => <option key={t} value={t}>{cIsX ? COL_META[t].label_x : COL_META[t].label_w}</option>)}
        </select>
      </label>
      <label style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <span style={{ fontSize: 10.5, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.05em', color: 'var(--fg-subdued)' }}>{isX ? 'Account' : '账号'}</span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          <span style={{ position: 'relative', display: 'inline-flex', flex: 'none' }}>
            <PAvatar person={acct} size={24} />
            <span style={{ position: 'absolute', right: -3, bottom: -3 }}><PlatformBadge platform={acct.platform} size={12} /></span>
          </span>
          <select value={accountId || fallback.id} onChange={e => onAccount(e.target.value)} style={{ ...EDIT_SEL, flex: 1, height: 34 }}>
            {ACCOUNTS.map(a => <option key={a.id} value={a.id}>{a.name}{a.platform === 'x' ? ' · X' : ' · 微博'}</option>)}
          </select>
        </div>
      </label>
    </div>
  );
}

/* The insertion placeholder shown between columns while dragging. */
function DropSlot() {
  return (
    <div onDragOver={e => e.preventDefault()} style={{ width: 64, flex: 'none', borderRadius: 12, border: '2px dashed var(--accent)', background: 'color-mix(in srgb, var(--accent) 9%, transparent)', display: 'flex', alignItems: 'center', justifyContent: 'center', alignSelf: 'stretch' }}>
      <span style={{ width: 3, height: 'calc(100% - 24px)', borderRadius: 9999, background: 'var(--accent)', opacity: .5 }} />
    </div>
  );
}

/* A single editable (draggable) column card in the horizontal tray. */
function ColumnCard({ col, i, isX, active, onType, onAccount, onRemove, dragging, onDragStart, onDragOver, onDragEnd }) {
  const acct = ACCOUNTS.find(a => a.id === col.accountId) || active;
  const cIsX = acct.platform === 'x';
  const meta = COL_META[col.type] || COL_META.home;
  const [hClose, setHClose] = useState(false);
  if (dragging) return null; // hidden while dragging; a DropSlot stands in for it
  return (
    <div
      draggable
      onDragStart={e => { e.dataTransfer.effectAllowed = 'move'; onDragStart(); }}
      onDragOver={onDragOver}
      onDragEnd={onDragEnd}
      style={{
        width: CARD_W, flex: 'none', position: 'relative', borderRadius: 12,
        border: '1px solid var(--border-default)', background: 'var(--bg-base)',
        display: 'flex', flexDirection: 'column', overflow: 'hidden',
      }}>
      {/* card header mirrors the real column header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '8px 8px 8px 6px', borderBottom: '1px solid var(--border-default)', background: 'var(--bg-layer-1)' }}>
        <span title={isX ? 'Drag to reorder' : '拖动排序'} style={{ display: 'inline-flex', width: 18, height: 18, color: 'var(--fg-disabled)', cursor: 'grab', flex: 'none' }}><Glyph name="grip" size={18} /></span>
        <span style={{ display: 'inline-flex', width: 17, height: 17, color: 'var(--fg-heading)', flex: 'none' }}><Glyph name={meta.icon} size={17} /></span>
        <div style={{ flex: 1, minWidth: 0, fontSize: 13.5, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.01em', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{cIsX ? meta.label_x : meta.label_w}</div>
        <span style={{ fontSize: 10, fontWeight: 700, color: 'var(--fg-disabled)', flex: 'none' }}>{i + 1}</span>
        <button title={isX ? 'Remove column' : '移除分栏'} onClick={() => onRemove(col.id)} onMouseEnter={() => setHClose(true)} onMouseLeave={() => setHClose(false)}
          style={{ width: 24, height: 24, borderRadius: 7, border: 'none', flex: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', background: hClose ? 'color-mix(in srgb, var(--negative) 14%, transparent)' : 'transparent', color: hClose ? 'var(--negative)' : 'var(--fg-subdued)', transition: 'background .12s, color .12s' }}>
          <span style={{ display: 'inline-flex', width: 14, height: 14 }}><Glyph name="close" size={14} /></span>
        </button>
      </div>
      <CardControls type={col.type} accountId={col.accountId} fallback={active} isX={isX} cIsX={cIsX}
        onType={v => onType(col.id, v)} onAccount={v => onAccount(col.id, v)} />
    </div>
  );
}

function ColumnEditor({ columns, isX, active, onType, onAccount, onPrimaryType, onReorder, onRemove, onAdd }) {
  const [dragIdx, setDragIdx] = useState(null);   // index in columns of the card being dragged
  const [overIdx, setOverIdx] = useState(null);   // insertion index (1..columns.length)
  const reset = () => { setDragIdx(null); setOverIdx(null); };
  const dropAt = (insertIdx) => { if (dragIdx != null) onReorder(dragIdx, insertIdx); reset(); };
  // pointer left/right half of a card at columns-index ci -> insert before ci or after
  const overCard = (e, ci) => { e.preventDefault(); const r = e.currentTarget.getBoundingClientRect(); setOverIdx((e.clientX - r.left) < r.width / 2 ? ci : ci + 1); };

  const main = columns[0] || { id: 'c1', type: 'home' };
  const mainMeta = COL_META[main.type] || COL_META.home;
  const mainAcct = ACCOUNTS.find(a => a.id === main.accountId) || active;
  const dragging = dragIdx != null;

  return (
    <div style={{ display: 'flex', alignItems: 'stretch', gap: 12 }} onDragOver={e => { if (dragging) e.preventDefault(); }} onDrop={e => { if (dragging) { e.preventDefault(); dropAt(overIdx == null ? dragIdx : overIdx); } }} onDragEnd={reset}>
      {/* fixed (position-locked, but editable) card */}
      <div style={{ width: CARD_W, flex: 'none', borderRadius: 12, border: '1px solid var(--border-default)', background: 'var(--bg-base)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '8px 10px', borderBottom: '1px solid var(--border-default)', background: 'var(--bg-layer-1)' }}>
          <span style={{ display: 'inline-flex', width: 17, height: 17, color: 'var(--fg-heading)', flex: 'none' }}><Glyph name={mainMeta.icon} size={17} /></span>
          <div style={{ flex: 1, minWidth: 0, fontSize: 13.5, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.01em', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{(mainAcct.platform === 'x') ? mainMeta.label_x : mainMeta.label_w}</div>
          <span style={{ fontSize: 9.5, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.05em', color: 'var(--fg-subdued)', background: 'var(--gray-100)', borderRadius: 6, padding: '3px 6px', flex: 'none' }}>{isX ? 'Fixed' : '固定'}</span>
        </div>
        <CardControls type={main.type} accountId={main.accountId} fallback={active} isX={isX} cIsX={mainAcct.platform === 'x'}
          onType={onPrimaryType} onAccount={v => onAccount(main.id, v)} />
      </div>

      {/* editable cards, interleaved with the drop placeholder */}
      {columns.slice(1).map((col, k) => {
        const ci = k + 1;
        return (
          <React.Fragment key={col.id}>
            {dragging && overIdx === ci && <DropSlot />}
            <ColumnCard col={col} i={ci} isX={isX} active={active}
              onType={onType} onAccount={onAccount} onRemove={onRemove}
              dragging={dragIdx === ci}
              onDragStart={() => setTimeout(() => setDragIdx(ci), 0)} onDragOver={e => overCard(e, ci)}
              onDragEnd={reset} />
          </React.Fragment>
        );
      })}
      {dragging && overIdx === columns.length && <DropSlot />}

      {/* add card (also a drop target for "move to end") */}
      <button onClick={() => onAdd('home')}
        onDragOver={e => { if (dragging) { e.preventDefault(); setOverIdx(columns.length); } }}
        onMouseEnter={e => { e.currentTarget.style.background = 'var(--gray-75)'; e.currentTarget.style.borderColor = 'var(--gray-500)'; e.currentTarget.style.color = 'var(--fg-body)'; }}
        onMouseLeave={e => { e.currentTarget.style.background = 'transparent'; e.currentTarget.style.borderColor = 'var(--gray-400)'; e.currentTarget.style.color = 'var(--fg-subdued)'; }}
        style={{ width: 132, flex: 'none', borderRadius: 12, border: '1.5px dashed var(--gray-400)', background: 'transparent', color: 'var(--fg-subdued)', cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 8, fontFamily: 'var(--font-sans)', fontSize: 13, fontWeight: 700, transition: 'background .12s, border-color .12s, color .12s' }}>
        <span style={{ width: 34, height: 34, borderRadius: '50%', border: '1.5px solid currentColor', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}><span style={{ display: 'inline-flex', width: 18, height: 18 }}><Glyph name="add" size={18} /></span></span>
        {isX ? 'Add column' : '添加分栏'}
      </button>
    </div>
  );
}

function App() {
  const saved = loadState();
  const [themeMode, setThemeMode] = useState(saved.themeMode || saved.theme || 'dark');
  const [sysDark, setSysDark] = useState(() => !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches));
  const theme = themeMode === 'system' ? (sysDark ? 'dark' : 'light') : themeMode;
  const [prefs, setPrefs] = useState({ ...DEFAULT_PREFS, ...(saved.prefs || {}) });
  const [settingsOpen, setSettingsOpen] = useState(false);
  const setPref = (k, v) => setPrefs(p => ({ ...p, [k]: v }));
  const dbg = useDebug();
  const [activeId, setActiveId] = useState(saved.activeId || ACCOUNTS[0].id);
  const [columns, setColumns] = useState(saved.columns || [{ id: 'c1', type: 'home' }, { id: 'c2', type: 'home', accountId: 'aw1' }]);
  const [unread, setUnread] = useState(saved.unread || UNREAD_SEED);
  const [overrides, setOverrides] = useState(() => bookmarkSeedOverrides());
  // Bookmark folders (per platform) + per-post folder assignment.
  const [folders, setFolders] = useState(saved.folders || SEED_FOLDERS);
  const [bmFolder, setBmFolder] = useState(saved.bmFolder || SEED_ASSIGN);
  const addFolder = (plat, data) => { const id = 'f' + Date.now().toString(36); setFolders(f => ({ ...f, [plat]: [...(f[plat] || []), { id, ...data }] })); return id; };
  const updateFolder = (plat, id, patch) => setFolders(f => ({ ...f, [plat]: (f[plat] || []).map(x => x.id === id ? { ...x, ...patch } : x) }));
  const deleteFolder = (plat, id) => { setFolders(f => ({ ...f, [plat]: (f[plat] || []).filter(x => x.id !== id) })); setBmFolder(m => { const c = { ...m }; Object.keys(c).forEach(k => { if (c[k] === id) delete c[k]; }); return c; }); };
  const setPostFolder = (postId, folderId) => setBmFolder(m => { const c = { ...m }; if (folderId == null) delete c[postId]; else c[postId] = folderId; return c; });
  const [injected, setInjected] = useState({ x: [], weibo: [] });
  const [composeOpen, setComposeOpen] = useState(false);
  const [composeFrom, setComposeFrom] = useState(activeId);
  const [composeCtx, setComposeCtx] = useState(null);
  const [colNav, setColNav] = useState({});    // colId -> [pushed screens]
  const [replies, setReplies] = useState({});  // postId -> [reply, ...]
  const [addMenu, setAddMenu] = useState(false);
  const [acctMenu, setAcctMenu] = useState(false);
  const [moreMenu, setMoreMenu] = useState(false);
  // Configurable rail: which destinations live in the bar vs the ⋯ menu, + post-button placement.
  const [nav, setNav] = useState(() => normalizeNav(saved.nav || DEFAULT_NAV));
  const [navConfigOpen, setNavConfigOpen] = useState(false);
  const [colMenu, setColMenu] = useState(false);
  const [toast, setToast] = useState(null);
  const [added, setAdded] = useState(saved.added || []);
  const [addOpen, setAddOpen] = useState(false);
  const [addPlatform, setAddPlatform] = useState(null);
  const [media, setMedia] = useState(null); // { slides, index, author } — shared media viewer
  const openMedia = (slides, index, author) => { if (slides && slides.length) setMedia({ slides, index: index || 0, author }); };

  // ── Timeline lifecycle: per-column load status, refresh + new-post counts ──
  const [tweaks, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [colStatus, setColStatus] = useState({});      // colId -> 'loading' | 'ready' | 'error' | 'empty'
  const [colRefreshing, setColRefreshing] = useState({}); // colId -> false | 'manual' | 'soft'
  const [colReloadError, setColReloadError] = useState({}); // colId -> bool (warm reload failed, content preserved)
  const [colNew, setColNew] = useState({});            // colId -> count of new posts waiting on the server
  const [colView, setColView] = useState({});          // colId -> ordered view (posts + gap markers) for home columns
  const [colGapLoading, setColGapLoading] = useState({}); // gapId -> bool
  const tRef = useRef(tweaks); tRef.current = tweaks;
  const statusRef = useRef(colStatus); statusRef.current = colStatus;
  const viewRef = useRef(colView); viewRef.current = colView;
  const seenSigRef = useRef(new Set());  // signatures loaded ≥1× → re-entry is a WARM reload, not a cold skeleton
  const colGapLoadingRef = useRef({});  // gapId -> bool (sync guard against double-tap)
  const sigRef = useRef({});       // colId -> last (account:type:feed) signature
  const timersRef = useRef({});    // colId -> pending load timeout
  const scrollRef = useRef({});    // colId -> { last, acc } scroll bookkeeping

  // re-hydrate previously-added accounts into the global roster once
  const hydratedRef = useRef(false);
  if (!hydratedRef.current) {
    hydratedRef.current = true;
    (saved.added || []).forEach(a => { if (!ACCOUNTS.some(x => x.id === a.id)) ACCOUNTS.push(a); });
  }

  const active = ACCOUNTS.find(a => a.id === activeId) || ACCOUNTS[0];

  useEffect(() => { document.documentElement.setAttribute('data-theme', theme); }, [theme]);
  useEffect(() => { if (window.DebugBus) window.DebugBus.configure({ enabled: !!prefs.debug, jsonInline: prefs.debugJson !== false, netLog: prefs.debugNet !== false }); }, [prefs.debug, prefs.debugJson, prefs.debugNet]);
  useEffect(() => {
    if (!window.matchMedia) return;
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const fn = (e) => setSysDark(e.matches);
    mq.addEventListener ? mq.addEventListener('change', fn) : mq.addListener(fn);
    return () => { mq.removeEventListener ? mq.removeEventListener('change', fn) : mq.removeListener(fn); };
  }, []);
  useEffect(() => { localStorage.setItem(LS, JSON.stringify({ themeMode, prefs, activeId, columns, unread, added, folders, bmFolder, nav })); }, [themeMode, prefs, activeId, columns, unread, added, folders, bmFolder, nav]);
  useEffect(() => {
    const onKey = (e) => {
      const tag = (e.target.tagName || '').toLowerCase();
      if (tag === 'input' || tag === 'textarea') return;
      if (e.key === 'c' && !e.metaKey && !e.ctrlKey) { e.preventDefault(); openCompose(); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [activeId]);

  const findBase = (id) => {
    for (const plat of ['x', 'weibo']) {
      for (const p of injected[plat]) if (p.id === id) return p;
      for (const t of ['home', 'mentions']) { const arr = timelineFor(plat, t); for (const p of arr) if (p.id === id) return p; }
    }
    if (typeof notifPostById === 'function') { const np = notifPostById(id); if (np) return np; }
    if (typeof FeedStore !== 'undefined') { const fp = FeedStore.findById(id); if (fp) return fp; }
    return null;
  };
  const mergePost = (p) => {
    const o = overrides[p.id] || {};
    const liked = 'liked' in o ? o.liked : !!p.liked;
    const reposted = 'reposted' in o ? o.reposted : !!p.reposted;
    const bookmarked = 'bookmarked' in o ? o.bookmarked : !!p.bookmarked;
    const adj = (v, now, was) => typeof v === 'number' ? v + ((now ? 1 : 0) - (was ? 1 : 0)) : v;
    const repliesAdded = (replies[p.id] || []).length;
    const quotesAdded = injected.x.concat(injected.weibo).filter(x => x.quoteSrcId === p.id).length;
    return {
      ...p, liked, reposted, bookmarked,
      stats: {
        ...p.stats,
        likes: adj(p.stats.likes, liked, p.liked),
        reposts: adj(p.stats.reposts, reposted, p.reposted) + quotesAdded,
        replies: typeof p.stats.replies === 'number' ? p.stats.replies + repliesAdded : p.stats.replies,
      },
    };
  };
  const onAction = (id, field) => {
    const base = findBase(id);
    const cur = overrides[id] || {};
    const curVal = field in cur ? cur[field] : !!(base && base[field]);
    const next = !curVal;
    setOverrides(prev => { const c = prev[id] || {}; return { ...prev, [id]: { ...c, [field]: next } }; });
    dbgAction(id, base, field, next);
  };

  // account shown in a column: uses the column's own account, falling back to the active (sidebar) one
  const colAccount = (col) => (ACCOUNTS.find(a => a.id === col.accountId) || active);

  const postsFor = (col, i) => {
    const plat = colAccount(col, i).platform;
    let base = col.type === 'mentions' ? timelineFor(plat, 'mentions') : timelineFor(plat, 'home');
    if (col.type !== 'mentions') base = injected[plat].concat(base);
    let merged = base.map(mergePost);
    if (col.type === 'likes') merged = merged.filter(p => p.liked);
    if (col.type === 'bookmarks') merged = merged.filter(p => p.bookmarked);
    if (col.type === 'home') merged = applyHomeFeed(merged, plat, col.feed);
    return merged;
  };

  // signature for a column's feed identity — changes trigger a fresh load
  const colSig = (col) => `${col.accountId || activeId}:${col.type}:${col.feed || ''}`;
  const isHomeCol = (col) => col.type === 'home';

  // raw static base feed for the server store (no injected, no overrides)
  const baseFeedFor = (col) => {
    const plat = colAccount(col).platform;
    return applyHomeFeed(timelineFor(plat, 'home').slice(), plat, col.feed);
  };
  // lazily stand up the server-side feed for a home column
  const ensureStore = (col) => {
    const sig = colSig(col);
    if (!FeedStore.has(sig)) {
      const plat = colAccount(col).platform;
      FeedStore.ensure(sig, plat, baseFeedFor(col), { feed: col.feed || 'foryou', injected: injected[plat] || [] });
    }
    return sig;
  };
  // derive the waiting-posts count from how far the view trails the server
  const countOf = (sig, view) => Math.max(0, FeedStore.frontier(sig) - (FeedStore.topSeq(view || []) ?? FeedStore.frontier(sig)));

  // resolve a column's content from cache and mark it ready (no skeleton).
  const hydrateView = (col) => {
    if (isHomeCol(col)) {
      const sig = ensureStore(col);
      const view = FeedStore.initialView(sig);
      setColView(v => ({ ...v, [col.id]: view }));
      setColNew(n => ({ ...n, [col.id]: 0 }));
      setColStatus(s => ({ ...s, [col.id]: view.length ? 'ready' : 'empty' }));
      return view.length;
    }
    const n = postsFor(col).length;
    setColView(v => { if (!(col.id in v)) return v; const c = { ...v }; delete c[col.id]; return c; });
    setColStatus(s => ({ ...s, [col.id]: n ? 'ready' : 'empty' }));
    return n;
  };

  // begin a load for a column. COLD (this feed never loaded) → blank skeleton,
  // then resolve. WARM (we've shown this feed before, so there's cached content)
  // → show it immediately and silently revalidate — re-entering never blanks.
  const startLoad = (col, opts) => {
    clearTimeout(timersRef.current[col.id]);
    const sig = colSig(col);
    const warm = !(opts && opts.cold === true) && seenSigRef.current.has(sig);
    if (warm) {
      setColReloadError(e => ({ ...e, [col.id]: false }));
      hydrateView(col);
      softReload(col);
      return;
    }
    setColStatus(s => ({ ...s, [col.id]: 'loading' }));
    setColReloadError(e => ({ ...e, [col.id]: false }));
    setColNew(n => ({ ...n, [col.id]: 0 }));
    const willFail = tRef.current.failNext;
    timersRef.current[col.id] = setTimeout(() => {
      if (willFail) { dbgTimeline(col, { kind: 'cold-load', fail: true }); setColStatus(s => ({ ...s, [col.id]: 'error' })); setTweak('failNext', false); return; }
      seenSigRef.current.add(sig);
      const n = hydrateView(col);
      dbgTimeline(col, { kind: 'cold-load', count: n });
    }, Math.max(250, tRef.current.loadMs));
  };

  // WARM revalidation: keep the existing content on screen, run the soft
  // indicator (thin bar + "checking for updates" pill), then merge fresh data.
  // On failure DON'T wipe — raise a dismissible inline error strip with retry.
  const softReload = (col) => {
    clearTimeout(timersRef.current[col.id]);
    const sig = colSig(col);
    setColRefreshing(r => ({ ...r, [col.id]: 'soft' }));
    const willFail = tRef.current.failNext;
    timersRef.current[col.id] = setTimeout(() => {
      setColRefreshing(r => ({ ...r, [col.id]: false }));
      if (willFail) { dbgTimeline(col, { kind: 'revalidate', fail: true }); setColReloadError(e => ({ ...e, [col.id]: true })); setTweak('failNext', false); return; }
      seenSigRef.current.add(sig);
      setColReloadError(e => ({ ...e, [col.id]: false }));
      dbgTimeline(col, { kind: 'revalidate', count: isHomeCol(col) && FeedStore.has(sig) ? FeedStore.fetchLatest(sig, tRef.current.pageSize).length : 0 });
      if (isHomeCol(col) && FeedStore.has(sig)) doMerge(col);
    }, Math.max(450, tRef.current.loadMs));
  };

  // fetch the newest page and MERGE it into the view. Overlap → seamless;
  // a hole bigger than one page → a gap marker is inserted.
  const doMerge = (col) => {
    const sig = colSig(col);
    if (!FeedStore.has(sig)) return;
    const page = FeedStore.fetchLatest(sig, Math.max(1, tRef.current.pageSize));
    setColView(v => {
      const cur = v[col.id] || FeedStore.initialView(sig);
      const res = FeedStore.applyLatest(cur, page);
      return { ...v, [col.id]: res.view };
    });
    setColNew(n => ({ ...n, [col.id]: 0 }));
  };

  // pull-to-refresh / "load new" — a WARM reload of a column you're looking at:
  // spins the header, then merges. Failure keeps content + shows the error strip.
  const refreshCol = (colId) => {
    const col = columns.find(c => c.id === colId);
    if (!col || colRefreshing[colId]) return;
    if (statusRef.current[colId] === 'loading') return;
    if (statusRef.current[colId] === 'error') { startLoad(col, { cold: true }); return; }
    setColRefreshing(r => ({ ...r, [colId]: 'manual' }));
    const willFail = tRef.current.failNext;
    setTimeout(() => {
      setColRefreshing(r => ({ ...r, [colId]: false }));
      if (willFail) { dbgTimeline(col, { kind: 'refresh', fail: true }); setColReloadError(e => ({ ...e, [colId]: true })); setTweak('failNext', false); return; }
      seenSigRef.current.add(colSig(col));
      setColReloadError(e => ({ ...e, [colId]: false }));
      if (isHomeCol(col)) {
        dbgTimeline(col, { kind: 'refresh', count: FeedStore.has(colSig(col)) ? FeedStore.fetchLatest(colSig(col), tRef.current.pageSize).length : 0 });
        doMerge(col);
        setColStatus(s => ({ ...s, [colId]: 'ready' }));
      } else {
        setColNew(n => ({ ...n, [colId]: 0 }));
        const cnt = postsFor(col).length;
        dbgTimeline(col, { kind: 'refresh', count: cnt });
        setColStatus(s => ({ ...s, [colId]: cnt ? 'ready' : 'empty' }));
      }
    }, Math.max(600, tRef.current.loadMs));
  };
  // HARD reload (⇧⌘R) — discard the loaded view + any gaps and rebuild the
  // freshest snapshot from the top with a skeleton. Unlike normal refresh it
  // never stacks onto / merges with what's on screen: clean slate, scroll top.
  const hardReloadCol = (colId) => {
    const col = columns.find(c => c.id === colId);
    if (!col || statusRef.current[colId] === 'loading') return;
    setColView(v => { if (!(col.id in v)) return v; const c = { ...v }; delete c[col.id]; return c; });
    seenSigRef.current.delete(colSig(col)); // force the cold skeleton path
    startLoad(col, { cold: true });
  };
  // EMPTY CACHE and reload — also throw away the in-memory feed cache for this
  // column (every post pulled in this session + unread count), then cold-load
  // from the source timeline. The deepest "start over from scratch".
  const emptyReloadCol = (colId) => {
    const col = columns.find(c => c.id === colId);
    if (!col || statusRef.current[colId] === 'loading') return;
    const sig = colSig(col);
    if (FeedStore.reset) FeedStore.reset(sig);
    setColNew(n => ({ ...n, [colId]: 0 }));
    setColView(v => { if (!(col.id in v)) return v; const c = { ...v }; delete c[col.id]; return c; });
    seenSigRef.current.delete(sig);
    startLoad(col, { cold: true });
  };
  // full-screen error retry → fresh COLD load (there was nothing to preserve)
  const retryCol = (colId) => { const col = columns.find(c => c.id === colId); if (col) startLoad(col, { cold: true }); };
  // inline error-strip retry → another WARM revalidation, content stays put
  const retryReload = (colId) => { const col = columns.find(c => c.id === colId); if (col && !colRefreshing[colId]) softReload(col); };
  const dismissReloadError = (colId) => setColReloadError(e => ({ ...e, [colId]: false }));

  // tap a gap → load DOWN from the post above it. Reaches the lower segment →
  // gap removed (merged). Otherwise the gap shrinks and stays in its new place.
  const fillGapCol = (colId, gapId) => {
    const col = columns.find(c => c.id === colId);
    if (!col || colGapLoadingRef.current[gapId]) return;
    const sig = colSig(col);
    if (!FeedStore.has(sig)) return;
    const gap = (viewRef.current[colId] || []).find(it => it && it._gap && it.id === gapId);
    if (!gap) return;
    colGapLoadingRef.current[gapId] = true;
    setColGapLoading(g => ({ ...g, [gapId]: true }));
    const willFail = tRef.current.failNext;
    setTimeout(() => {
      colGapLoadingRef.current[gapId] = false;
      if (willFail) {
        dbgTimeline(col, { kind: 'gap-fill', fail: true, maxId: gap.aboveSeq });
        setColGapLoading(g => { const c = { ...g }; delete c[gapId]; return c; });
        setTweak('failNext', false);
        setToast(colAccount(col).platform === 'weibo' ? '加载失败，请重试' : "Couldn't load posts");
        setTimeout(() => setToast(null), 1800);
        return;
      }
      const page = FeedStore.fetchBelow(sig, gap.aboveSeq, Math.max(1, tRef.current.pageSize));
      dbgTimeline(col, { kind: 'gap-fill', maxId: gap.aboveSeq, count: page.length });
      setColView(v => {
        const cur = v[colId] || [];
        const res = FeedStore.fillGap(cur, gapId, page);
        return { ...v, [colId]: res.view };
      });
      setColGapLoading(g => { const c = { ...g }; delete c[gapId]; return c; });
    }, Math.max(500, tRef.current.loadMs));
  };

  // scrolling to the very top auto-merges anything waiting on the server
  // (you're caught up), keeping the at-top experience seamless.
  const onColScroll = (colId, scrollTop) => {
    const ref = scrollRef.current;
    let s = ref[colId]; if (!s) { s = { last: scrollTop }; ref[colId] = s; }
    s.last = scrollTop;
    if (scrollTop <= 2 && !colRefreshing[colId]) {
      const col = columns.find(c => c.id === colId);
      if (col && isHomeCol(col)) {
        const sig = colSig(col);
        const cur = viewRef.current[colId];
        if (cur && FeedStore.has(sig) && FeedStore.frontier(sig) > (FeedStore.topSeq(cur) ?? 0)) doMerge(col);
      }
    }
  };

  // periodic tick: publish new posts to the server, then either merge them
  // (columns sitting at the top) or surface a waiting count + future gap.
  const publishTick = (opts) => {
    const force = !!(opts && opts.force);
    const amount = opts && opts.amount;
    const homeCols = columns.filter(c => isHomeCol(c) && statusRef.current[c.id] === 'ready' && FeedStore.has(colSig(c)));
    const seen = {};
    homeCols.forEach(col => {
      const sig = colSig(col);
      if (seen[sig]) return; seen[sig] = true;
      const n = amount != null ? amount : (1 + Math.floor(Math.random() * Math.max(1, tRef.current.newPerTick)));
      FeedStore.publish(sig, n);
      dbgTimeline(col, { kind: 'poll', sinceId: FeedStore.topSeq(viewRef.current[col.id] || []), count: n });
    });
    setColNew(prev => {
      const next = { ...prev };
      homeCols.forEach(col => { next[col.id] = countOf(colSig(col), viewRef.current[col.id]); });
      return next;
    });
    if (!force) homeCols.forEach(col => {
      const atTop = ((scrollRef.current[col.id] || {}).last || 0) <= 60;
      if (atTop) doMerge(col);
    });
  };

  // the user's own composed post becomes the newest server post + lands on
  // top of every matching home column's view (seamless, no gap).
  const publishUserPost = (np, plat) => {
    const homeCols = columns.filter(c => isHomeCol(c) && colAccount(c).platform === plat);
    const stamped = {};
    homeCols.forEach(col => {
      const sig = colSig(col);
      if (!(sig in stamped)) stamped[sig] = FeedStore.has(sig) ? FeedStore.publishPost(sig, np) : null;
      const sp = stamped[sig];
      if (!sp) return;
      setColView(v => {
        const cur = v[col.id]; if (!cur) return v;
        return { ...v, [col.id]: [sp].concat(cur.filter(it => it._gap || it._seq !== sp._seq)) };
      });
      setColNew(n => ({ ...n, [col.id]: 0 }));
    });
  };

  // kick off a load whenever a column appears or its feed identity changes
  useEffect(() => {
    columns.forEach(col => {
      const sig = colSig(col);
      if (sigRef.current[col.id] !== sig) { sigRef.current[col.id] = sig; startLoad(col); }
    });
    Object.keys(sigRef.current).forEach(id => { if (!columns.some(c => c.id === id)) { delete sigRef.current[id]; clearTimeout(timersRef.current[id]); } });
  }, [columns, activeId]); // eslint-disable-line

  // auto-refresh: periodically publish + merge new posts
  useEffect(() => {
    if (!tweaks.autoRefresh) return undefined;
    const ms = Math.max(3, tweaks.refreshSecs) * 1000;
    const id = setInterval(() => publishTick(), ms);
    return () => clearInterval(id);
  }, [tweaks.autoRefresh, tweaks.refreshSecs, columns]); // eslint-disable-line

  // status a column should render — the tweak override wins for easy debugging
  const effStatus = (col) => (tweaks.tlState === 'auto' ? (colStatus[col.id] || 'loading') : tweaks.tlState);
  // merged (override-applied) view for a home column, with gap markers intact
  const renderView = (col) => {
    const v = colView[col.id];
    if (!v) return null;
    return v.map(it => (it && it._gap) ? it : mergePost(it));
  };

  // ── Debug: synthetic, sanitized network log ──
  // Every data operation emits a believable API request (URL + payload). The
  // log itself strips cookies/tokens (see DebugBus.safeHeaders); nothing here
  // ever carries real credentials. No-ops entirely unless debug + netLog are on.
  const NET_BASE = (plat) => plat === 'weibo' ? 'https://api.weibo.com/2' : 'https://api.x.com/2';
  const TL_EP = { home: 'timelines/home', mentions: 'notifications/mentions', likes: 'users/me/likes', bookmarks: 'users/me/bookmarks', search: 'search/recent', lists: 'lists/statuses', profile: 'users/me/tweets' };
  const dbgOn = () => window.DebugBus && DebugBus.enabled() && DebugBus.cfg.netLog;
  const dbgTimeline = (col, opts) => {
    if (!dbgOn()) return;
    const o = opts || {};
    const acct = colAccount(col);
    const ep = TL_EP[col.type] || 'timelines/home';
    const q = ['screen_name=' + encodeURIComponent(acct.handle)];
    if (col.type === 'home') q.push('feed=' + (col.feed || 'foryou'));
    q.push('count=' + Math.max(1, tRef.current.pageSize));
    if (o.maxId != null) q.push('max_id=' + o.maxId);
    if (o.sinceId != null) q.push('since_id=' + o.sinceId);
    const ids = (viewRef.current[col.id] || []).filter(p => p && !p._gap).slice(0, 4).map(p => ({ id: p.id }));
    DebugBus.log({
      method: 'GET', url: NET_BASE(acct.platform) + '/' + ep + '.json?' + q.join('&'), platform: acct.platform,
      account: { name: acct.name, handle: acct.handle }, kind: o.kind || 'timeline',
      status: o.fail ? (Math.random() < 0.5 ? 503 : 500) : 200,
      ms: o.ms != null ? o.ms : Math.max(120, tRef.current.loadMs),
      resBody: o.fail ? { errors: [{ code: 130, message: 'Over capacity' }] } : { meta: { result_count: o.count != null ? o.count : ids.length }, data: ids },
    });
  };
  const dbgAction = (id, base, field, on) => {
    if (!dbgOn()) return;
    const plat = base ? base.author.platform : active.platform;
    const x = plat !== 'weibo';
    const root = NET_BASE(plat);
    let method = 'POST', url, reqBody = null;
    if (field === 'liked') {
      if (x) { method = on ? 'POST' : 'DELETE'; url = root + '/users/me/likes' + (on ? '' : '/' + id); reqBody = on ? { tweet_id: id } : null; }
      else { url = root + '/statuses/favorites/' + (on ? 'create' : 'destroy') + '.json'; reqBody = { id }; }
    } else if (field === 'reposted') {
      if (x) { method = on ? 'POST' : 'DELETE'; url = root + '/users/me/retweets' + (on ? '' : '/' + id); reqBody = on ? { tweet_id: id } : null; }
      else { url = root + '/statuses/repost.json'; reqBody = { id, status: '转发微博' }; }
    } else if (field === 'bookmarked') {
      if (x) { method = on ? 'POST' : 'DELETE'; url = root + '/users/me/bookmarks' + (on ? '' : '/' + id); reqBody = on ? { tweet_id: id } : null; }
      else { url = root + '/statuses/favorites/' + (on ? 'create' : 'destroy') + '.json'; reqBody = { id }; }
    } else return;
    DebugBus.log({ method, url, platform: plat, account: { name: active.name, handle: active.handle }, kind: field, status: 200, ms: Math.round(60 + Math.random() * 120), reqBody, resBody: { id, ok: true } });
  };
  const dbgCompose = (from, body, kind, status) => {
    if (!dbgOn()) return;
    const root = NET_BASE(from.platform);
    const url = from.platform === 'weibo' ? root + '/statuses/' + (kind === 'reply' ? 'comment' : 'update') + '.json' : root + '/tweets';
    DebugBus.log({ method: 'POST', url, platform: from.platform, account: { name: from.name, handle: from.handle }, kind: kind || 'post', status: status || 201, ms: Math.round(140 + Math.random() * 220), reqBody: body, resBody: { id: 'np' + Date.now(), created: true } });
  };


  const openCompose = () => { setComposeFrom(activeId); setComposeCtx(null); setComposeOpen(true); };
  const closeCompose = () => { setComposeOpen(false); setComposeCtx(null); };

  // add-account workflow
  const openAddAccount = (platform = null) => { setAddPlatform(platform); setAddOpen(true); setAcctMenu(false); };
  const onAccountAdded = (acct) => {
    if (!ACCOUNTS.some(a => a.id === acct.id)) ACCOUNTS.push(acct);
    setAdded(list => [...list, acct]);
    setUnread(u => ({ ...u, [acct.id]: 0 }));
    setActiveId(acct.id);
    setPrimaryType('home');
    setAddOpen(false);
    setToast(acct.platform === 'x' ? `Connected @${acct.handle}` : `已连接 ${acct.name}`);
    setTimeout(() => setToast(null), 2400);
  };

  // per-column navigation stacks (iOS-style push/pop within a column)
  const pushScreen = (colId, screen) => setColNav(m => ({ ...m, [colId]: [...(m[colId] || []), { ...screen, key: 's' + Date.now() + Math.round(Math.random() * 1e4) }] }));
  const popScreen = (colId) => setColNav(m => ({ ...m, [colId]: (m[colId] || []).slice(0, -1) }));
  const openOwnProfile = () => { const c = columns[0]; if (c) pushScreen(c.id, { kind: 'profile', person: active }); };

  // ── Comments-as-posts ─────────────────────────────────────────
  // Replies are synthesized deterministically from their parent (see
  // repliesFor), and their ids encode the path: "x1-r0-r2" = the 3rd reply to
  // the 1st reply to post x1. That lets us open ANY reply as its own focal
  // screen — resolve it, rebuild its ancestor chain (root post + every parent
  // comment), and hand both to the detail view. This is the X conversation
  // model: tap a reply, it becomes the big post, its parents stack above it,
  // its own replies list below.
  const isCommentId = (id) => /-r\d+/.test(String(id));
  // Give a synthesized comment the full stat shape a Post/DetailScreen expects
  // (reposts + a plausible view count), derived deterministically from its id.
  const enrichComment = (c) => {
    const likes = (c.stats && typeof c.stats.likes === 'number') ? c.stats.likes : 0;
    const reps = (c.stats && typeof c.stats.replies === 'number') ? c.stats.replies : 0;
    const seed = String(c.id).split('').reduce((s, ch) => s + ch.charCodeAt(0), 0);
    const reposts = (c.stats && typeof c.stats.reposts === 'number') ? c.stats.reposts : (seed % 9) + (reps > 0 ? 1 : 0);
    const views = (c.stats && c.stats.views) || fmt(Math.max(60, likes * 33 + seed * 7));
    return { ...c, reposted: !!c.reposted, bookmarked: !!c.bookmarked, stats: { likes, replies: reps, reposts, views } };
  };
  // Walk the id path down from the root post, regenerating each level, to
  // return [rootPost, ...parentComments, focalComment].
  const commentChain = (id) => {
    const sid = String(id);
    const rootId = sid.split('-r')[0];
    const root = findBase(rootId);
    if (!root) return null;
    const idxs = (sid.slice(rootId.length).match(/-r(\d+)/g) || []).map(s => parseInt(s.slice(2), 10));
    let node = root;
    const chain = [root];
    for (const ix of idxs) {
      const subs = repliesFor(node);
      if (!subs || !subs[ix]) return null;
      node = subs[ix];
      chain.push(node);
    }
    return chain;
  };
  const mergeNode = (n) => (isCommentId(n.id) ? mergePost(enrichComment(n)) : mergePost(n));

  const resolvePost = (id) => {
    const b = findBase(id);
    if (b) return mergePost(b);
    // a synthesized reply opened as a focal post
    if (isCommentId(id)) {
      const chain = commentChain(id);
      if (chain && chain.length) {
        const focal = mergeNode(chain[chain.length - 1]);
        focal._ancestors = chain.slice(0, -1).map(mergeNode);
        return focal;
      }
    }
    // a reply the user actually composed (lives in the replies store)
    if (String(id).indexOf('rp') === 0) {
      for (const pid in replies) {
        const r = (replies[pid] || []).find(x => x.id === id);
        if (r) {
          const focal = mergePost(enrichComment(r));
          const parent = resolvePost(pid);
          focal._ancestors = parent ? [...(parent._ancestors || []), parent] : [];
          return focal;
        }
      }
    }
    return null;
  };
  const repliesOf = (post) => (replies[post.id] || []).concat(repliesFor(post));
  const authorPosts = (person) => {
    const plat = person.platform;
    const all = (injected[plat] || []).concat(timelineFor(plat, 'home'));
    return all.filter(p => p.author && (p.author.handle === person.handle || p.author.name === person.name)).map(mergePost);
  };

  // reply / repost / quote entry points
  const openReply = (post) => { setComposeFrom(activeId); setComposeCtx({ mode: 'reply', post }); setComposeOpen(true); };
  const openQuote = (post) => { setComposeFrom(activeId); setComposeCtx({ mode: 'quote', post }); setComposeOpen(true); };
  const openRepost = (post) => { setComposeFrom(activeId); setComposeCtx({ mode: 'repost', post }); setComposeOpen(true); };
  const directRepost = (post) => { onAction(post.id, 'reposted'); setToast(post.author.platform === 'x' ? (post.reposted ? 'Repost removed' : 'Reposted') : '转发成功'); setTimeout(() => setToast(null), 1800); };
  const addReply = (postId, from, text) => setReplies(prev => ({
    ...prev,
    [postId]: [
      { id: 'rp' + Date.now(), author: { name: from.name, handle: from.handle, color: from.color, verified: from.verified, platform: from.platform }, time: from.platform === 'x' ? 'now' : '刚刚', text, stats: { likes: 0, replies: 0 }, liked: false },
      ...(prev[postId] || []),
    ],
  }));

  const onPost = (from, text, context, extras) => {
    const ctx = context || null;
    const ex = extras || {};
    // scheduling: don't publish now — add to the scheduled store
    if (ex.scheduledAt) {
      ScheduleStore.add({ id: 'sc' + Date.now(), text, when: new Date(ex.scheduledAt).toISOString(), platform: from.platform, fromName: from.name, fromHandle: from.handle, images: (ex.images || []).length, hasPoll: !!ex.poll });
      dbgCompose(from, { text, scheduled_at: new Date(ex.scheduledAt).toISOString(), media_ids: (ex.images || []).map((_, i) => 'media_' + i) }, 'schedule', 200);
      setActiveId(from.id);
      closeCompose();
      setToast(from.platform === 'x' ? 'Your post was scheduled' : '已添加到定时任务');
      setTimeout(() => setToast(null), 2400);
      return;
    }
    const media = (ex.images && ex.images.length) ? { type: 'images', items: ex.images } : undefined;
    if (ctx && ctx.mode === 'reply') {
      addReply(ctx.post.id, from, text);
      dbgCompose(from, { text, reply: { in_reply_to_tweet_id: ctx.post.id } }, 'reply', 201);
      closeCompose();
      setToast(from.platform === 'x' ? 'Reply sent' : '评论已发布');
      setTimeout(() => setToast(null), 2000);
      return;
    }
    const base = {
      id: 'np' + Date.now(),
      author: { name: from.name, handle: from.handle, color: from.color, verified: from.verified, platform: from.platform },
      time: from.platform === 'x' ? 'now' : '刚刚',
      stats: { replies: 0, reposts: 0, likes: 0, views: from.platform === 'x' ? '12' : '阅读 12' },
      liked: false, reposted: false, bookmarked: false,
    };
    if (ctx && (ctx.mode === 'quote' || ctx.mode === 'repost')) {
      const o = ctx.post;
      const np = {
        ...base,
        text: text || (from.platform === 'x' ? '' : '转发微博'),
        quote: { author: o.author, time: o.time, text: o.text, media: o.media },
        quoteSrcId: o.id,
      };
      setInjected(prev => ({ ...prev, [from.platform]: [np, ...prev[from.platform]] }));
      dbgCompose(from, { text: text || '', quote_tweet_id: o.id }, ctx.mode, 201);
      publishUserPost(np, from.platform);
      setActiveId(from.id);
      closeCompose();
      setToast(from.platform === 'x' ? 'Reposted' : '转发成功');
      setTimeout(() => setToast(null), 2000);
      return;
    }
    const np = { ...base, text, ...(media ? { media } : {}) };
    setInjected(prev => ({ ...prev, [from.platform]: [np, ...prev[from.platform]] }));
    dbgCompose(from, { text, ...(media ? { media_ids: media.items.map((_, i) => 'media_' + i) } : {}) }, 'post', 201);
    publishUserPost(np, from.platform);
    setActiveId(from.id);
    closeCompose();
    setToast(from.platform === 'x' ? 'Posted to X' : '已发布到微博');
    setTimeout(() => setToast(null), 2200);
  };

  const closeColumn = (id) => setColumns(cols => { const idx = cols.findIndex(c => c.id === id); return (idx <= 0) ? cols : cols.filter(c => c.id !== id); });
  const addColumn = (type) => setColumns(cols => [...cols, { id: 'c' + Date.now(), type, accountId: activeId }]);
  const setColType = (id, type) => setColumns(cols => cols.map(c => c.id === id ? { ...c, type } : c));
  const setColFeed = (id, feed) => setColumns(cols => cols.map(c => c.id === id ? { ...c, feed } : c));
  const setColAccount = (id, accountId) => setColumns(cols => cols.map(c => c.id === id ? { ...c, accountId } : c));
  const moveColumn = (id, dir) => setColumns(cols => {
    const idx = cols.findIndex(c => c.id === id);
    const j = idx + dir;
    if (idx <= 0 || j <= 0 || j >= cols.length) return cols; // never touch index 0
    const copy = [...cols]; const [it] = copy.splice(idx, 1); copy.splice(j, 0, it); return copy;
  });
  const reorderColumns = (from, insertIdx) => setColumns(cols => {
    if (from <= 0 || from >= cols.length) return cols; // never move the fixed column
    let to = Math.max(1, Math.min(insertIdx, cols.length));
    let target = to > from ? to - 1 : to;
    if (target < 1) target = 1;
    if (target === from) return cols;
    const copy = [...cols]; const [it] = copy.splice(from, 1); copy.splice(target, 0, it); return copy;
  });
  const setPrimaryType = (type) => setColumns(cols => { if (!cols.length) return [{ id: 'c1', type }]; const copy = [...cols]; copy[0] = { ...copy[0], type }; return copy; });

  const primaryType = columns[0] ? columns[0].type : 'home';
  const isX = active.platform === 'x';
  const RAIL_W = 72;
  const MORE_TYPES = ['bookmarks', 'likes', 'lists'];
  // Window resizes fluidly with the viewport; columns always split the canvas equally.
  // Floor = 320px/col (window can't shrink past it); cap keeps columns from over-stretching.
  const minWinW = RAIL_W + columns.length * COLUMN_MIN;
  const maxWinW = RAIL_W + columns.length * COLUMN_MAX;

  // notifications: opening Mentions for the active account marks it read
  const markRead = (id) => setUnread(u => (u[id] ? { ...u, [id]: 0 } : u));
  const viewMentions = () => { setPrimaryType('mentions'); markRead(activeId); };
  // accounts OTHER than the one being viewed that have unread — drives the switcher avatar badge
  const othersUnread = ACCOUNTS.reduce((s, a) => s + (a.id === activeId ? 0 : (unread[a.id] || 0)), 0);
  const otherUnreadAccts = ACCOUNTS.filter(a => a.id !== activeId && (unread[a.id] || 0) > 0)
    .sort((a, b) => (unread[b.id] || 0) - (unread[a.id] || 0));
  // new posts waiting on any home column → highlight dot on the Home rail icon
  const homeNew = columns.filter(c => c.type === 'home').reduce((s, c) => s + (colNew[c.id] || 0), 0);

  // ── Configurable navigation ──
  const navCfg = normalizeNav(nav);
  const navTo = (id) => {
    setMoreMenu(false);
    if (id === 'profile') { openOwnProfile(); return; }
    if (id === 'mentions') { viewMentions(); return; }
    setPrimaryType(id);
  };
  const navActive = (id) => (id === 'profile' ? false : primaryType === id);
  const navBadge = (id) => (id === 'mentions' ? unread[activeId] : undefined);
  const navDot = (id) => (id === 'home' ? homeNew > 0 : false);
  const menuActive = navCfg.menu.includes(primaryType);

  // Data sources for the inspector's Data tab — a JSON snapshot per open column.
  const debugSources = (window.DebugBus && DebugBus.enabled()) ? columns.map(col => {
    const acct = colAccount(col);
    const meta = COL_META[col.type] || COL_META.home;
    const snap = renderView(col) || postsFor(col);
    return {
      id: col.id, icon: meta.icon, platform: acct.platform,
      label: acct.platform === 'x' ? meta.label_x : meta.label_w,
      sub: acct.platform === 'x' ? '@' + acct.handle : acct.name,
      count: (snap || []).filter(p => p && !p._gap).length,
      get: () => ({
        column: { id: col.id, type: col.type, feed: col.feed || null, accountId: col.accountId || activeId },
        account: { id: acct.id, name: acct.name, handle: acct.handle, platform: acct.platform },
        posts: (renderView(col) || postsFor(col)).filter(p => p && !p._gap),
      }),
    };
  }) : [];

  return (
    <div data-theme={theme} style={{ position: 'fixed', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: theme === 'dark' ? 'radial-gradient(120% 120% at 20% 0%, #2a2730, #131216 60%)' : 'radial-gradient(120% 120% at 20% 0%, #e7ecf5, #cdd6e6 70%)' }}>
      <div className={'perch-window' + (prefs.reduceMotion ? ' perch-reduce-motion' : '')} style={{ width: `clamp(${minWinW}px, 95vw, ${maxWinW}px)`, height: 'min(872px, 93vh)', borderRadius: 13, overflow: 'hidden', display: 'flex', background: 'var(--bg-base)',
        boxShadow: '0 0 0 1px rgba(0,0,0,.28), 0 28px 70px rgba(0,0,0,.45)', position: 'relative', fontFamily: 'var(--font-sans)', ...accentVars(prefs.accent) }}>

        {prefs.reduceMotion && <style>{'.perch-reduce-motion *{transition:none!important;animation:none!important;}'}</style>}

        {/* ── Icon rail ── */}
        <nav style={{ width: RAIL_W, flex: 'none', borderRight: '1px solid var(--border-default)', background: 'var(--bg-layer-1)', display: 'flex', flexDirection: 'column', alignItems: 'center', position: 'relative', zIndex: 2 }}>
          <div style={{ height: 16 }} />
          <div style={{ display: 'flex', justifyContent: 'center', width: '100%' }}><TrafficLights /></div>
          <div style={{ height: 16 }} />
          {/* active account → switcher popover */}
          <div style={{ position: 'relative', display: 'flex', justifyContent: 'center', width: '100%', padding: '4px 0 6px' }}>
            <button onClick={() => { setAcctMenu(m => !m); setMoreMenu(false); }} title={active.name + (othersUnread ? (isX ? ` · ${othersUnread} unread on your other account${otherUnreadAccts.length > 1 ? 's' : ''}` : ` · 其他账号 ${othersUnread} 条未读`) : (isX ? ' · click to switch' : ' · 点击切换账号'))}
              style={{ position: 'relative', border: 'none', background: 'none', padding: 0, cursor: 'pointer', display: 'inline-flex' }}>
              <span style={{ position: 'relative', display: 'inline-flex', borderRadius: '50%', padding: 2, background: 'var(--accent)' }}>
                <PAvatar person={active} size={42} />
              </span>
              <span style={{ position: 'absolute', right: -2, bottom: -2, width: 16, height: 16, borderRadius: '50%', background: 'var(--bg-layer-1)', boxShadow: '0 0 0 1px var(--border-default)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--fg-subdued)' }}>
                <span style={{ display: 'inline-flex', width: 13, height: 13 }}><Glyph name="chevron-down" size={13} /></span>
              </span>
              {/* Other-account unread: same small accent dot as the Home rail icon — "another account
                  has something new", quiet and consistent with the rest of the rail. */}
              {otherUnreadAccts.length > 0 && (
                <span title={isX ? `${othersUnread} unread on your other account${otherUnreadAccts.length > 1 ? 's' : ''}` : `其他账号 ${othersUnread} 条未读`}
                  style={{ position: 'absolute', top: 2, right: 2, width: 9, height: 9, borderRadius: '50%', background: 'var(--accent)', boxShadow: '0 0 0 2px var(--bg-layer-1)' }} />
              )}
            </button>
          </div>
          <div style={{ width: 34, height: 1, background: 'var(--border-default)', margin: '6px 0' }} />
          {/* nav — driven by the configurable rail layout */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'center' }}>
            {navCfg.bar.map(id => {
              const m = NAV_ITEMS[id];
              return <RailIcon key={id} name={m.glyph} title={isX ? m.label_x : m.label_w} active={navActive(id)} onClick={() => navTo(id)} badge={navBadge(id)} dot={navDot(id)} />;
            })}
            <div style={{ position: 'relative' }}>
              <RailIcon name="more" title={isX ? 'More' : '更多'} active={menuActive || moreMenu} onClick={() => { setMoreMenu(m => !m); setAcctMenu(false); }} />
              {moreMenu && (
                <React.Fragment>
                  <div onClick={() => setMoreMenu(false)} style={{ position: 'fixed', inset: 0, zIndex: 30 }} />
                  <div style={{ position: 'absolute', top: -6, left: 50, width: 200, background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', borderRadius: 12, boxShadow: 'var(--shadow-elevated)', padding: 6, zIndex: 31 }}>
                    {navCfg.menu.map(id => {
                      const m = NAV_ITEMS[id];
                      const on = navActive(id);
                      return (
                        <button key={id} onClick={() => navTo(id)} style={{ display: 'flex', alignItems: 'center', gap: 11, width: '100%', padding: '8px 10px', borderRadius: 9, border: 'none', background: on ? 'var(--gray-100)' : 'transparent', cursor: 'pointer', textAlign: 'left', color: 'var(--fg-body)', fontSize: 14, fontWeight: 600 }}
                          onMouseEnter={e => { if (!on) e.currentTarget.style.background = 'var(--gray-75)'; }} onMouseLeave={e => { if (!on) e.currentTarget.style.background = 'transparent'; }}>
                          <span style={{ display: 'inline-flex', width: 19, height: 19, color: 'var(--fg-subdued)' }}><Glyph name={m.glyph} size={19} /></span>
                          {isX ? m.label_x : m.label_w}
                          {on && <span style={{ marginLeft: 'auto', display: 'inline-flex', width: 16, height: 16, color: 'var(--accent)' }}><Glyph name="checkmark" size={16} /></span>}
                        </button>
                      );
                    })}
                    {navCfg.menu.length > 0 && <div style={{ height: 1, background: 'var(--border-default)', margin: '6px 8px' }} />}
                    <button onClick={() => { setMoreMenu(false); setNavConfigOpen(true); setAcctMenu(false); }} style={{ display: 'flex', alignItems: 'center', gap: 11, width: '100%', padding: '8px 10px', borderRadius: 9, border: 'none', background: 'transparent', cursor: 'pointer', textAlign: 'left', color: 'var(--fg-body)', fontSize: 14, fontWeight: 600 }}
                      onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-75)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
                      <span style={{ display: 'inline-flex', width: 19, height: 19, color: 'var(--fg-subdued)' }}><Glyph name="gear" size={19} /></span>
                      {isX ? 'Configure…' : '自定义…'}
                    </button>
                  </div>
                </React.Fragment>
              )}
            </div>
          </div>
          <div style={{ flex: 1 }} />
          {/* bottom */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, alignItems: 'center', paddingBottom: 14 }}>
            <button onClick={openCompose} title={isX ? 'New post (c)' : '发新微博 (c)'}
              style={{ width: 48, height: 48, borderRadius: '50%', border: 'none', background: 'var(--accent-bg)', color: '#fff', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 2px 10px color-mix(in srgb, var(--accent-bg) 45%, transparent)' }}>
              <span style={{ display: 'inline-flex', width: 22, height: 22 }}><Glyph name="pencil" size={22} /></span>
            </button>
            <div style={{ position: 'relative' }}>
              <RailIcon name="columns" title={isX ? 'Columns' : '分栏设置'} active={colMenu} onClick={() => { setColMenu(m => !m); setAcctMenu(false); setMoreMenu(false); }} />
            </div>
            <RailIcon name="settings" title={isX ? 'Settings' : '设置'} active={settingsOpen} onClick={() => { setSettingsOpen(true); setAcctMenu(false); setMoreMenu(false); }} />
            {prefs.debug && (
              <RailIcon name="code" title={isX ? 'Inspector' : '检查器'} active={!!(dbg.modal && dbg.modal.kind === 'inspector')} dot={dbg.reqs.length > 0}
                onClick={() => { DebugBus.openInspector('network'); setAcctMenu(false); setMoreMenu(false); }} />
            )}
          </div>

          {/* account popover */}
          {acctMenu && (
            <React.Fragment>
              <div onClick={() => setAcctMenu(false)} style={{ position: 'fixed', inset: 0, zIndex: 30 }} />
              <div style={{ position: 'absolute', top: 70, left: RAIL_W - 6, width: 268, background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', borderRadius: 14, boxShadow: 'var(--shadow-elevated)', padding: 6, zIndex: 31 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 10px 4px' }}>
                  <span style={{ fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.06em', color: 'var(--fg-subdued)' }}>{isX ? 'Accounts' : '账号'}</span>
                  {ACCOUNTS.reduce((s, a) => s + (unread[a.id] || 0), 0) > 0 && (
                    <span style={{ marginLeft: 'auto', display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 11.5, fontWeight: 600, color: 'var(--fg-subdued)' }}>
                      <NotifBadge count={ACCOUNTS.reduce((s, a) => s + (unread[a.id] || 0), 0)} ring="var(--bg-elevated)" mini />
                      {isX ? 'unread' : '条未读'}
                    </span>
                  )}
                </div>
                {ACCOUNTS.map(a => (
                  <button key={a.id} onClick={() => { setActiveId(a.id); setAcctMenu(false); }} style={{ display: 'flex', alignItems: 'center', gap: 11, width: '100%', padding: '7px 10px', borderRadius: 9, border: 'none', background: a.id === activeId ? 'var(--gray-100)' : 'transparent', cursor: 'pointer', textAlign: 'left' }}
                    onMouseEnter={e => { if (a.id !== activeId) e.currentTarget.style.background = 'var(--gray-75)'; }} onMouseLeave={e => { if (a.id !== activeId) e.currentTarget.style.background = 'transparent'; }}>
                    <span style={{ position: 'relative', display: 'inline-flex' }}>
                      <PAvatar person={a} size={32} />
                      <span style={{ position: 'absolute', right: -3, bottom: -3 }}><PlatformBadge platform={a.platform} size={15} /></span>
                      {unread[a.id] > 0 && <span style={{ position: 'absolute', left: -6, top: -5 }}><NotifBadge count={unread[a.id]} ring="var(--bg-elevated)" mini /></span>}
                    </span>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 14, fontWeight: 700, color: 'var(--fg-heading)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{a.name}</div>
                      <div style={{ fontSize: 12, color: 'var(--fg-subdued)' }}>{unread[a.id] > 0 ? (isX ? `${unread[a.id]} new mention${unread[a.id] > 1 ? 's' : ''}` : `${unread[a.id]} 条新提及`) : (a.platform === 'x' ? '@' + a.handle + ' · X' : '微博')}</div>
                    </div>
                    {a.id === activeId && <span style={{ display: 'inline-flex', width: 17, height: 17, color: 'var(--accent)' }}><Glyph name="checkmark" size={17} /></span>}
                  </button>
                ))}
                <button onClick={() => openAddAccount()} title="Add account" style={{ display: 'flex', alignItems: 'center', gap: 11, width: '100%', padding: '7px 10px', borderRadius: 9, border: 'none', background: 'transparent', cursor: 'pointer', textAlign: 'left', color: 'var(--fg-subdued)' }}
                  onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-75)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
                  <span style={{ width: 32, height: 32, borderRadius: '50%', border: '1.5px dashed var(--gray-400)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}><span style={{ display: 'inline-flex', width: 15, height: 15 }}><Glyph name="add" size={15} /></span></span>
                  <span style={{ fontSize: 14, fontWeight: 600 }}>{isX ? 'Add account' : '添加账号'}</span>
                </button>
                <div style={{ height: 1, background: 'var(--border-default)', margin: '6px 8px' }} />
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '4px 10px 6px' }}>
                  <span style={{ fontSize: 13, fontWeight: 600, color: 'var(--fg-subdued)' }}>{isX ? 'Appearance' : '外观'}</span>
                  <div style={{ display: 'flex', background: 'var(--gray-100)', borderRadius: 9999, padding: 2, gap: 2 }}>
                    {[['light', isX ? 'Light' : '浅色'], ['dark', isX ? 'Dark' : '深色']].map(([val, lbl]) => (
                      <button key={val} onClick={() => setThemeMode(val)} style={{ height: 24, padding: '0 11px', borderRadius: 9999, border: 'none', cursor: 'pointer', fontSize: 12.5, fontWeight: 600, fontFamily: 'var(--font-sans)', background: themeMode === val ? 'var(--bg-elevated)' : 'transparent', color: themeMode === val ? 'var(--fg-heading)' : 'var(--fg-subdued)', boxShadow: themeMode === val ? 'var(--shadow-emphasized)' : 'none' }}>{lbl}</button>
                    ))}
                  </div>
                </div>
              </div>
            </React.Fragment>
          )}

          {/* more-lists popover (anchored to the · · · icon above) */}
        </nav>

        {/* ── Columns canvas ── */}
        <div className="col-scroll" style={{ flex: 1, minWidth: 0, display: 'flex', overflow: 'hidden' }}>
          {columns.map((col, i) => (
            <Column key={col.id} col={col} account={colAccount(col, i)} posts={postsFor(col, i)} view={renderView(col)} isLast={i === columns.length - 1} isFirst={i === 0}
              onAction={onAction} onReply={openReply} onQuote={openQuote} onRepost={openRepost} onDirectRepost={directRepost}
              onType={setColType} onAccount={setColAccount} onFeed={setColFeed} unread={unread}
              status={effStatus(col)} refreshing={!!colRefreshing[col.id]} newCount={colNew[col.id] || 0} newAuthors={isHomeCol(col) && FeedStore.has(colSig(col)) ? FeedStore.waitingAuthors(colSig(col), colView[col.id], 4) : null} onRefresh={refreshCol} onRetry={retryCol} onScroll={onColScroll}
              onHardReload={hardReloadCol} onEmptyReload={emptyReloadCol}
              softReloading={colRefreshing[col.id] === 'soft'} reloadError={!!colReloadError[col.id]} onRetryReload={retryReload} onDismissReloadError={dismissReloadError}
              gapLoading={colGapLoading} onLoadGap={fillGapCol}
              folders={folders} bmFolder={bmFolder} onAddFolder={addFolder} onUpdateFolder={updateFolder} onDeleteFolder={deleteFolder} onSetFolder={setPostFolder} bmTweaks={{ bmShape: tweaks.bmShape, bmCounts: tweaks.bmCounts }}
              subStack={colNav[col.id] || []} onPushScreen={(s) => pushScreen(col.id, s)} onPopScreen={() => popScreen(col.id)}
              resolvePost={resolvePost} repliesOf={repliesOf} authorPosts={authorPosts} activeAccount={active} onOpenMedia={openMedia} />
          ))}
        </div>

        {composeOpen && <Compose accounts={ACCOUNTS} fromId={composeFrom} context={composeCtx} onChangeFrom={setComposeFrom} onClose={closeCompose} onPost={onPost} />}

        {settingsOpen && <Settings isX={isX} accounts={ACCOUNTS} active={active} themeMode={themeMode} onThemeMode={setThemeMode} prefs={prefs} setPref={setPref} onAddAccount={openAddAccount} onClose={() => setSettingsOpen(false)} />}

        {prefs.debug && <DebugLayer bus={DebugBus} sources={debugSources} isX={isX} />}

        {navConfigOpen && <NavConfigModal isX={isX} nav={navCfg} onChange={(n) => setNav(normalizeNav(n))} onClose={() => setNavConfigOpen(false)} />}

        {/* ── Horizontal column manager tray ── */}
        {colMenu && (
          <React.Fragment>
            <div onClick={() => setColMenu(false)} style={{ position: 'absolute', inset: 0, background: 'color-mix(in srgb, var(--gray-1000) 28%, transparent)', zIndex: 60 }} />
            <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 61, background: 'var(--bg-elevated)', borderTop: '1px solid var(--border-default)', boxShadow: '0 -18px 50px rgba(0,0,0,.28)', animation: 'trayUp .22s var(--ease-default)' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '14px 18px 10px' }}>
                <span style={{ display: 'inline-flex', width: 20, height: 20, color: 'var(--fg-heading)' }}><Glyph name="columns" size={20} /></span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 15.5, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.01em' }}>{isX ? 'Arrange columns' : '排列分栏'}</div>
                  <div style={{ fontSize: 12, color: 'var(--fg-subdued)' }}>{isX ? 'Drag to reorder · swap type & account · add or remove' : '拖动排序 · 切换类型与账号 · 添加或移除'}</div>
                </div>
                <button onClick={() => setColMenu(false)} style={{ height: 32, padding: '0 16px', borderRadius: 9, border: 'none', cursor: 'pointer', background: 'var(--accent-bg)', color: '#fff', fontSize: 13.5, fontWeight: 700, fontFamily: 'var(--font-sans)' }}>{isX ? 'Done' : '完成'}</button>
              </div>
              <div className="col-scroll" style={{ overflowX: 'auto', padding: '4px 18px 18px' }}>
                <ColumnEditor columns={columns} isX={isX} active={active}
                  onType={setColType} onAccount={setColAccount} onPrimaryType={setPrimaryType} onReorder={reorderColumns} onRemove={closeColumn} onAdd={addColumn} />
              </div>
            </div>
          </React.Fragment>
        )}

        {toast && (
          <div style={{ position: 'absolute', bottom: 24, left: '50%', transform: 'translateX(-50%)', zIndex: 80, display: 'flex', alignItems: 'center', gap: 9, height: 42, padding: '0 18px', borderRadius: 9999, background: 'var(--gray-900)', color: 'var(--gray-25)', boxShadow: 'var(--shadow-elevated)', fontFamily: 'var(--font-sans)', fontSize: 14, fontWeight: 600 }}>
            <span style={{ display: 'inline-flex', width: 18, height: 18, color: 'var(--green-700)' }}><Glyph name="checkmark-circle" size={18} /></span>
            {toast}
          </div>
        )}
      </div>

      {/* Add-account opens as its own floating macOS window, over the desktop */}
      {addOpen && <AddAccount platform={addPlatform} isX={isX} onClose={() => setAddOpen(false)} onAdded={onAccountAdded} />}

      {/* Shared media viewer — its own floating window, over everything */}
      {media && <MediaViewer slides={media.slides} index={media.index} author={media.author} onClose={() => setMedia(null)} />}

      {/* Debug panel — toggled from the toolbar; convenient timeline-state testing */}
      <TweaksPanel title="Tweaks">
        <TweakSection label="Timeline state" />
        <TweakSelect label="Force state" value={tweaks.tlState}
          options={[{ value: 'auto', label: 'Auto (live)' }, { value: 'loading', label: 'Loading' }, { value: 'error', label: 'Error' }, { value: 'empty', label: 'Empty' }]}
          onChange={(v) => setTweak('tlState', v)} />
        <TweakToggle label="Fail next load / refresh" value={tweaks.failNext} onChange={(v) => setTweak('failNext', v)} />
        <TweakSlider label="Load delay" value={tweaks.loadMs} min={200} max={3000} step={100} unit="ms" onChange={(v) => setTweak('loadMs', v)} />
        <TweakButton label="Cold reload (skeleton)" onClick={() => columns.forEach(c => startLoad(c, { cold: true }))} />
        <TweakButton label="Warm reload (keep content)" onClick={() => columns.forEach(c => softReload(c))} secondary />

        <TweakSection label="Auto-refresh & gaps" />
        <TweakToggle label="Auto-refresh on" value={tweaks.autoRefresh} onChange={(v) => setTweak('autoRefresh', v)} />
        <TweakSlider label="Interval" value={tweaks.refreshSecs} min={3} max={60} step={1} unit="s" onChange={(v) => setTweak('refreshSecs', v)} />
        <TweakSlider label="New posts / tick" value={tweaks.newPerTick} min={1} max={40} step={1} onChange={(v) => setTweak('newPerTick', v)} />
        <TweakSlider label="Fetch page size" value={tweaks.pageSize} min={2} max={30} step={1} onChange={(v) => setTweak('pageSize', v)} />
        <TweakButton label="Publish a burst (force a gap)" onClick={() => publishTick({ force: true, amount: Math.max(tweaks.pageSize + 3, tweaks.newPerTick) })} />
        <TweakButton label="Publish new posts to server" onClick={() => publishTick({ force: true })} secondary />

        <TweakSection label="Bookmarks" />
        <TweakRadio label="Folder icon" value={tweaks.bmShape} options={[{ value: 'square', label: 'Square' }, { value: 'circle', label: 'Circle' }]} onChange={(v) => setTweak('bmShape', v)} />
        <TweakToggle label="Show folder counts" value={tweaks.bmCounts !== false} onChange={(v) => setTweak('bmCounts', v)} />
      </TweaksPanel>
    </div>
  );
}

Object.assign(window, { PlatformBadge, NotifBadge });

ReactDOM.createRoot(document.getElementById('root')).render(<App />);

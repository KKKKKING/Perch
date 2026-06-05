/* Configurable navigation: item definitions + the "Configure navigation" sheet.
   The rail's primary destinations and its ⋯ overflow menu are both driven by a
   single { bar, menu, postInBar } config. Users open this from ⋯ › Configure
   and drag rows between the Sidebar list and the Overflow-menu list. */

const NAV_ITEMS = {
  home:      { glyph: 'home',     label_x: 'Home',          label_w: '主页' },
  mentions:  { glyph: 'bell',     label_x: 'Notifications', label_w: '消息' },
  search:    { glyph: 'search',   label_x: 'Search',        label_w: '搜索' },
  profile:   { glyph: 'user',     label_x: 'Profile',       label_w: '我的' },
  bookmarks: { glyph: 'bookmark-outline', label_x: 'Bookmarks',     label_w: '收藏' },
  likes:     { glyph: 'heart-outline',    label_x: 'Likes',         label_w: '赞过' },
  lists:     { glyph: 'list',     label_x: 'Lists',         label_w: '列表' },
};

const DEFAULT_NAV = {
  bar: ['home', 'mentions', 'search', 'profile', 'bookmarks'],
  menu: ['likes', 'lists'],
};

// Heal a persisted config: drop unknown ids, append any newly-introduced
// destinations to the overflow menu so nothing silently disappears.
function normalizeNav(n) {
  const cfg = { bar: [], menu: [] };
  const seen = {};
  const take = (arr, dst) => (arr || []).forEach(id => { if (NAV_ITEMS[id] && !seen[id]) { seen[id] = 1; cfg[dst].push(id); } });
  take(n && n.bar, 'bar');
  take(n && n.menu, 'menu');
  Object.keys(NAV_ITEMS).forEach(id => { if (!seen[id]) cfg.menu.push(id); });
  return cfg;
}

/* A single draggable nav row inside one of the two lists. */
function NavRow({ id, list, isX, dim, onDragStart, onDragEnd }) {
  const m = NAV_ITEMS[id];
  const [h, setH] = React.useState(false);
  return (
    <div data-row draggable
      onDragStart={e => { e.dataTransfer.effectAllowed = 'move'; onDragStart(); }}
      onDragEnd={onDragEnd}
      onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '0 10px 0 12px', height: 46,
        background: dim ? 'var(--gray-75)' : h ? 'var(--gray-75)' : 'var(--bg-base)',
        opacity: dim ? 0.45 : 1, cursor: 'grab', userSelect: 'none', transition: 'background .1s' }}>
      <span style={{ display: 'inline-flex', width: 21, height: 21, color: 'var(--accent)', flex: 'none' }}><Glyph name={m.glyph} size={21} /></span>
      <span style={{ flex: 1, minWidth: 0, fontSize: 14.5, fontWeight: 600, color: 'var(--fg-heading)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{isX ? m.label_x : m.label_w}</span>
      <span title={isX ? 'Drag to reorder' : '拖动排序'} style={{ display: 'inline-flex', width: 20, height: 20, color: h ? 'var(--fg-subdued)' : 'var(--fg-disabled)', flex: 'none' }}><Glyph name="grip" size={20} /></span>
    </div>
  );
}

/* The Configure-navigation modal. Updates the parent config live as you drag,
   so the rail behind the sheet reflects every change immediately. */
function NavConfigModal({ isX, nav, onChange, onClose }) {
  const cfg = normalizeNav(nav);
  const [drag, setDrag] = React.useState(null);  // { id, from }
  const [over, setOver] = React.useState(null);   // { list, index }
  const reset = () => { setDrag(null); setOver(null); };

  const doDrop = () => {
    if (!drag || !over) { reset(); return; }
    const next = { bar: [...cfg.bar], menu: [...cfg.menu] };
    const src = next[drag.from];
    const srcIdx = src.indexOf(drag.id);
    if (srcIdx === -1) { reset(); return; }
    src.splice(srcIdx, 1);
    let idx = over.index;
    if (drag.from === over.list && srcIdx < idx) idx -= 1;
    idx = Math.max(0, Math.min(idx, next[over.list].length));
    next[over.list].splice(idx, 0, drag.id);
    onChange(next);
    reset();
  };

  // index computed from the rendered rows so empty lists & end-drops both work
  const listOver = (e, list) => {
    if (!drag) return;
    e.preventDefault();
    const rows = Array.from(e.currentTarget.querySelectorAll('[data-row]'));
    let idx = rows.length;
    for (let k = 0; k < rows.length; k++) {
      const r = rows[k].getBoundingClientRect();
      if (e.clientY < r.top + r.height / 2) { idx = k; break; }
    }
    setOver({ list, index: idx });
  };

  const Indicator = () => <div style={{ height: 2, margin: '0 10px', borderRadius: 2, background: 'var(--accent)', boxShadow: '0 0 0 2px color-mix(in srgb, var(--accent) 22%, transparent)' }} />;

  const renderList = (list, emptyText) => {
    const ids = cfg[list];
    return (
      <div onDragOver={e => listOver(e, list)} onDrop={e => { e.preventDefault(); doDrop(); }}
        style={{ borderRadius: 12, border: '1px solid var(--border-default)', background: 'var(--bg-base)', overflow: 'hidden', minHeight: 50 }}>
        {ids.length === 0 && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: 50, fontSize: 13, fontWeight: 600, color: 'var(--fg-disabled)' }}>{emptyText}</div>
        )}
        {ids.map((id, i) => (
          <React.Fragment key={id}>
            {drag && over && over.list === list && over.index === i && <Indicator />}
            {i > 0 && !(drag && over && over.list === list && over.index === i) && <div style={{ height: 1, background: 'var(--border-default)', margin: '0 12px' }} />}
            <NavRow id={id} list={list} isX={isX} dim={drag && drag.id === id}
              onDragStart={() => setTimeout(() => setDrag({ id, from: list }), 0)} onDragEnd={reset} />
          </React.Fragment>
        ))}
        {drag && over && over.list === list && over.index === ids.length && ids.length > 0 && <Indicator />}
      </div>
    );
  };

  const SectionLabel = ({ children }) => (
    <div style={{ fontSize: 11.5, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.06em', color: 'var(--fg-subdued)', padding: '0 2px 8px' }}>{children}</div>
  );

  return (
    <React.Fragment>
      <div onClick={onClose} style={{ position: 'absolute', inset: 0, background: 'color-mix(in srgb, var(--gray-1000) 34%, transparent)', zIndex: 70 }} />
      <div style={{ position: 'absolute', inset: 0, zIndex: 71, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 28, pointerEvents: 'none' }}>
        <div role="dialog" aria-modal="true" style={{ width: 460, maxWidth: '100%', maxHeight: '100%', pointerEvents: 'auto',
          background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', borderRadius: 16, boxShadow: 'var(--shadow-elevated)', display: 'flex', flexDirection: 'column', overflow: 'hidden', animation: 'winPop .2s var(--ease-default)' }}>

        {/* header */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '15px 16px', borderBottom: '1px solid var(--border-default)', flex: 'none' }}>
          <span style={{ display: 'inline-flex', width: 20, height: 20, color: 'var(--fg-heading)' }}><Glyph name="gear" size={20} /></span>
          <div style={{ flex: 1, minWidth: 0, fontSize: 16, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.01em' }}>{isX ? 'Configure navigation' : '自定义导航'}</div>
          <button onClick={onClose} style={{ height: 32, padding: '0 16px', borderRadius: 9, border: 'none', cursor: 'pointer', background: 'var(--accent-bg)', color: '#fff', fontSize: 13.5, fontWeight: 700, fontFamily: 'var(--font-sans)' }}>{isX ? 'Done' : '完成'}</button>
        </div>

        {/* body */}
        <div className="col-scroll" style={{ overflowY: 'auto', padding: 16, display: 'flex', flexDirection: 'column', gap: 18 }}>
          {/* sidebar list */}
          <div>
            <SectionLabel>{isX ? 'Sidebar' : '侧边栏'}</SectionLabel>
            {renderList('bar', isX ? 'Drag items here' : '拖动到此处')}
            <div style={{ fontSize: 12.5, lineHeight: 1.45, color: 'var(--fg-subdued)', padding: '8px 2px 0' }}>{isX ? 'Shown as icons directly in the rail, top to bottom.' : '以图标形式从上到下显示在侧栏中。'}</div>
          </div>

          {/* overflow menu list */}
          <div>
            <SectionLabel>{isX ? 'Overflow menu  ·  ⋯' : '更多菜单  ·  ⋯'}</SectionLabel>
            {renderList('menu', isX ? 'Drag items here' : '拖动到此处')}
            <div style={{ fontSize: 12.5, lineHeight: 1.45, color: 'var(--fg-subdued)', padding: '8px 2px 0' }}>{isX ? 'Tucked inside the ⋯ button at the bottom of the icons.' : '收纳在图标底部的 ⋯ 按钮中。'}</div>
          </div>
        </div>
      </div>
      </div>
    </React.Fragment>
  );
}

Object.assign(window, { NAV_ITEMS, DEFAULT_NAV, normalizeNav, NavConfigModal });

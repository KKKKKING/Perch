/* Bookmark folders for the Bookmarks column. Adds an organizable folder
   index on top of the flat bookmark list: browse "All bookmarks" + custom
   folders, filter into a folder, create / rename / recolor / delete folders,
   and a Select mode to move bookmarks between folders. Spectrum 2 throughout.
   Loaded as Babel JSX after post.jsx (uses ThreadedList) and before column.jsx. */

// Curated folder colors — distinct Spectrum hues at a saturated stop.
const FOLDER_PALETTE = [
  'var(--blue-900)', 'var(--magenta-800)', 'var(--green-800)', 'var(--orange-800)',
  'var(--purple-800)', 'var(--seafoam-800)', 'var(--red-800)', 'var(--cyan-800)',
  'var(--indigo-700)', 'var(--celery-800)', 'var(--turquoise-800)', 'var(--pink-700)',
];

// Seed folders per platform (folders are shared across same-platform accounts).
const SEED_FOLDERS = {
  x: [
    { id: 'fx_read',   name: 'Read later',    color: 'var(--blue-900)' },
    { id: 'fx_design', name: 'Design',        color: 'var(--magenta-800)' },
    { id: 'fx_ideas',  name: 'Product ideas', color: 'var(--green-800)' },
    { id: 'fx_code',   name: 'Code',          color: 'var(--orange-800)' },
    { id: 'fx_inspo',  name: 'Inspiration',   color: 'var(--purple-800)' },
  ],
  weibo: [
    { id: 'fw_read',    name: '稍后读', color: 'var(--blue-900)' },
    { id: 'fw_sheying', name: '摄影',   color: 'var(--indigo-700)' },
    { id: 'fw_linggan', name: '灵感',   color: 'var(--purple-800)' },
    { id: 'fw_keji',    name: '科技',   color: 'var(--cyan-800)' },
    { id: 'fw_meishi',  name: '美食',   color: 'var(--red-800)' },
  ],
};

// Which bookmarked post lands in which folder (also forces the post bookmarked).
const SEED_ASSIGN = {
  x1: 'fx_design', xc1: 'fx_design', x4: 'fx_design',
  x2: 'fx_ideas',  x8: 'fx_ideas',   xt1: 'fx_ideas',
  x3: 'fx_read',   x9: 'fx_read',
  x6: 'fx_inspo',  x7: 'fx_inspo',
  x5: 'fx_code',   x0: 'fx_code',
  w1: 'fw_sheying', w7: 'fw_sheying', wt1: 'fw_sheying',
  w3: 'fw_meishi',  wc1: 'fw_meishi',
  w2: 'fw_keji',    w6: 'fw_keji',
  w4: 'fw_linggan',
  w5: 'fw_read',    w0: 'fw_read',
};

// Initial overrides so every assigned post reads as bookmarked.
function bookmarkSeedOverrides() {
  const o = {};
  Object.keys(SEED_ASSIGN).forEach(id => { o[id] = { bookmarked: true }; });
  return o;
}

const FONT = 'var(--font-sans)';

/* A rounded-square (or circle) folder tile with the bookmark glyph. */
function FolderTile({ color, size = 38, round, icon = 'bookmark' }) {
  return (
    <span style={{ width: size, height: size, flex: 'none', borderRadius: round ? '50%' : Math.round(size * 0.28),
      background: color, color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.14), inset 0 -5px 12px rgba(0,0,0,.14)' }}>
      <span style={{ display: 'inline-flex', width: Math.round(size * 0.5), height: Math.round(size * 0.5) }}>
        <Glyph name={icon} size={Math.round(size * 0.5)} />
      </span>
    </span>
  );
}

/* Small ghost icon button used in the sub-bar / rows. */
function BmIconBtn({ icon, onClick, title, danger, size = 17, active }) {
  const [h, setH] = React.useState(false);
  return (
    <button title={title} onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ width: 30, height: 30, borderRadius: 8, border: 'none', flex: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
        background: active || h ? (danger ? 'color-mix(in srgb, var(--negative) 14%, transparent)' : 'var(--gray-100)') : 'transparent',
        color: danger ? 'var(--negative)' : (active ? 'var(--fg-heading)' : 'var(--fg-subdued)'), transition: 'background .12s, color .12s' }}>
      <span style={{ display: 'inline-flex', width: size, height: size }}><Glyph name={icon} size={size} /></span>
    </button>
  );
}

/* Pill text button (primary = accent fill, secondary = hairline). */
function PillBtn({ label, onClick, primary, danger, disabled, icon }) {
  const [h, setH] = React.useState(false);
  const base = { height: 34, padding: icon ? '0 16px 0 13px' : '0 16px', borderRadius: 9999, cursor: disabled ? 'default' : 'pointer',
    fontFamily: FONT, fontSize: 13.5, fontWeight: 700, display: 'inline-flex', alignItems: 'center', gap: 7, transition: 'background .12s, color .12s, border-color .12s', whiteSpace: 'nowrap' };
  let st;
  if (primary) st = { ...base, border: 'none', background: disabled ? 'var(--border-disabled)' : (h ? 'var(--accent-bg-hover)' : 'var(--accent-bg)'), color: '#fff' };
  else if (danger) st = { ...base, border: '1px solid var(--border-strong)', background: h ? 'color-mix(in srgb, var(--negative) 12%, transparent)' : 'transparent', color: 'var(--negative)', borderColor: h ? 'var(--negative)' : 'var(--border-strong)' };
  else st = { ...base, border: '1px solid var(--border-strong)', background: h ? 'var(--gray-100)' : 'transparent', color: 'var(--fg-heading)' };
  return (
    <button onClick={disabled ? undefined : onClick} disabled={disabled} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)} style={{ ...st, opacity: disabled ? 0.55 : 1 }}>
      {icon && <span style={{ display: 'inline-flex', width: 16, height: 16 }}><Glyph name={icon} size={16} /></span>}
      {label}
    </button>
  );
}

/* ── Create / edit folder dialog ── */
function FolderDialog({ mode, folder, isX, onSave, onDelete, onClose, startConfirm }) {
  const [name, setName] = React.useState(folder ? folder.name : '');
  const [color, setColor] = React.useState(folder ? folder.color : FOLDER_PALETTE[0]);
  const [confirming, setConfirming] = React.useState(!!startConfirm);
  const inputRef = React.useRef(null);
  React.useEffect(() => { if (!confirming && inputRef.current) inputRef.current.focus(); }, [confirming]);
  const valid = name.trim().length > 0;
  const save = () => { if (valid) onSave({ name: name.trim(), color }); };

  return (
    <div onClick={onClose} style={{ position: 'absolute', inset: 0, zIndex: 70, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20,
      background: 'color-mix(in srgb, var(--gray-1000) 34%, transparent)' }}>
      <div onClick={e => e.stopPropagation()} style={{ width: '100%', maxWidth: 320, background: 'var(--bg-elevated)', border: '1px solid var(--border-default)',
        borderRadius: 16, boxShadow: 'var(--shadow-elevated)', padding: 18, fontFamily: FONT, animation: 'bmPop .14s var(--ease-default)' }}>

        {confirming ? (
          <React.Fragment>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', gap: 12 }}>
              <span style={{ width: 48, height: 48, borderRadius: '50%', background: 'var(--negative-bg)', color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
                <span style={{ display: 'inline-flex', width: 24, height: 24 }}><Glyph name="trash" size={24} /></span>
              </span>
              <div>
                <div style={{ fontSize: 16.5, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.01em', marginBottom: 5 }}>{isX ? `Delete “${folder.name}”?` : `删除“${folder.name}”？`}</div>
                <div style={{ fontSize: 13.5, lineHeight: 1.5, color: 'var(--fg-subdued)' }}>{isX ? "The folder is removed. Your bookmarks stay saved in All bookmarks." : '文件夹将被删除，其中的收藏仍会保留在“全部收藏”里。'}</div>
              </div>
            </div>
            <div style={{ display: 'flex', gap: 10, marginTop: 18 }}>
              <div style={{ flex: 1 }}><PillBtn label={isX ? 'Cancel' : '取消'} onClick={() => (startConfirm ? onClose() : setConfirming(false))} /></div>
              <button onClick={onDelete} style={{ flex: 1, height: 34, borderRadius: 9999, border: 'none', cursor: 'pointer', background: 'var(--negative)', color: '#fff', fontFamily: FONT, fontSize: 13.5, fontWeight: 700 }}>{isX ? 'Delete' : '删除'}</button>
            </div>
          </React.Fragment>
        ) : (
          <React.Fragment>
            <div style={{ display: 'flex', alignItems: 'center', gap: 11, marginBottom: 16 }}>
              <FolderTile color={color} size={40} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 16.5, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.01em' }}>{mode === 'edit' ? (isX ? 'Edit folder' : '编辑文件夹') : (isX ? 'New folder' : '新建文件夹')}</div>
                <div style={{ fontSize: 12.5, color: 'var(--fg-subdued)' }}>{name.trim() || (isX ? 'Pick a name and color' : '选择名称和颜色')}</div>
              </div>
            </div>

            <label style={{ display: 'block', fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.05em', color: 'var(--fg-subdued)', marginBottom: 6 }}>{isX ? 'Name' : '名称'}</label>
            <input ref={inputRef} value={name} maxLength={32} onChange={e => setName(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') save(); }}
              placeholder={isX ? 'Folder name' : '文件夹名称'} style={{ width: '100%', boxSizing: 'border-box', height: 38, padding: '0 12px', borderRadius: 9, border: '1px solid var(--border-default)',
                background: 'var(--bg-base)', color: 'var(--fg-body)', fontSize: 14.5, fontFamily: FONT, outline: 'none' }}
              onFocus={e => { e.target.style.borderColor = 'var(--accent)'; e.target.style.boxShadow = '0 0 0 2px color-mix(in srgb, var(--accent) 32%, transparent)'; }}
              onBlur={e => { e.target.style.borderColor = 'var(--border-default)'; e.target.style.boxShadow = 'none'; }} />

            <div style={{ fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.05em', color: 'var(--fg-subdued)', margin: '16px 0 9px' }}>{isX ? 'Color' : '颜色'}</div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10 }}>
              {FOLDER_PALETTE.map(c => {
                const on = c === color;
                return (
                  <button key={c} onClick={() => setColor(c)} title={c}
                    style={{ width: 28, height: 28, borderRadius: '50%', border: 'none', cursor: 'pointer', background: c, position: 'relative',
                      boxShadow: on ? '0 0 0 2px var(--bg-elevated), 0 0 0 4px var(--fg-heading)' : 'inset 0 0 0 1px rgba(255,255,255,.16)', transition: 'box-shadow .12s' }}>
                    {on && <span style={{ position: 'absolute', inset: 0, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}><Glyph name="checkmark" size={16} /></span>}
                  </button>
                );
              })}
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 20 }}>
              {mode === 'edit'
                ? <button onClick={() => setConfirming(true)} title={isX ? 'Delete folder' : '删除文件夹'}
                    style={{ width: 36, height: 34, borderRadius: 9, border: '1px solid var(--border-strong)', background: 'transparent', color: 'var(--negative)', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}
                    onMouseEnter={e => { e.currentTarget.style.background = 'color-mix(in srgb, var(--negative) 12%, transparent)'; e.currentTarget.style.borderColor = 'var(--negative)'; }}
                    onMouseLeave={e => { e.currentTarget.style.background = 'transparent'; e.currentTarget.style.borderColor = 'var(--border-strong)'; }}>
                    <span style={{ display: 'inline-flex', width: 16, height: 16 }}><Glyph name="trash" size={16} /></span>
                  </button>
                : null}
              <div style={{ flex: 1 }} />
              <PillBtn label={isX ? 'Cancel' : '取消'} onClick={onClose} />
              <PillBtn label={mode === 'edit' ? (isX ? 'Save' : '保存') : (isX ? 'Create' : '创建')} primary disabled={!valid} onClick={save} />
            </div>
          </React.Fragment>
        )}
      </div>
    </div>
  );
}

/* Folder picker popover used by Select-mode "Move" — choose a destination. */
function MovePopover({ folders, isX, onPick, onNew, onClose }) {
  return (
    <React.Fragment>
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 88 }} />
      <div onClick={e => e.stopPropagation()} className="col-scroll" style={{ position: 'absolute', bottom: 50, left: '50%', transform: 'translateX(-50%)', width: 244, maxHeight: 300, overflowY: 'auto',
        background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', borderRadius: 13, boxShadow: 'var(--shadow-elevated)', padding: 6, zIndex: 89, animation: 'bmPop .12s var(--ease-default)' }}>
        <div style={{ fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.06em', color: 'var(--fg-subdued)', padding: '6px 10px 4px' }}>{isX ? 'Move to' : '移动到'}</div>
        {folders.map(f => (
          <button key={f.id} onClick={() => onPick(f.id)} style={{ display: 'flex', alignItems: 'center', gap: 11, width: '100%', padding: '7px 10px', borderRadius: 9, border: 'none', background: 'transparent', cursor: 'pointer', textAlign: 'left', color: 'var(--fg-body)', fontSize: 14, fontWeight: 600, fontFamily: FONT }}
            onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-100)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
            <FolderTile color={f.color} size={26} />
            <span style={{ flex: 1, minWidth: 0, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{f.name}</span>
          </button>
        ))}
        <div style={{ height: 1, background: 'var(--border-default)', margin: '5px 8px' }} />
        <button onClick={() => onPick(null)} style={{ display: 'flex', alignItems: 'center', gap: 11, width: '100%', padding: '7px 10px', borderRadius: 9, border: 'none', background: 'transparent', cursor: 'pointer', textAlign: 'left', color: 'var(--fg-subdued)', fontSize: 14, fontWeight: 600, fontFamily: FONT }}
          onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-100)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
          <span style={{ width: 26, height: 26, borderRadius: 7, flex: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: 'var(--fg-subdued)', background: 'var(--gray-100)' }}><Glyph name="close" size={14} /></span>
          {isX ? 'Remove from folder' : '移出文件夹'}
        </button>
        <button onClick={onNew} style={{ display: 'flex', alignItems: 'center', gap: 11, width: '100%', padding: '7px 10px', borderRadius: 9, border: 'none', background: 'transparent', cursor: 'pointer', textAlign: 'left', color: 'var(--accent)', fontSize: 14, fontWeight: 700, fontFamily: FONT }}
          onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-100)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
          <span style={{ width: 26, height: 26, borderRadius: 7, flex: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent)', background: 'color-mix(in srgb, var(--accent) 14%, transparent)' }}><Glyph name="add" size={15} /></span>
          {isX ? 'New folder…' : '新建文件夹…'}
        </button>
      </div>
    </React.Fragment>
  );
}

/* A filter chip in the sticky strip. Tap to scope the list to a folder. */
function FilterChip({ label, count, color, selected, showCount, round, onClick }) {
  const [h, setH] = React.useState(false);
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ flex: 'none', height: 32, display: 'inline-flex', alignItems: 'center', gap: 7, padding: color ? '0 12px 0 9px' : '0 13px', borderRadius: 9999, border: 'none', cursor: 'pointer', fontFamily: FONT, fontSize: 13.5, fontWeight: 700, letterSpacing: '-.005em', whiteSpace: 'nowrap', transition: 'background .12s, color .12s, box-shadow .12s',
        background: selected ? 'var(--accent-bg)' : (h ? 'var(--gray-200)' : 'var(--gray-100)'),
        color: selected ? '#fff' : 'var(--fg-body)' }}>
      {color && <span style={{ width: 13, height: 13, flex: 'none', borderRadius: round ? '50%' : 4, background: color, boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.2)' + (selected ? ', 0 0 0 1.5px rgba(255,255,255,.5)' : '') }} />}
      {label}
      {showCount && count != null && <span style={{ fontSize: 11.5, fontWeight: 800, fontVariantNumeric: 'tabular-nums', color: selected ? 'rgba(255,255,255,.82)' : 'var(--fg-subdued)' }}>{count}</span>}
    </button>
  );
}

/* A post wrapped for Select mode: a tap toggles selection instead of opening. */
function SelectablePost({ post, platform, selected, onToggle }) {
  return (
    <div style={{ position: 'relative' }}>
      <Post post={post} platform={platform} onAction={() => {}} onReply={() => {}} onOpenPost={() => {}} onOpenProfile={() => {}} onMention={() => {}} onQuote={() => {}} onRepost={() => {}} onDirectRepost={() => {}} onOpenMedia={() => {}} />
      <div onClick={onToggle} style={{ position: 'absolute', inset: 0, cursor: 'pointer',
        background: selected ? 'color-mix(in srgb, var(--accent) 12%, transparent)' : 'transparent',
        boxShadow: selected ? 'inset 3px 0 0 var(--accent)' : 'none', transition: 'background .12s' }}>
        <span style={{ position: 'absolute', top: 14, right: 14, width: 22, height: 22, borderRadius: '50%',
          border: selected ? 'none' : '2px solid var(--border-strong)', background: selected ? 'var(--accent-bg)' : 'color-mix(in srgb, var(--bg-base) 70%, transparent)',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}>
          {selected && <Glyph name="checkmark" size={15} />}
        </span>
      </div>
    </div>
  );
}

/* Centered empty state for a folder / search with no posts. */
function BmEmpty({ icon, title, body }) {
  return (
    <div style={{ padding: '64px 32px', textAlign: 'center', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 13 }}>
      <span style={{ width: 54, height: 54, borderRadius: '50%', background: 'var(--gray-100)', color: 'var(--fg-subdued)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
        <span style={{ display: 'inline-flex', width: 27, height: 27 }}><Glyph name={icon} size={27} /></span>
      </span>
      <div>
        <div style={{ fontSize: 16, fontWeight: 800, color: 'var(--fg-heading)', fontFamily: FONT, marginBottom: 5, letterSpacing: '-.01em' }}>{title}</div>
        <div style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--fg-subdued)', fontFamily: FONT, maxWidth: 280 }}>{body}</div>
      </div>
    </div>
  );
}

/* ── Main view: bookmarks shown by default, with a one-tap folder filter
   strip. Owns search, the create/edit dialog, and Select-to-organize. ── */
function BookmarksView({ account, isX, posts, folders, bmFolder, onAddFolder, onUpdateFolder, onDeleteFolder, onSetFolder, handlers, tweaks }) {
  const plat = account.platform;
  const folderList = folders[plat] || [];
  const round = (tweaks && tweaks.bmShape) === 'circle';
  const showCount = !tweaks || tweaks.bmCounts !== false;

  const [scope, setScope] = React.useState('__all__');   // '__all__' | folderId
  const [searchOpen, setSearchOpen] = React.useState(false);
  const [query, setQuery] = React.useState('');
  const [dialog, setDialog] = React.useState(null);       // { mode, folder?, assignIds?, confirm? }
  const [selectMode, setSelectMode] = React.useState(false);
  const [selected, setSelected] = React.useState({});
  const [moveOpen, setMoveOpen] = React.useState(false);
  const searchRef = React.useRef(null);

  // A deleted / missing folder falls back to All.
  React.useEffect(() => {
    if (scope !== '__all__' && !folderList.some(f => f.id === scope)) setScope('__all__');
  }, [folderList, scope]);
  React.useEffect(() => { if (searchOpen && searchRef.current) searchRef.current.focus(); }, [searchOpen]);

  const countIn = (fid) => posts.filter(p => bmFolder[p.id] === fid).length;
  const curFolder = folderList.find(f => f.id === scope) || null;
  const exitSelect = () => { setSelectMode(false); setSelected({}); setMoveOpen(false); };
  const selIds = Object.keys(selected).filter(id => selected[id]);
  const pickScope = (v) => { setScope(v); setSelected({}); };

  const openNew = (assignIds) => setDialog({ mode: 'new', assignIds: assignIds || null });
  const saveDialog = (data) => {
    if (dialog.mode === 'new') {
      const id = onAddFolder(plat, data);
      if (dialog.assignIds) { dialog.assignIds.forEach(pid => onSetFolder(pid, id)); exitSelect(); }
      else pickScope(id);
    } else {
      onUpdateFolder(plat, dialog.folder.id, data);
    }
    setDialog(null);
  };
  const doDelete = () => { onDeleteFolder(plat, dialog.folder.id); setDialog(null); };
  const moveSelected = (fid) => { selIds.forEach(pid => onSetFolder(pid, fid)); setMoveOpen(false); exitSelect(); };
  const removeSelected = () => { selIds.forEach(pid => handlers.onAction && handlers.onAction(pid, 'bookmarked')); exitSelect(); };

  const q = query.trim().toLowerCase();
  const searching = searchOpen && q.length > 0;
  const base = scope === '__all__' ? posts : posts.filter(p => bmFolder[p.id] === scope);
  const list = searching ? base.filter(p => (p.text || '').toLowerCase().includes(q) || (p.author && ((p.author.name || '').toLowerCase().includes(q) || (p.author.handle || '').toLowerCase().includes(q)))) : base;

  const closeSearch = () => { setSearchOpen(false); setQuery(''); };

  return (
    <div style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', position: 'relative' }}>
      {/* ── filter / toolbar strip ── */}
      <div style={{ flex: 'none', borderBottom: '1px solid var(--border-default)', background: 'var(--bg-base)', position: 'relative', zIndex: 2 }}>
        {searchOpen ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '9px 10px' }}>
            <div style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', gap: 8, height: 36, padding: '0 12px', borderRadius: 9999, background: 'var(--bg-layer-1)', border: '1px solid var(--border-default)' }}>
              <span style={{ display: 'inline-flex', width: 17, height: 17, color: 'var(--fg-subdued)', flex: 'none' }}><Glyph name="search" size={17} /></span>
              <input ref={searchRef} value={query} onChange={e => setQuery(e.target.value)} onKeyDown={e => { if (e.key === 'Escape') closeSearch(); }}
                placeholder={curFolder ? (isX ? `Search ${curFolder.name}` : `搜索${curFolder.name}`) : (isX ? 'Search bookmarks' : '搜索收藏')}
                style={{ flex: 1, minWidth: 0, border: 'none', background: 'none', outline: 'none', fontSize: 14, fontFamily: FONT, color: 'var(--fg-body)' }} />
            </div>
            <button onClick={closeSearch} style={{ height: 34, padding: '0 10px', borderRadius: 8, border: 'none', cursor: 'pointer', background: 'transparent', color: 'var(--accent)', fontFamily: FONT, fontSize: 13.5, fontWeight: 700, flex: 'none' }}
              onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-100)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>{isX ? 'Cancel' : '取消'}</button>
          </div>
        ) : (
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '8px 8px 8px 10px' }}>
            <div className="bm-chips" style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', gap: 6, overflowX: 'auto', overflowY: 'hidden', scrollbarWidth: 'none' }}>
              <FilterChip label={isX ? 'All' : '全部'} count={posts.length} selected={scope === '__all__'} showCount={showCount} onClick={() => pickScope('__all__')} />
              {folderList.map(f => (
                <FilterChip key={f.id} label={f.name} color={f.color} count={countIn(f.id)} round={round} selected={scope === f.id} showCount={showCount} onClick={() => pickScope(f.id)} />
              ))}
              <button onClick={() => openNew()} title={isX ? 'New folder' : '新建文件夹'}
                style={{ flex: 'none', height: 32, display: 'inline-flex', alignItems: 'center', gap: 5, padding: '0 13px 0 10px', borderRadius: 9999, border: '1.5px dashed var(--gray-400)', background: 'transparent', cursor: 'pointer', fontFamily: FONT, fontSize: 13.5, fontWeight: 700, color: 'var(--fg-subdued)', whiteSpace: 'nowrap', transition: 'color .12s, border-color .12s' }}
                onMouseEnter={e => { e.currentTarget.style.color = 'var(--fg-body)'; e.currentTarget.style.borderColor = 'var(--gray-500)'; }}
                onMouseLeave={e => { e.currentTarget.style.color = 'var(--fg-subdued)'; e.currentTarget.style.borderColor = 'var(--gray-400)'; }}>
                <span style={{ display: 'inline-flex', width: 15, height: 15 }}><Glyph name="add" size={15} /></span>{isX ? 'New' : '新建'}
              </button>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 2, flex: 'none', paddingLeft: 2 }}>
              <BmIconBtn icon="search" title={isX ? 'Search' : '搜索'} onClick={() => setSearchOpen(true)} />
              {curFolder && <BmIconBtn icon="pencil" title={isX ? 'Edit folder' : '编辑文件夹'} onClick={() => setDialog({ mode: 'edit', folder: curFolder })} />}
              {posts.length > 0 && <BmIconBtn icon="checkmark-circle" title={isX ? 'Select' : '选择'} active={selectMode} onClick={() => (selectMode ? exitSelect() : setSelectMode(true))} />}
            </div>
          </div>
        )}
      </div>

      {/* ── results ── */}
      <div className="col-scroll" style={{ flex: 1, overflowY: 'auto', overflowX: 'hidden' }}>
        {list.length === 0 ? (
          searching
            ? <BmEmpty icon="search" title={isX ? 'No matches' : '没有匹配的收藏'} body={isX ? 'Try a different word.' : '换个关键词试试。'} />
            : scope === '__all__'
              ? <BmEmpty icon="bookmark" title={isX ? 'No bookmarks yet' : '还没有收藏'} body={isX ? 'Save posts to read them later.' : '收藏内容方便稍后阅读。'} />
              : <BmEmpty icon="folder" title={isX ? 'This folder is empty' : '这个文件夹是空的'} body={isX ? 'Tap Select, then Move to add bookmarks here.' : '点击“选择”再“移动”，把收藏放进这个文件夹。'} />
        ) : selectMode ? (
          list.map(p => <SelectablePost key={p.id} post={p} platform={plat} selected={!!selected[p.id]} onToggle={() => setSelected(s => ({ ...s, [p.id]: !s[p.id] }))} />)
        ) : (
          <ThreadedList posts={list} platform={plat} handlers={handlers} />
        )}
        <div style={{ height: selectMode ? 80 : 24 }} />
      </div>

      {/* ── select action bar ── */}
      {selectMode && (
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: 14, display: 'flex', justifyContent: 'center', pointerEvents: 'none' }}>
          <div style={{ position: 'relative', pointerEvents: 'auto', display: 'flex', alignItems: 'center', gap: 6, padding: '7px 7px 7px 16px', borderRadius: 9999, background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', boxShadow: 'var(--shadow-elevated)', fontFamily: FONT, maxWidth: '100%' }}>
            <span style={{ fontSize: 13.5, fontWeight: 700, color: selIds.length ? 'var(--fg-heading)' : 'var(--fg-subdued)', whiteSpace: 'nowrap' }}>{selIds.length ? (isX ? `${selIds.length} selected` : `已选 ${selIds.length} 项`) : (isX ? 'Select posts' : '选择内容')}</span>
            <div style={{ width: 1, height: 22, background: 'var(--border-default)', margin: '0 4px' }} />
            <PillBtn label={isX ? 'Move' : '移动'} icon="folder" primary disabled={!selIds.length} onClick={() => setMoveOpen(true)} />
            <BmIconBtn icon="trash" title={isX ? 'Remove from bookmarks' : '移除收藏'} danger onClick={selIds.length ? removeSelected : undefined} />
            <div style={{ width: 1, height: 22, background: 'var(--border-default)', margin: '0 2px' }} />
            <BmIconBtn icon="close" title={isX ? 'Done' : '完成'} onClick={exitSelect} />
            {moveOpen && <MovePopover folders={folderList} isX={isX} onPick={moveSelected} onNew={() => { setMoveOpen(false); openNew(selIds); }} onClose={() => setMoveOpen(false)} />}
          </div>
        </div>
      )}

      {dialog && <FolderDialog mode={dialog.mode} folder={dialog.folder} startConfirm={dialog.confirm} isX={isX} onSave={saveDialog} onDelete={doDelete} onClose={() => setDialog(null)} />}
    </div>
  );
}

Object.assign(window, { BookmarksView, SEED_FOLDERS, SEED_ASSIGN, FOLDER_PALETTE, bookmarkSeedOverrides });

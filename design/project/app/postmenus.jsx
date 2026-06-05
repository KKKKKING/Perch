/* Post detail chrome: Subscribe pill, the ··· overflow menu, and the share
   menu. Both menus borrow native macOS context-menu manners — sectioned items,
   right-aligned ⌘ shortcut hints, destructive actions in red — rendered with
   Spectrum 2's elevated-popover surface. Loaded as Babel JSX before detail.jsx. */

/* Right-aligned keycap cluster, e.g. ⌘C — the Mac tell on a menu row. */
function Kbd({ combo }) {
  return (
    <span style={{ marginLeft: 'auto', display: 'inline-flex', alignItems: 'center', gap: 2, color: 'var(--fg-disabled)', fontSize: 12.5, fontWeight: 600, fontFamily: 'var(--font-sans)', letterSpacing: '.02em', flex: 'none', paddingLeft: 14 }}>{combo}</span>
  );
}

function MenuItem({ icon, label, sub, kbd, danger, onClick }) {
  const [h, setH] = React.useState(false);
  const tint = danger ? 'var(--negative)' : 'var(--fg-body)';
  return (
    <button onClick={(e) => { e.stopPropagation(); onClick && onClick(); }} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', padding: '8px 11px', borderRadius: 8, border: 'none', cursor: 'pointer', textAlign: 'left',
        background: h ? (danger ? 'color-mix(in srgb, var(--negative) 13%, transparent)' : 'var(--gray-100)') : 'transparent', color: tint, fontFamily: 'var(--font-sans)', transition: 'background .1s' }}>
      <span style={{ display: 'inline-flex', width: 19, height: 19, flex: 'none', color: danger ? 'var(--negative)' : 'var(--fg-subdued)' }}><Glyph name={icon} size={19} /></span>
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'block', fontSize: 14, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{label}</span>
        {sub && <span style={{ display: 'block', fontSize: 12, fontWeight: 500, color: 'var(--fg-subdued)', marginTop: 1 }}>{sub}</span>}
      </span>
      {kbd && <Kbd combo={kbd} />}
    </button>
  );
}

function MenuSep() {
  return <div style={{ height: 1, background: 'var(--border-default)', margin: '5px 8px' }} />;
}

/* Shared popover shell: outside-click scrim + the elevated surface. `place`
   anchors it (the more menu drops down-end; share pops up-end over its button). */
function MenuShell({ place, width, onClose, children }) {
  const pos = place === 'up'
    ? { bottom: 36, right: -4 }
    : { top: 34, right: -4 };
  return (
    <React.Fragment>
      <div onClick={(e) => { e.stopPropagation(); onClose(); }} style={{ position: 'fixed', inset: 0, zIndex: 90 }} />
      <div onClick={(e) => e.stopPropagation()} role="menu"
        style={{ position: 'absolute', ...pos, width, zIndex: 91, background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', borderRadius: 13, boxShadow: 'var(--shadow-elevated)', padding: 6, animation: 'winPop .13s var(--ease-default)' }}>
        {children}
      </div>
    </React.Fragment>
  );
}

/* ··· overflow — the long X menu, trimmed to the meaningful actions and given
   Mac affordances (Open in new window, ⌘-shortcuts). */
function PostMoreMenu({ post, isX, following, onToggleFollow, onFlash, onClose }) {
  const handle = post.author.handle;
  const at = isX ? '@' + handle : post.author.name;
  const done = (msg) => { onClose(); if (msg && onFlash) onFlash(msg); };
  return (
    <MenuShell place="down" width={252} onClose={onClose}>
      {window.DebugBus && DebugBus.enabled() && (
        <React.Fragment>
          <MenuItem icon="code" label={isX ? 'View raw JSON' : '查看原始 JSON'}
            onClick={() => { onClose(); DebugBus.openJson(isX ? 'Tweet · ' + post.author.name : '微博 · ' + post.author.name, post, (isX ? '@' + post.author.handle : post.author.name) + ' · id ' + post.id); }} />
          <MenuSep />
        </React.Fragment>
      )}
      <MenuItem icon={following ? 'block' : 'user'} label={following ? (isX ? `Unfollow ${at}` : `取消关注 ${at}`) : (isX ? `Follow ${at}` : `关注 ${at}`)}
        onClick={() => { onToggleFollow(); done(following ? (isX ? `Unfollowed ${at}` : `已取消关注`) : (isX ? `Following ${at}` : `已关注`)); }} />
      <MenuItem icon="list" label={isX ? 'Add/remove from Lists' : '从列表中添加/移除'} onClick={() => done(isX ? 'Lists updated' : '已更新列表')} />
      <MenuSep />
      <MenuItem icon="mute-chat" label={isX ? 'Mute this conversation' : '隐藏此对话'} onClick={() => done(isX ? 'Conversation muted' : '已隐藏对话')} />
      <MenuItem icon="mute" label={isX ? `Mute ${at}` : `隐藏 ${at}`} onClick={() => done(isX ? `Muted ${at}` : `已隐藏 ${at}`)} />
      <MenuItem icon="block" label={isX ? `Block ${at}` : `屏蔽 ${at}`} danger onClick={() => done(isX ? `Blocked ${at}` : `已屏蔽 ${at}`)} />
      <MenuSep />
      <MenuItem icon="newwindow" label={isX ? 'Open in new window' : '在新窗口打开'} kbd="⌘⏎" onClick={() => done(isX ? 'Opened in new window' : '已在新窗口打开')} />
      <MenuItem icon="poll" label={isX ? 'View post analytics' : '查看帖子动态'} onClick={() => done()} />
      <MenuItem icon="code" label={isX ? 'Embed post' : '嵌入帖子'} onClick={() => done(isX ? 'Embed code copied' : '已复制嵌入代码')} />
      <MenuSep />
      <MenuItem icon="flag" label={isX ? 'Report post' : '举报帖子'} danger onClick={() => done(isX ? 'Report submitted' : '举报已提交')} />
    </MenuShell>
  );
}

/* Share menu — Copy link · Send via DM · the macOS share sheet · Bookmark. */
function ShareMenu({ post, isX, hasMedia, onBookmark, bookmarked, onFlash, onClose }) {
  const done = (msg) => { onClose(); if (msg && onFlash) onFlash(msg); };
  return (
    <MenuShell place="up" width={248} onClose={onClose}>
      <MenuItem icon="message" label={isX ? 'Send via Direct Message' : '通过私信发送'} onClick={() => done(isX ? 'Opening message…' : '正在打开私信…')} />
      <MenuItem icon="link" label={isX ? 'Copy link' : '复制链接'} kbd="⌘C" onClick={() => done(isX ? 'Link copied' : '已复制链接')} />
      <MenuItem icon="share" label={isX ? 'Share via…' : '帖子分享途径…'} sub={isX ? 'AirDrop, Mail, and more' : '隔空投送、邮件等'} onClick={() => done()} />
      {hasMedia && <MenuItem icon="download" label={isX ? 'Save media' : '存储媒体'} onClick={() => done(isX ? 'Saved to Downloads' : '已存储到下载')} />}
      <MenuSep />
      <MenuItem icon="folder" label={isX ? (bookmarked ? 'Remove bookmark' : 'Bookmark to folder') : (bookmarked ? '取消收藏' : '收藏到文件夹')} kbd="⌘D"
        onClick={() => { onBookmark && onBookmark(); done(bookmarked ? (isX ? 'Removed' : '已取消收藏') : (isX ? 'Bookmarked' : '已收藏')); }} />
    </MenuShell>
  );
}

/* Column-local toast for menu actions (keeps detail self-contained). */
function ColFlash({ msg }) {
  if (!msg) return null;
  return (
    <div style={{ position: 'absolute', bottom: 18, left: '50%', transform: 'translateX(-50%)', zIndex: 95, display: 'inline-flex', alignItems: 'center', gap: 8, height: 38, padding: '0 16px', borderRadius: 9999, background: 'var(--gray-900)', color: 'var(--gray-25)', boxShadow: 'var(--shadow-elevated)', fontFamily: 'var(--font-sans)', fontSize: 13.5, fontWeight: 600, whiteSpace: 'nowrap', pointerEvents: 'none', animation: 'winPop .14s var(--ease-default)' }}>
      <span style={{ display: 'inline-flex', width: 17, height: 17, color: 'var(--green-700)' }}><Glyph name="checkmark-circle" size={17} /></span>
      {msg}
    </div>
  );
}

Object.assign(window, { PostMoreMenu, ShareMenu, ColFlash, MenuItem, MenuSep, MenuShell, Kbd });

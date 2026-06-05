/* Timeline lifecycle UI: loading skeleton, error + retry, empty state,
   the refresh control (spinner + new-count pill) and the floating
   "N new posts" banner. Pure presentation — the App owns the state. */

/* ── Loading: shimmer skeleton that mirrors the Post layout ── */
function SkelBlock({ w, h = 12, r = 6, style }) {
  return <span className="perch-skel" style={{ display: 'block', width: w, height: h, borderRadius: r, ...style }} />;
}

function SkelPost({ withMedia, isX }) {
  return (
    <div style={{ padding: '14px 16px', borderBottom: '1px solid var(--border-default)' }}>
      <div style={{ display: 'flex', gap: 11 }}>
        <SkelBlock w={40} h={40} r="50%" style={{ flex: 'none' }} />
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 8 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <SkelBlock w={isX ? 104 : 88} h={13} />
            <SkelBlock w={isX ? 70 : 46} h={11} />
            <div style={{ flex: 1 }} />
            <SkelBlock w={30} h={11} />
          </div>
          <SkelBlock w="96%" h={12} />
          <SkelBlock w="82%" h={12} />
          {withMedia && <SkelBlock w="100%" h={150} r={12} style={{ marginTop: 4 }} />}
          <div style={{ display: 'flex', gap: 40, marginTop: 6 }}>
            <SkelBlock w={26} h={11} /><SkelBlock w={26} h={11} /><SkelBlock w={26} h={11} /><SkelBlock w={18} h={11} />
          </div>
        </div>
      </div>
    </div>
  );
}

function TimelineSkeleton({ isX, count = 6 }) {
  return (
    <div aria-busy="true" aria-label={isX ? 'Loading timeline' : '正在加载'}>
      {Array.from({ length: count }).map((_, i) => (
        <SkelPost key={i} isX={isX} withMedia={i % 3 === 1} />
      ))}
    </div>
  );
}

/* ── Notification-shaped skeleton: mirrors the bell column's row rhythm
   (faux sub-tab strip + aggregated rows with an avatar stack + engagement
   rows with a leading avatar and action chips) so a cold load doesn't snap
   layout when the real rows arrive. ── */
function NotifSkelRow({ engage }) {
  return (
    <div style={{ display: 'flex', gap: engage ? 11 : 12, padding: '13px 16px 13px 14px', borderBottom: '1px solid var(--border-default)' }}>
      {engage
        ? <SkelBlock w={40} h={40} r="50%" style={{ flex: 'none' }} />
        : <SkelBlock w={20} h={20} r={6} style={{ flex: 'none', marginTop: 2 }} />}
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 8 }}>
        {!engage && (
          <div style={{ display: 'flex' }}>
            {[0, 1, 2, 3].map(i => (
              <span key={i} className="perch-skel" style={{ width: 30, height: 30, borderRadius: '50%', marginInlineStart: i ? -8 : 0, boxShadow: '0 0 0 2px var(--bg-base)' }} />
            ))}
          </div>
        )}
        <SkelBlock w={engage ? '54%' : '72%'} h={13} />
        <SkelBlock w="90%" h={12} />
        {engage && (
          <div style={{ display: 'flex', gap: 8, marginTop: 3 }}>
            <SkelBlock w={64} h={26} r={13} /><SkelBlock w={30} h={26} r={13} />
          </div>
        )}
      </div>
      {!engage && <SkelBlock w={46} h={46} r={10} style={{ flex: 'none' }} />}
    </div>
  );
}

function NotifSkeleton({ isX, count = 7 }) {
  return (
    <div aria-busy="true" aria-label={isX ? 'Loading notifications' : '正在加载通知'}>
      <div style={{ flex: 'none', padding: '8px 12px', borderBottom: '1px solid var(--border-default)' }}>
        <div style={{ display: 'flex', gap: 3, padding: 3, borderRadius: 9999, background: 'var(--gray-100)' }}>
          {[0, 1, 2].map(i => (
            <span key={i} className="perch-skel" style={{ height: 32, flex: i === 0 ? '0 0 70px' : '0 0 36px', borderRadius: 9999 }} />
          ))}
        </div>
      </div>
      {Array.from({ length: count }).map((_, i) => <NotifSkelRow key={i} engage={i % 3 === 2} />)}
    </div>
  );
}

/* ── Soft-reload pill: a small floating "checking for updates" chip shown over
   EXISTING content while a feed silently revalidates (re-entry or refresh).
   Unlike the skeleton it never hides what's already there — stale-while-
   revalidate. Pairs with the thin RefreshBar under the header. ── */
function SoftReloadPill({ isX }) {
  return (
    <div role="status" style={{ position: 'absolute', top: 12, left: '50%', transform: 'translateX(-50%)', zIndex: 6, display: 'inline-flex', alignItems: 'center', gap: 7, height: 30, padding: '0 14px', borderRadius: 9999, background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', boxShadow: 'var(--shadow-elevated)', fontFamily: 'var(--font-sans)', fontSize: 12.5, fontWeight: 700, color: 'var(--fg-subdued)', whiteSpace: 'nowrap', animation: 'perchBannerIn .26s var(--ease-default)' }}>
      <span style={{ display: 'inline-flex', width: 14, height: 14, color: 'var(--accent)', animation: 'perchSpin .8s linear infinite' }}><Glyph name="refresh" size={14} /></span>
      {isX ? 'Checking for updates…' : '正在检查更新…'}
    </div>
  );
}

/* ── Reload-error strip: a non-destructive failure banner for a WARM reload —
   the revalidation failed but we still have content, so we keep showing it and
   surface a dismissible strip with Retry instead of wiping to a full-screen
   error. (Cold loads with nothing to show still use TimelineError.) ── */
function ReloadErrorStrip({ isX, onRetry, retrying, onDismiss }) {
  const [hR, setHR] = React.useState(false);
  const [hX, setHX] = React.useState(false);
  return (
    <div role="alert" style={{ flex: 'none', display: 'flex', alignItems: 'center', gap: 10, padding: '9px 10px 9px 14px', background: 'var(--negative-bg)', borderBottom: '1px solid color-mix(in srgb, var(--negative) 32%, transparent)', animation: 'perchBannerIn .22s var(--ease-default)' }}>
      <span style={{ display: 'inline-flex', width: 18, height: 18, color: '#fff', flex: 'none' }}><Glyph name="info" size={18} /></span>
      <span style={{ flex: 1, minWidth: 0, fontFamily: 'var(--font-sans)', fontSize: 13.5, fontWeight: 600, color: '#fff', lineHeight: 1.35 }}>
        {isX ? "Couldn't refresh — showing older items" : '刷新失败 · 显示的是较早的内容'}
      </span>
      <button onClick={onRetry} disabled={retrying} onMouseEnter={() => setHR(true)} onMouseLeave={() => setHR(false)}
        style={{ flex: 'none', display: 'inline-flex', alignItems: 'center', gap: 6, height: 28, padding: '0 13px', borderRadius: 9999, border: 'none', cursor: retrying ? 'default' : 'pointer', fontFamily: 'var(--font-sans)', fontSize: 13, fontWeight: 700, color: 'var(--negative)', background: '#fff', opacity: retrying ? 0.8 : 1, transition: 'opacity .12s, transform .12s', transform: hR && !retrying ? 'translateY(-1px)' : 'none' }}>
        <span style={{ display: 'inline-flex', width: 14, height: 14, animation: retrying ? 'perchSpin .8s linear infinite' : 'none' }}><Glyph name="refresh" size={14} /></span>
        {retrying ? (isX ? 'Retrying…' : '重试中…') : (isX ? 'Retry' : '重试')}
      </button>
      <button onClick={onDismiss} title={isX ? 'Dismiss' : '忽略'} onMouseEnter={() => setHX(true)} onMouseLeave={() => setHX(false)}
        style={{ flex: 'none', width: 28, height: 28, borderRadius: 8, border: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', background: hX ? 'rgba(255,255,255,.18)' : 'transparent', color: '#fff', transition: 'background .12s' }}>
        <span style={{ display: 'inline-flex', width: 15, height: 15 }}><Glyph name="close" size={15} /></span>
      </button>
    </div>
  );
}

/* ── Error: failed load with a retry button ── */
function TimelineError({ isX, onRetry, retrying }) {
  const [h, setH] = React.useState(false);
  return (
    <div style={{ padding: '72px 32px', textAlign: 'center', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
      <span style={{ width: 56, height: 56, borderRadius: '50%', background: 'var(--negative-bg)', color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
        <svg width="30" height="30" viewBox="0 0 20 20" style={{ display: 'block' }} aria-hidden="true">
          <path fill="currentColor" d="M9.13 2.6a1 1 0 0 1 1.74 0l7.3 12.9a1 1 0 0 1-.87 1.5H2.7a1 1 0 0 1-.87-1.5L9.13 2.6Z" />
          <rect x="9.1" y="7.2" width="1.8" height="5" rx=".9" fill="var(--negative)" />
          <circle cx="10" cy="14.2" r="1.05" fill="var(--negative)" />
        </svg>
      </span>
      <div>
        <div style={{ fontSize: 16, fontWeight: 800, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', marginBottom: 5, letterSpacing: '-.01em' }}>
          {isX ? "Couldn't load timeline" : '加载失败'}
        </div>
        <div style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', maxWidth: 280 }}>
          {isX ? 'Check your connection and try again.' : '请检查网络连接后重试。'}
        </div>
      </div>
      <button onClick={onRetry} disabled={retrying} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
        style={{ display: 'inline-flex', alignItems: 'center', gap: 8, height: 38, padding: '0 18px', borderRadius: 9999, border: 'none', cursor: retrying ? 'default' : 'pointer', fontFamily: 'var(--font-sans)', fontSize: 14, fontWeight: 700, whiteSpace: 'nowrap', color: '#fff', background: h && !retrying ? 'var(--accent-bg-hover)' : 'var(--accent-bg)', transition: 'background .12s', opacity: retrying ? 0.7 : 1 }}>
        <span style={{ display: 'inline-flex', width: 16, height: 16, animation: retrying ? 'perchSpin .8s linear infinite' : 'none' }}><Glyph name="refresh" size={16} /></span>
        {retrying ? (isX ? 'Retrying…' : '重试中…') : (isX ? 'Try again' : '重试')}
      </button>
    </div>
  );
}

/* ── Empty: nothing in this feed yet ── */
function TimelineEmpty({ isX, type }) {
  const copy = {
    home:      [isX ? 'Your timeline is empty' : '时间线还是空的', isX ? 'Follow some people and their posts will show up here.' : '关注一些人，他们的内容会出现在这里。', 'home'],
    likes:     [isX ? 'No likes yet' : '还没有赞过', isX ? 'Posts you like will be collected here.' : '你点赞过的内容会收藏在这里。', 'heart'],
    bookmarks: [isX ? 'No bookmarks yet' : '还没有收藏', isX ? 'Save posts to read them later.' : '收藏内容方便稍后阅读。', 'bookmark'],
    search:    [isX ? 'No results' : '没有结果', isX ? 'Try a different search term.' : '换个关键词试试。', 'search'],
    profile:   [isX ? 'No posts yet' : '还没有动态', isX ? 'When they post, it will appear here.' : 'TA 发布的内容会出现在这里。', 'user'],
  };
  const [title, body, icon] = copy[type] || copy.home;
  return (
    <div style={{ padding: '72px 32px', textAlign: 'center', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
      <span style={{ width: 56, height: 56, borderRadius: '50%', background: 'var(--gray-100)', color: 'var(--fg-subdued)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
        <span style={{ display: 'inline-flex', width: 28, height: 28 }}><Glyph name={icon} size={28} /></span>
      </span>
      <div>
        <div style={{ fontSize: 16, fontWeight: 800, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', marginBottom: 5, letterSpacing: '-.01em' }}>{title}</div>
        <div style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', maxWidth: 280 }}>{body}</div>
      </div>
    </div>
  );
}

/* ── Refresh control for the column header — a Chrome-style split button.
   Left-click = normal refresh (spins in place, merges new posts onto your
   current view). Right-click = a context menu with the heavier reload modes
   the merge model otherwise hides: a hard reload that clears the column and
   rebuilds from the top, and an empty-cache reload that throws the whole
   session away. The new-post count lives in its own corner pill. ── */
function ReloadMenuItem({ title, desc, kbd, danger, onClick }) {
  const [hi, setHi] = React.useState(false);
  return (
    <button onClick={onClick} onMouseEnter={() => setHi(true)} onMouseLeave={() => setHi(false)}
      style={{ display: 'flex', alignItems: 'flex-start', gap: 12, width: '100%', padding: '8px 11px', borderRadius: 9, border: 'none', cursor: 'pointer', textAlign: 'left', background: hi ? 'var(--gray-100)' : 'transparent', transition: 'background .1s', fontFamily: 'var(--font-sans)' }}>
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'block', fontSize: 13.5, fontWeight: 700, letterSpacing: '-.01em', color: danger ? 'var(--orange-900)' : 'var(--fg-heading)' }}>{title}</span>
        <span style={{ display: 'block', fontSize: 11.5, fontWeight: 500, color: 'var(--fg-subdued)', marginTop: 1, lineHeight: 1.4, textWrap: 'pretty' }}>{desc}</span>
      </span>
      {kbd && <span style={{ flex: 'none', alignSelf: 'center', fontSize: 13.5, fontWeight: 500, color: 'var(--fg-subdued)', letterSpacing: '.06em', whiteSpace: 'nowrap' }}>{kbd}</span>}
    </button>
  );
}

function RefreshControl({ isX, refreshing, newCount, onClick, onHardReload, onEmptyReload, onMenuToggle }) {
  const [h, setH] = React.useState(false);
  const [menu, setMenu] = React.useState(false);
  const setOpen = (v) => { setMenu(v); if (onMenuToggle) onMenuToggle(v); };
  const close = () => setOpen(false);
  const openMenu = (e) => { e.preventDefault(); e.stopPropagation(); setOpen(true); };
  const run = (fn) => { close(); if (fn) fn(); };

  const T = isX ? {
    refresh: ['Normal reload', 'Pull in new posts, keep your place'],
    clear: ['Clear and reload', 'Discard everything and reload from the top'],
  } : {
    refresh: ['普通刷新', '拉取新内容，保留当前阅读位置'],
    clear: ['清空并重载', '丢弃全部内容，从顶部重新加载'],
  };

  return (
    <span style={{ position: 'relative', display: 'inline-flex' }}>
      <button title={isX ? 'Refresh — right-click for more' : '刷新 · 右键查看更多'}
        onClick={onClick} onContextMenu={openMenu}
        onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
        style={{ width: 30, height: 30, borderRadius: 8, border: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', background: (h || menu) ? 'var(--gray-100)' : 'transparent', color: (h || menu) ? 'var(--fg-heading)' : 'var(--fg-subdued)', transition: 'background .12s, color .12s' }}>
        <span style={{ display: 'inline-flex', width: 18, height: 18, animation: refreshing ? 'perchSpin .8s linear infinite' : 'none' }}><Glyph name="refresh" size={18} /></span>
      </button>

      {menu && (
        <React.Fragment>
          <div onClick={close} onContextMenu={(e) => { e.preventDefault(); close(); }}
            style={{ position: 'fixed', inset: 0, zIndex: 40 }} />
          <div role="menu" style={{ position: 'absolute', top: 37, right: 0, width: 272, background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', borderRadius: 13, boxShadow: 'var(--shadow-elevated)', padding: 6, zIndex: 41, transformOrigin: 'top right', animation: 'bmPop .14s var(--ease-default)' }}>
            <ReloadMenuItem title={T.refresh[0]} desc={T.refresh[1]} kbd="⌘R" onClick={() => run(onClick)} />
            <ReloadMenuItem title={T.clear[0]} desc={T.clear[1]} kbd="⇧⌘R" onClick={() => run(onEmptyReload)} />
          </div>
        </React.Fragment>
      )}
    </span>
  );
}

/* Indeterminate top progress bar shown under the header while refreshing. */
function RefreshBar() {
  return (
    <div style={{ height: 2, flex: 'none', overflow: 'hidden', background: 'color-mix(in srgb, var(--accent) 18%, transparent)', position: 'relative' }}>
      <span className="perch-refbar" style={{ position: 'absolute', inset: 0, width: '40%', background: 'var(--accent)', borderRadius: 9999 }} />
    </div>
  );
}

/* Small unread-count pill anchored to the top-right corner of the timeline.
   Shows just the number (99+ capped); tapping it loads the waiting posts. */
function NewPostsBanner({ isX, count, onClick }) {
  const [h, setH] = React.useState(false);
  const txt = count > 99 ? '99+' : String(count);
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      title={isX ? `${count} new — tap to load` : `${txt} 条新内容 · 点击加载`}
      style={{ position: 'absolute', top: 10, right: 14, zIndex: 5, minWidth: 22, height: 22, padding: txt.length > 1 ? '0 7px' : 0, borderRadius: 9999, border: 'none', cursor: 'pointer', background: h ? 'var(--accent-bg-hover)' : 'var(--accent-bg)', color: '#fff', fontFamily: 'var(--font-sans)', fontSize: 11.5, fontWeight: 800, letterSpacing: '-.02em', lineHeight: 1, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', boxShadow: 'var(--shadow-elevated)', transition: 'background .12s', animation: 'perchBannerIn .26s var(--ease-default)' }}>
      {txt}
    </button>
  );
}

/* ── Home column "new posts" pill: a centered accent capsule that previews
   WHO posted while you were away — an up-arrow, a stack of the waiting
   authors' avatars, and the live waiting count (the count replaces the
   "posted" label X normally shows). Tapping loads the waiting posts. Only
   the home timeline uses this richer pill; every other column keeps the
   compact corner number (NewPostsBanner). ── */
function StackAvatar({ person, size, ring }) {
  const initials = (person.name || '?').replace(/\s+/g, ' ').trim().split(' ').map(w => w[0]).slice(0, 2).join('');
  return (
    <span style={{ width: size, height: size, borderRadius: '50%', flex: 'none', background: person.color || 'var(--gray-500)', color: '#fff',
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: size * 0.4, fontWeight: 700,
      fontFamily: 'var(--font-sans)', letterSpacing: '-.02em', userSelect: 'none',
      boxShadow: `0 0 0 2px ${ring}, inset 0 0 0 1px rgba(255,255,255,.22), inset 0 -4px 9px rgba(0,0,0,.16)` }}>
      {initials}
    </span>
  );
}

function NewPostsPill({ isX, count, avatars, onClick }) {
  const [h, setH] = React.useState(false);
  const txt = count > 99 ? '99+' : String(count);
  const av = (avatars || []).slice(0, 3);
  const ring = h ? 'var(--accent-bg-hover)' : 'var(--accent-bg)';
  const extra = count - av.length;
  return (
    <div style={{ position: 'absolute', top: 12, left: 0, right: 0, zIndex: 5, display: 'flex', justifyContent: 'center', pointerEvents: 'none' }}>
      <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
        title={isX ? `${count} new posts from people you follow — tap to load` : `${txt} 条来自关注账号的新内容 · 点击加载`}
        style={{ pointerEvents: 'auto', display: 'inline-flex', alignItems: 'center', gap: 8, height: 36, padding: av.length ? '0 15px 0 11px' : '0 16px', borderRadius: 9999, border: 'none', cursor: 'pointer', maxWidth: 'calc(100% - 24px)',
          background: ring, color: '#fff', fontFamily: 'var(--font-sans)', fontSize: 14, fontWeight: 800, letterSpacing: '-.01em', whiteSpace: 'nowrap',
          boxShadow: 'var(--shadow-elevated)', transition: 'background .12s, transform .12s', transform: h ? 'translateY(-1px)' : 'none', animation: 'perchBannerIn .26s var(--ease-default)' }}>
        <span style={{ display: 'inline-flex', width: 18, height: 18, flex: 'none' }}><Glyph name="chevron-up" size={18} /></span>
        {av.length > 0 && (
          <span style={{ display: 'inline-flex', alignItems: 'center', flex: 'none' }}>
            {av.map((p, i) => (
              <span key={i} style={{ marginInlineStart: i ? -7 : 0, zIndex: av.length - i, display: 'inline-flex' }}>
                <StackAvatar person={p} size={24} ring={ring} />
              </span>
            ))}
          </span>
        )}
        <span style={{ fontVariantNumeric: 'tabular-nums', flex: 'none' }}>{txt}</span>
      </button>
    </div>
  );
}


/* ── Gap (断点): a tappable break standing in for posts that arrived between
   refreshes but weren't loaded. Reads as a torn seam through the timeline —
   a dashed rule with a centred pill. Tapping loads down from the post above
   it; while loading it shows a spinner. `count` (when known) hints how many
   posts are hiding in the break. ── */
function GapRow({ gap, isX, loading, count, onClick }) {
  const [h, setH] = React.useState(false);
  const n = count != null ? count : (typeof FeedStore !== 'undefined' ? FeedStore.gapSize(gap) : 0);
  const label = loading
    ? (isX ? 'Loading…' : '加载中…')
    : (isX ? 'Load missing posts' : '加载中断的内容');
  const dash = 'repeating-linear-gradient(90deg, var(--gray-400) 0 5px, transparent 5px 10px)';
  return (
    <div role="button" tabIndex={0} aria-label={isX ? 'Load missing posts' : '加载中断的内容'}
      onClick={loading ? undefined : onClick}
      onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ position: 'relative', display: 'flex', alignItems: 'center', gap: 12, padding: '13px 16px',
        borderBottom: '1px solid var(--border-default)', cursor: loading ? 'default' : 'pointer',
        background: h && !loading ? 'var(--bg-layer-1)' : 'var(--bg-layer-1)', transition: 'background .12s',
        animation: 'perchBannerIn .22s var(--ease-default)' }}>
      <span aria-hidden="true" style={{ flex: 1, height: 2, borderRadius: 2, background: dash, opacity: .9 }} />
      <span style={{ flex: 'none', display: 'inline-flex', alignItems: 'center', gap: 8, height: 30, padding: '0 14px', borderRadius: 9999,
        border: '1px solid var(--border-default)', background: h && !loading ? 'var(--accent-bg)' : 'var(--bg-base)',
        color: h && !loading ? '#fff' : 'var(--accent)', fontFamily: 'var(--font-sans)', fontSize: 13, fontWeight: 700,
        whiteSpace: 'nowrap', boxShadow: 'var(--shadow-emphasized)', transition: 'background .12s, color .12s, border-color .12s', borderColor: h && !loading ? 'transparent' : 'var(--border-default)' }}>
        <span style={{ display: 'inline-flex', width: 15, height: 15, animation: loading ? 'perchSpin .8s linear infinite' : 'none' }}>
          <Glyph name={loading ? 'refresh' : 'chevron-down'} size={15} />
        </span>
        {label}
      </span>
      <span aria-hidden="true" style={{ flex: 1, height: 2, borderRadius: 2, background: dash, opacity: .9 }} />
    </div>
  );
}

Object.assign(window, { TimelineSkeleton, NotifSkeleton, SoftReloadPill, ReloadErrorStrip, TimelineError, TimelineEmpty, RefreshControl, RefreshBar, NewPostsBanner, NewPostsPill, GapRow });

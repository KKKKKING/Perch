/* A single timeline column with iOS-style in-column navigation:
   the timeline is screen 0; tapping a post/profile pushes a screen that
   slides in from the right. The column owns the stack animation. */

const COLUMN_W = 374;       // preferred per-column width (used to size the window)
const COLUMN_MIN = 320;     // hard floor: columns never shrink below this
const COLUMN_MAX = 460;     // comfortable cap so columns don't stretch on huge monitors

function ColIconBtn({ name, onClick, title, size = 18 }) {
  const [h, setH] = React.useState(false);
  return (
    <button title={title} onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ width: 30, height: 30, borderRadius: 8, border: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', background: h ? 'var(--gray-100)' : 'transparent', color: h ? 'var(--fg-heading)' : 'var(--fg-subdued)', transition: 'background .12s, color .12s' }}>
      <span style={{ display: 'inline-flex', width: size, height: size }}><Glyph name={name} size={size} /></span>
    </button>
  );
}

const COL_META = {
  home:     { icon: 'home',   label_x: 'Home',     label_w: '主页' },
  mentions: { icon: 'bell',   label_x: 'Notifications', label_w: '消息' },
  search:   { icon: 'search', label_x: 'Search',   label_w: '搜索' },
  likes:    { icon: 'heart',  label_x: 'Likes',    label_w: '赞过' },
  bookmarks:{ icon: 'bookmark', label_x: 'Bookmarks', label_w: '收藏' },
  lists:    { icon: 'list',   label_x: 'Lists',    label_w: '列表' },
  profile:  { icon: 'user',   label_x: 'Profile',  label_w: '我的主页' },
};

const COL_TYPES = ['home', 'mentions', 'search', 'bookmarks', 'likes', 'lists', 'profile'];

/* iOS-style nav bar for a pushed screen: back chevron · centered title · refresh. */
function BackHeader({ title, onBack, onRefresh, isX }) {
  const [h, setH] = React.useState(false);
  const [spin, setSpin] = React.useState(false);
  const doRefresh = () => { setSpin(true); if (onRefresh) onRefresh(); setTimeout(() => setSpin(false), 700); };
  return (
    <header style={{ height: 54, flex: 'none', display: 'flex', alignItems: 'center', padding: '0 8px 0 4px', borderBottom: '1px solid var(--border-default)', background: 'color-mix(in srgb, var(--bg-base) 82%, transparent)', backdropFilter: 'blur(12px)', WebkitBackdropFilter: 'blur(12px)', position: 'relative' }}>
      <button onClick={onBack} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)} title={isX ? 'Back' : '返回'}
        style={{ height: 34, display: 'inline-flex', alignItems: 'center', padding: '0 8px 0 4px', borderRadius: 9, border: 'none', cursor: 'pointer', background: h ? 'var(--gray-100)' : 'transparent', color: 'var(--accent)', position: 'relative', zIndex: 1 }}>
        <span style={{ display: 'inline-flex', width: 23, height: 23, transform: 'rotate(90deg)' }}><Glyph name="chevron-down" size={23} /></span>
      </button>
      <div style={{ position: 'absolute', left: 52, right: 52, textAlign: 'center', fontSize: 16, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.015em', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', pointerEvents: 'none' }}>{title}</div>
      <div style={{ flex: 1 }} />
      <div style={{ flex: 'none', display: 'inline-flex', justifyContent: 'center', position: 'relative', zIndex: 1, transform: spin ? 'rotate(360deg)' : 'rotate(0deg)', transition: 'transform .7s var(--ease-default)' }}>
        <ColIconBtn name="refresh" title={isX ? 'Refresh' : '刷新'} onClick={doRefresh} />
      </div>
    </header>
  );
}

/* Screen 0: the live timeline with the account/title switcher + refresh. */
function TimelineScreen({ col, account, posts, view, isFirst, activeAccount, status, refreshing, newCount, newAuthors, onRefresh, onRetry, onScroll, onHardReload, onEmptyReload, softReloading, reloadError, onRetryReload, onDismissReloadError, onAction, onReply, onType, onAccount, onFeed, unread, onOpenPost, onOpenProfile, onMention, onQuote, onRepost, onDirectRepost, onOpenMedia, gapLoading, onLoadGap, folders, bmFolder, onAddFolder, onUpdateFolder, onDeleteFolder, onSetFolder, bmTweaks }) {
  const meta = COL_META[col.type] || COL_META.home;
  const isX = account.platform === 'x';
  const title = isX ? meta.label_x : meta.label_w;
  const [menu, setMenu] = React.useState(false);
  const [reloadMenu, setReloadMenu] = React.useState(false);
  const [hov, setHov] = React.useState(false);
  const bodyRef = React.useRef(null);
  const st = status || 'ready';
  const scrollTop = () => { if (bodyRef.current) bodyRef.current.scrollTo({ top: 0, behavior: 'smooth' }); };
  const doRefresh = () => { scrollTop(); if (onRefresh) onRefresh(col.id); };
  const loadNew = () => { scrollTop(); if (onRefresh) onRefresh(col.id); };
  const multiAccount = (typeof ACCOUNTS !== 'undefined') && ACCOUNTS.length > 1;
  const u = unread || {};
  const hideAvatar = isFirst || (activeAccount && account.id === activeAccount.id);
  const screenProps = { onAction, onReply, onOpenPost, onOpenProfile, onMention, onQuote, onRepost, onDirectRepost, onOpenMedia };

  // The home timeline renders from a `view` of posts interleaved with gap
  // markers; every other column renders a flat post list. Split the view into
  // contiguous post segments (each threaded on its own) divided by GapRows.
  const feedItems = view || posts;
  const feedPostCount = view ? view.filter(it => it && !it._gap).length : posts.length;
  const renderFeed = () => {
    if (!view) return <ThreadedList posts={posts} platform={account.platform} handlers={screenProps} />;
    const out = [];
    let seg = [];
    const flush = (k) => { if (seg.length) { out.push(<ThreadedList key={'seg' + k} posts={seg} platform={account.platform} handlers={screenProps} />); seg = []; } };
    view.forEach((it, i) => {
      if (it && it._gap) {
        flush(i);
        out.push(<GapRow key={it.id} gap={it} isX={isX} loading={!!(gapLoading && gapLoading[it.id])} onClick={() => onLoadGap && onLoadGap(col.id, it.id)} />);
      } else seg.push(it);
    });
    flush('end');
    return out;
  };

  const menuRow = (on) => ({ display: 'flex', alignItems: 'center', gap: 11, width: '100%', padding: '8px 10px', borderRadius: 9, border: 'none', background: on ? 'var(--gray-100)' : 'transparent', cursor: 'pointer', textAlign: 'left', color: 'var(--fg-body)', fontSize: 14, fontWeight: 600, fontFamily: 'var(--font-sans)' });
  const sectionLbl = { fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.06em', color: 'var(--fg-subdued)', padding: '8px 10px 4px' };

  return (
    <React.Fragment>
      <header style={{ height: 54, flex: 'none', display: 'flex', alignItems: 'center', gap: 6, padding: '0 8px', borderBottom: '1px solid var(--border-default)', background: 'color-mix(in srgb, var(--bg-base) 82%, transparent)', backdropFilter: 'blur(12px)', WebkitBackdropFilter: 'blur(12px)', position: 'relative', zIndex: (menu || reloadMenu) ? 6 : 'auto' }}>
        <span style={{ width: 34, flex: 'none', display: 'inline-flex', justifyContent: 'center' }}>
          {hideAvatar ? null : (
          <span style={{ position: 'relative', display: 'inline-flex', cursor: 'pointer' }} onClick={() => onOpenProfile && onOpenProfile(account)} title={isX ? account.name : account.name}>
            <PAvatar person={account} size={26} />
            <span style={{ position: 'absolute', right: -3, bottom: -3 }}><PlatformBadge platform={account.platform} size={12} /></span>
          </span>
          )}
        </span>

        <div style={{ flex: 1, minWidth: 0, display: 'flex', justifyContent: 'center' }}>
          <button onClick={() => setMenu(m => !m)} title={isX ? `${title} · ${account.name} · tap to switch` : `${title} · ${account.name} · 点击切换`}
            style={{ flex: '0 1 auto', maxWidth: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, height: 40, border: 'none', cursor: 'pointer', padding: '0 4px', background: 'transparent', fontFamily: 'var(--font-sans)' }}>
            <span style={{ display: 'inline-flex', width: 19, height: 19, color: 'var(--fg-heading)', flex: 'none' }}><Glyph name={meta.icon} size={19} /></span>
            <span style={{ fontSize: 16, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.015em', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 'none' }}>{title}</span>
            <span style={{ display: 'inline-flex', width: 14, height: 14, color: 'var(--fg-subdued)', flex: 'none', transform: menu ? 'rotate(180deg)' : 'none', transition: 'transform .15s' }}><Glyph name="chevron-down" size={14} /></span>
          </button>
        </div>

        <div style={{ width: 30, flex: 'none', display: 'inline-flex', justifyContent: 'center' }}>
          {window.DebugBus && DebugBus.inline() ? (
            <ColIconBtn name="code" size={17} title={isX ? 'Timeline JSON' : '时间线 JSON'}
              onClick={() => DebugBus.openJson(title + ' · ' + account.name, (view || posts), (account.platform === 'x' ? '@' + account.handle : account.name) + ' · ' + col.type + (col.feed ? '/' + col.feed : ''))} />
          ) : null}
        </div>

        <div style={{ width: 30, flex: 'none', display: 'inline-flex', justifyContent: 'center' }}>
          <RefreshControl isX={isX} refreshing={refreshing} newCount={newCount || 0} onClick={doRefresh} onMenuToggle={setReloadMenu}
            onHardReload={() => { scrollTop(); onHardReload && onHardReload(col.id); }}
            onEmptyReload={() => { scrollTop(); onEmptyReload && onEmptyReload(col.id); }} />
        </div>

        {menu && (
          <React.Fragment>
            <div onClick={() => setMenu(false)} style={{ position: 'fixed', inset: 0, zIndex: 40 }} />
            <div className="col-scroll" style={{ position: 'absolute', top: 50, left: '50%', transform: 'translateX(-50%)', width: 264, maxHeight: 'min(560px, 70vh)', overflowY: 'auto', background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', borderRadius: 14, boxShadow: 'var(--shadow-elevated)', padding: 6, zIndex: 41 }}>
              <div style={sectionLbl}>{isX ? 'Show' : '显示'}</div>
              {COL_TYPES.map(t => {
                const m = COL_META[t];
                const on = t === col.type;
                return (
                  <button key={t} onClick={() => { onType && onType(col.id, t); setMenu(false); }} style={menuRow(on)}
                    onMouseEnter={e => { if (!on) e.currentTarget.style.background = 'var(--gray-75)'; }} onMouseLeave={e => { if (!on) e.currentTarget.style.background = 'transparent'; }}>
                    <span style={{ display: 'inline-flex', width: 19, height: 19, color: 'var(--fg-subdued)', flex: 'none' }}><Glyph name={m.icon} size={19} /></span>
                    <span style={{ flex: 1, minWidth: 0 }}>{isX ? m.label_x : m.label_w}</span>
                    {on && <span style={{ display: 'inline-flex', width: 16, height: 16, color: 'var(--accent)', flex: 'none' }}><Glyph name="checkmark" size={16} /></span>}
                  </button>
                );
              })}

              {multiAccount && (
                <React.Fragment>
                  <div style={{ height: 1, background: 'var(--border-default)', margin: '6px 8px' }} />
                  <div style={sectionLbl}>{isX ? 'Account' : '账号'}</div>
                  {ACCOUNTS.map(a => {
                    const on = a.id === account.id;
                    return (
                      <button key={a.id} onClick={() => { onAccount && onAccount(col.id, a.id); setMenu(false); }} style={{ ...menuRow(on), gap: 10, padding: '7px 10px' }}
                        onMouseEnter={e => { if (!on) e.currentTarget.style.background = 'var(--gray-75)'; }} onMouseLeave={e => { if (!on) e.currentTarget.style.background = 'transparent'; }}>
                        <span style={{ position: 'relative', display: 'inline-flex', flex: 'none' }}>
                          <PAvatar person={a} size={28} />
                          <span style={{ position: 'absolute', right: -3, bottom: -3 }}><PlatformBadge platform={a.platform} size={13} /></span>
                          {u[a.id] > 0 && <span style={{ position: 'absolute', left: -6, top: -5 }}><NotifBadge count={u[a.id]} ring="var(--bg-elevated)" mini /></span>}
                        </span>
                        <span style={{ flex: 1, minWidth: 0 }}>
                          <span style={{ display: 'block', fontSize: 13.5, fontWeight: 700, color: 'var(--fg-heading)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{a.name}</span>
                          <span style={{ display: 'block', fontSize: 11.5, fontWeight: 500, color: 'var(--fg-subdued)' }}>{a.platform === 'x' ? '@' + a.handle + ' · X' : '微博'}</span>
                        </span>
                        {on && <span style={{ display: 'inline-flex', width: 16, height: 16, color: 'var(--accent)', flex: 'none' }}><Glyph name="checkmark" size={16} /></span>}
                      </button>
                    );
                  })}
                </React.Fragment>
              )}
            </div>
          </React.Fragment>
        )}
      </header>

      {refreshing && <RefreshBar />}

      {col.type === 'home' && <FeedTabs feeds={(HOME_FEEDS[account.platform] || HOME_FEEDS.x)} value={col.feed} onChange={(f) => { onFeed && onFeed(col.id, f); scrollTop(); }} />}

      {st === 'loading' ? (
        <div className="col-scroll" style={{ flex: 1, overflowY: 'auto', overflowX: 'hidden' }}>
          {col.type === 'mentions' ? <NotifSkeleton isX={isX} /> : <TimelineSkeleton isX={isX} />}
        </div>
      ) : st === 'error' ? (
        <div className="col-scroll" style={{ flex: 1, overflowY: 'auto', overflowX: 'hidden' }}>
          <TimelineError isX={isX} retrying={refreshing} onRetry={() => onRetry && onRetry(col.id)} />
        </div>
      ) : (
      <div style={{ flex: 1, minHeight: 0, position: 'relative', display: 'flex', flexDirection: 'column' }}>
        {reloadError && <ReloadErrorStrip isX={isX} retrying={!!softReloading} onRetry={() => onRetryReload && onRetryReload(col.id)} onDismiss={() => onDismissReloadError && onDismissReloadError(col.id)} />}
        {softReloading && !reloadError && <SoftReloadPill isX={isX} />}
        {col.type === 'bookmarks' ? (
          <BookmarksView account={account} isX={isX} posts={posts} folders={folders} bmFolder={bmFolder}
            onAddFolder={onAddFolder} onUpdateFolder={onUpdateFolder} onDeleteFolder={onDeleteFolder} onSetFolder={onSetFolder}
            handlers={screenProps} tweaks={bmTweaks} />
        ) : col.type === 'mentions' ? (
          <NotifList account={account} bodyRef={bodyRef} onOpenPost={onOpenPost} onOpenProfile={onOpenProfile} onReply={onReply} />
        ) : (
        <div style={{ flex: 1, minHeight: 0, position: 'relative', display: 'flex', flexDirection: 'column' }}>
          {newCount > 0 && (col.type === 'home'
            ? <NewPostsPill isX={isX} count={newCount} avatars={newAuthors} onClick={loadNew} />
            : <NewPostsBanner isX={isX} count={newCount} onClick={loadNew} />)}
          <div ref={bodyRef} className="col-scroll" style={{ flex: 1, overflowY: 'auto', overflowX: 'hidden' }} onScroll={(e) => onScroll && onScroll(col.id, e.currentTarget.scrollTop)}>
            {col.type === 'search' && <SearchHeader isX={isX} />}
            {(st === 'empty' || feedPostCount === 0) ? (
              <TimelineEmpty isX={isX} type={col.type} />
            ) : (
              renderFeed()
            )}
            <div style={{ height: 24 }} />
          </div>
        </div>
        )}
      </div>
      )}
    </React.Fragment>
  );
}

function Column(props) {
  const { col, account, posts, view, isLast, isFirst, subStack, onPushScreen, onPopScreen,
    onAction, onReply, onQuote, onRepost, onDirectRepost, onType, onAccount, onFeed, unread,
    resolvePost, repliesOf, authorPosts, activeAccount, onOpenMedia, gapLoading, onLoadGap,
    status, refreshing, newCount, newAuthors, onRefresh, onRetry, onScroll, softReloading, reloadError, onRetryReload, onDismissReloadError,
    onHardReload, onEmptyReload,
    folders, bmFolder, onAddFolder, onUpdateFolder, onDeleteFolder, onSetFolder, bmTweaks } = props;

  // local slide animation driven by the externally-owned stack length
  const stackLen = subStack.length;
  const [screens, setScreens] = React.useState(subStack);
  const [idx, setIdx] = React.useState(stackLen);
  React.useEffect(() => {
    if (stackLen > screens.length) {            // push: mount, then slide forward
      setScreens(subStack);
      const t = setTimeout(() => setIdx(stackLen), 24);
      return () => clearTimeout(t);
    } else if (stackLen < screens.length) {     // pop: slide back, then unmount
      setIdx(stackLen);
      const t = setTimeout(() => setScreens(subStack), 380);
      return () => clearTimeout(t);
    } else {
      setScreens(subStack); setIdx(stackLen);
    }
  }, [stackLen]); // eslint-disable-line

  const pushPost = (post) => onPushScreen({ kind: 'post', id: post.id });
  const pushProfile = (person) => onPushScreen({ kind: 'profile', person });
  const pushMention = (h) => { const p = personByHandle(h); if (p) pushProfile(p); };
  const shared = { onAction, onReply, onQuote, onRepost, onDirectRepost, onOpenPost: pushPost, onOpenProfile: pushProfile, onMention: pushMention, onOpenMedia };

  const meta = COL_META[col.type] || COL_META.home;
  const baseTitle = (account.platform === 'x') ? meta.label_x : meta.label_w;
  const n = screens.length + 1;                 // number of stacked screens (timeline + pushed)
  const screenPct = 100 / n;                     // each screen's share of the track

  return (
    <section data-screen-label={'Column: ' + baseTitle}
      style={{ flex: '1 1 0', minWidth: 0, height: '100%', borderRight: isLast ? 'none' : '1px solid var(--border-default)', background: 'var(--bg-base)', position: 'relative', overflow: 'hidden' }}>
      <div style={{ display: 'flex', height: '100%', width: `${n * 100}%`, transform: `translateX(${-idx * screenPct}%)`, transition: 'transform .36s var(--ease-default)' }}>
        {/* screen 0 — timeline */}
        <div style={{ flex: `0 0 ${screenPct}%`, minWidth: 0, height: '100%', display: 'flex', flexDirection: 'column' }}>
          <TimelineScreen col={col} account={account} posts={posts} view={view} isFirst={isFirst} activeAccount={activeAccount} onType={onType} onAccount={onAccount} onFeed={onFeed} unread={unread}
            status={status} refreshing={refreshing} newCount={newCount} newAuthors={newAuthors} onRefresh={onRefresh} onRetry={onRetry} onScroll={onScroll} onHardReload={onHardReload} onEmptyReload={onEmptyReload} gapLoading={gapLoading} onLoadGap={onLoadGap}
            softReloading={softReloading} reloadError={reloadError} onRetryReload={onRetryReload} onDismissReloadError={onDismissReloadError}
            folders={folders} bmFolder={bmFolder} onAddFolder={onAddFolder} onUpdateFolder={onUpdateFolder} onDeleteFolder={onDeleteFolder} onSetFolder={onSetFolder} bmTweaks={bmTweaks} {...shared} />
        </div>

        {/* pushed screens */}
        {screens.map((s) => {
          let bodyEl = null;
          const setBody = (el) => { bodyEl = el; };
          const doRefresh = () => { if (bodyEl) bodyEl.scrollTo({ top: 0, behavior: 'smooth' }); };
          return (
          <div key={s.key} data-screen-label={(s.kind === 'post' ? 'Detail' : 'Profile')}
            style={{ flex: `0 0 ${screenPct}%`, minWidth: 0, height: '100%', display: 'flex', flexDirection: 'column', borderLeft: '1px solid var(--border-default)', background: 'var(--bg-base)' }}>
            <BackHeader title={NavTitle(s, resolvePost)} onBack={onPopScreen} onRefresh={doRefresh} isX={account.platform === 'x'} />
            <div ref={setBody} className="col-scroll" style={{ flex: 1, overflowY: 'auto', overflowX: 'hidden' }}>
              {s.kind === 'post' ? (
                <DetailScreen post={resolvePost(s.id)} repliesOf={repliesOf}
                  onOpenPost={pushPost} onOpenProfile={pushProfile} onMention={pushMention}
                  onAction={onAction} onReply={onReply} onQuote={onQuote} onRepost={onRepost} onDirectRepost={onDirectRepost} onOpenMedia={onOpenMedia} />
              ) : (
                <ProfileScreen person={s.person} isOwn={!!(s.person.id && activeAccount && s.person.id === activeAccount.id)}
                  profileFor={profileFor} authorPosts={authorPosts} {...shared} />
              )}
            </div>
          </div>
          );
        })}
      </div>
    </section>
  );
}

/* Feed filter strip for the Home column: For you · Following (·热门 on Weibo).
   Shares the notification column's compact pill-tab vocabulary — an icon per
   feed, with the selected tab expanding to reveal its label — so the two
   columns feel like one system. */
const FEED_ICON = { foryou: 'sparkle', following: 'user', hot: 'flame' };
function FeedTabs({ feeds, value, onChange }) {
  const cur = value || (feeds[0] && feeds[0].id);
  return (
    <div style={{ flex: 'none', padding: '8px 12px', borderBottom: '1px solid var(--border-default)', background: 'var(--bg-base)', position: 'relative', zIndex: 1 }}>
      <div role="tablist" style={{ display: 'flex', gap: 3, padding: 3, borderRadius: 9999, background: 'var(--gray-100)' }}>
        {feeds.map(f => (
          <FeedSeg key={f.id} icon={FEED_ICON[f.id] || 'home'} label={f.label} selected={f.id === cur} onClick={() => onChange(f.id)} />
        ))}
      </div>
    </div>
  );
}

function FeedSeg({ icon, label, selected, onClick }) {
  const [h, setH] = React.useState(false);
  return (
    <button role="tab" aria-selected={selected} onClick={onClick} title={label} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ position: 'relative', height: 32, minWidth: 36, padding: selected ? '0 14px' : 0, flex: '0 0 auto', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', borderRadius: 9999, border: 'none', cursor: 'pointer', whiteSpace: 'nowrap', fontFamily: 'var(--font-sans)', fontSize: 13.5, fontWeight: 700, letterSpacing: '-.005em',
        background: selected ? 'var(--bg-elevated)' : (h ? 'color-mix(in srgb, var(--gray-400) 38%, transparent)' : 'transparent'),
        color: selected ? 'var(--fg-heading)' : 'var(--fg-subdued)',
        boxShadow: selected ? 'var(--shadow-emphasized)' : 'none',
        transition: 'background .18s var(--ease-default), color .18s, box-shadow .18s, padding .3s var(--ease-default)' }}>
      <span style={{ display: 'inline-flex', width: 16, height: 16, flex: 'none', transform: selected ? 'scale(1)' : 'scale(.96)', transition: 'transform .3s var(--ease-default)' }}><Glyph name={icon} size={16} /></span>
      <span style={{ display: 'inline-block', overflow: 'hidden', whiteSpace: 'nowrap', maxWidth: selected ? 120 : 0, opacity: selected ? 1 : 0, marginInlineStart: selected ? 7 : 0,
        transition: selected
          ? 'max-width .3s var(--ease-default), opacity .22s var(--ease-default) .13s, margin .3s var(--ease-default)'
          : 'max-width .26s var(--ease-default) .04s, opacity .11s var(--ease-default), margin .26s var(--ease-default) .04s' }}>{label}</span>
    </button>
  );
}

function SearchHeader({ isX }) {
  const trends = isX
    ? [['Trending in Design', '#DesignSystems', '12.4K posts'], ['Technology', 'Native Mac apps', '8,902 posts'], ['Trending', '#Spectrum2', '3,201 posts']]
    : [['热搜', '原生桌面客户端', '阅读 1,204万'], ['设计', '深色模式怎么调', '阅读 642万'], ['摄影', '#胶片日记#', '讨论 8.1万']];
  return (
    <div>
      <div style={{ padding: '12px 16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 38, padding: '0 12px', borderRadius: 9999, background: 'var(--bg-layer-1)', border: '1px solid var(--border-default)' }}>
          <span style={{ display: 'inline-flex', width: 18, height: 18, color: 'var(--fg-subdued)' }}><Glyph name="search" size={18} /></span>
          <input placeholder={isX ? 'Search posts and people' : '搜索微博和用户'} style={{ flex: 1, border: 'none', background: 'none', outline: 'none', fontSize: 14, fontFamily: 'var(--font-sans)', color: 'var(--fg-body)' }} />
        </div>
      </div>
      <div style={{ padding: '4px 0 8px' }}>
        {trends.map((t, i) => (
          <div key={i} style={{ padding: '8px 16px', cursor: 'pointer' }}>
            <div style={{ fontSize: 12, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>{t[0]}</div>
            <div style={{ fontSize: 15, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)' }}>{t[1]}</div>
            <div style={{ fontSize: 12, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>{t[2]}</div>
          </div>
        ))}
        <div style={{ height: 1, background: 'var(--border-default)', margin: '4px 0' }} />
      </div>
    </div>
  );
}

Object.assign(window, { Column, COLUMN_W, COLUMN_MIN, COLUMN_MAX });

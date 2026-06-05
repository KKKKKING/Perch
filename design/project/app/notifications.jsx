/* Notification center for the bell column. Six message kinds:
   like · repost · follow are aggregated into a single row with an avatar
   stack + count; reply · mention · quote render as full engagement cards.
   Segmented sub-tabs (All · @ · Replies · Likes · Reposts · Follows) filter
   the feed. Quotes are filed under @mentions. Built from Perch's own atoms
   (PAvatar, Verified, RichText, QuotePost, ACT_ICONS). */

/* ── kind metadata: leading icon + accent + verb per platform ── */
const NOTIF_KIND = {
  like:    { color: 'var(--magenta-800)', act: 'heart',  verb_x: 'liked your post',      verb_w: '赞了你的微博' },
  repost:  { color: 'var(--green-700)',   act: 'repost', verb_x: 'reposted your post',   verb_w: '转发了你的微博' },
  follow:  { color: 'var(--accent)',      glyph: 'user', verb_x: 'followed you',         verb_w: '关注了你' },
  reply:   { color: 'var(--accent)',      act: 'reply',  ctx_x: 'replied to you',        ctx_w: '回复了你' },
  mention: { color: 'var(--accent)',      char: '@',     ctx_x: 'mentioned you',         ctx_w: '提到了你' },
  quote:   { color: 'var(--purple-700)',  act: 'repost', ctx_x: 'quoted your post',      ctx_w: '引用了你的微博' },
};

// Weibo keeps the full six-way breakdown.
const NOTIF_FILTERS_W = [
  { id: 'all',     glyph: 'bell', label_x: 'All',     label_w: '全部' },
  { id: 'mention', char: '@',     label_x: 'Mentions', label_w: '@我的' },
  { id: 'reply',   act: 'reply',  label_x: 'Replies', label_w: '评论' },
  { id: 'like',    act: 'heart',  label_x: 'Likes',   label_w: '赞' },
  { id: 'repost',  act: 'repost', label_x: 'Reposts', label_w: '转发' },
  { id: 'follow',  glyph: 'user', label_x: 'Follows', label_w: '粉丝' },
];

// X mirrors the real product: just All · Verified · Mentions.
const NOTIF_FILTERS_X = [
  { id: 'all',      glyph: 'bell',             label_x: 'All',      label_w: '全部' },
  { id: 'verified', glyph: 'checkmark-circle', label_x: 'Verified', label_w: '认证' },
  { id: 'mention',  char: '@',                 label_x: 'Mentions', label_w: '@我的' },
];

const filtersFor = (platform) => (platform === 'x' ? NOTIF_FILTERS_X : NOTIF_FILTERS_W);

// which filter a kind belongs to (quotes live under mentions)
const kindFilter = (kind) => (kind === 'quote' ? 'mention' : kind);
// actors involved in a notification (for the Verified filter)
const notifActors = (n) => n.actors || (n.actor ? [n.actor] : (n.post && n.post.author ? [n.post.author] : []));
const filterMatch = (filter, n) => {
  if (filter === 'all') return true;
  if (filter === 'verified') return notifActors(n).some(a => a && a.verified);
  return kindFilter(n.kind) === filter;
};

/* a kind/filter icon — Glyph, action-svg, or a literal @ */
function KindIcon({ meta, size = 17, color }) {
  if (meta.char) return <span style={{ fontSize: size + 1, fontWeight: 800, lineHeight: 1, color: color || 'currentColor', fontFamily: 'var(--font-sans)' }}>{meta.char}</span>;
  if (meta.act) return <SvgIcon size={size} color={color}>{ACT_ICONS[meta.act]}</SvgIcon>;
  return <span style={{ display: 'inline-flex', width: size, height: size, color: color || 'currentColor' }}><Glyph name={meta.glyph} size={size} /></span>;
}

/* overlapping avatar row for aggregated rows */
function AvatarStack({ people, size = 30, max = 8, ring = 'var(--bg-base)' }) {
  const shown = people.slice(0, max);
  return (
    <div style={{ display: 'flex', alignItems: 'center' }}>
      {shown.map((p, i) => (
        <span key={i} style={{ marginInlineStart: i ? -8 : 0, borderRadius: '50%', boxShadow: `0 0 0 2px ${ring}`, position: 'relative', zIndex: shown.length - i }}>
          <PAvatar person={p} size={size} />
        </span>
      ))}
    </div>
  );
}

/* small media thumbnail (image gradient or video chip) */
function NotifThumb({ slide, size = 46 }) {
  if (!slide) return null;
  return (
    <div style={{ width: size, height: size, borderRadius: 10, flex: 'none', overflow: 'hidden', position: 'relative', border: '1px solid var(--border-default)' }}>
      <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(135deg, ${slide.grad[0]}, ${slide.grad[1]})` }} />
      {slide.kind === 'video' && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}>
          <span style={{ display: 'inline-flex', width: 16, height: 16, marginInlineStart: 1, filter: 'drop-shadow(0 1px 2px rgba(0,0,0,.5))' }}><Glyph name="play" size={16} /></span>
        </div>
      )}
    </div>
  );
}

/* compact "your post they engaged with" reference block (reply rows) */
function RefPost({ post, isX }) {
  if (!post) return null;
  const slide = post.media ? mediaSlides(post.media)[0] : null;
  return (
    <div style={{ marginTop: 9, display: 'flex', gap: 10, padding: '9px 11px', borderRadius: 12, background: 'var(--bg-layer-1)', border: '1px solid var(--border-default)' }}>
      {slide && <NotifThumb slide={slide} size={42} />}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 12.5, fontWeight: 600, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', marginBottom: 2 }}>
          {isX ? '@' + post.author.handle : post.author.name}<span style={{ fontWeight: 500 }}>{isX ? ' · your post' : ' · 你的微博'}</span>
        </div>
        <div style={{ fontSize: 13.5, lineHeight: 1.45, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{post.text}</div>
      </div>
    </div>
  );
}

/* a lightweight pill button used for Follow-back / Reply / Like on rows */
function RowButton({ label, icon, act, color = 'var(--fg-subdued)', filled, active, onClick }) {
  const [h, setH] = React.useState(false);
  const c = filled ? '#fff' : (active || h ? color : 'var(--fg-subdued)');
  return (
    <button onClick={(e) => { e.stopPropagation(); onClick && onClick(); }} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 30, padding: icon && !label ? 0 : '0 13px', width: icon && !label ? 30 : 'auto', justifyContent: 'center', borderRadius: 9999, cursor: 'pointer', whiteSpace: 'nowrap', fontFamily: 'var(--font-sans)', fontSize: 13, fontWeight: 700, transition: 'background .12s, color .12s, border-color .12s',
        background: filled ? (h ? 'var(--accent-bg-hover)' : 'var(--accent-bg)') : (h ? 'color-mix(in srgb, currentColor 10%, transparent)' : 'transparent'),
        border: filled ? 'none' : '1px solid var(--border-strong)', color: c }}>
      {icon && <SvgIcon size={16} color={c}>{ACT_ICONS[icon]}</SvgIcon>}
      {act && <span style={{ display: 'inline-flex', width: 16, height: 16, color: c }}><Glyph name={act} size={16} /></span>}
      {label && <span>{label}</span>}
    </button>
  );
}

/* ── aggregated row: like / repost / follow ── */
function NotifAggRow({ n, isX, unread, onOpenPost, onOpenProfile, onSeen }) {
  const [hover, setHover] = React.useState(false);
  const [followed, setFollowed] = React.useState(false);
  const meta = NOTIF_KIND[n.kind];
  const actors = n.actors || (n.actor ? [n.actor] : []);
  const count = n.count || actors.length;
  const lead = actors[0];
  const others = count - 1;
  const verb = isX ? meta.verb_x : meta.verb_w;
  const slide = n.post && n.post.media ? mediaSlides(n.post.media)[0] : null;
  const isFollow = n.kind === 'follow';
  const clickable = !isFollow || n.single;

  const open = () => {
    onSeen && onSeen(n.id);
    if (isFollow) { if (n.single) onOpenProfile && onOpenProfile(lead); }
    else if (n.post && onOpenPost) onOpenPost(n.post);
  };

  const line = isX
    ? <span><b style={{ fontWeight: 700, color: 'var(--fg-heading)' }}>{lead.name}</b>{others > 0 ? ` and ${others} other${others > 1 ? 's' : ''}` : ''} {verb}</span>
    : <span><b style={{ fontWeight: 700, color: 'var(--fg-heading)' }}>{lead.name}</b>{others > 0 ? ` 和另外 ${others} 个人` : ''}{verb}</span>;

  return (
    <article onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)} onClick={clickable ? open : (onSeen ? () => onSeen(n.id) : undefined)}
      style={{ position: 'relative', display: 'flex', gap: 12, padding: '13px 16px 13px 14px', borderBottom: '1px solid var(--border-default)', cursor: clickable ? 'pointer' : 'default', transition: 'background .12s',
        background: hover ? 'var(--bg-layer-1)' : (unread ? 'color-mix(in srgb, var(--accent) 7%, var(--bg-base))' : 'transparent') }}>
      {unread && <span style={{ position: 'absolute', left: 5, top: 19, width: 6, height: 6, borderRadius: '50%', background: 'var(--accent)' }} />}
      <span style={{ width: 22, flex: 'none', display: 'inline-flex', justifyContent: 'center', paddingTop: 3 }}><KindIcon meta={meta} size={20} color={meta.color} /></span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ marginBottom: 8 }}>
          <AvatarStack people={actors} ring={unread ? 'color-mix(in srgb, var(--accent) 7%, var(--bg-base))' : 'var(--bg-base)'} />
        </div>
        <div style={{ fontSize: 14.5, lineHeight: 1.4, color: 'var(--fg-body)', fontFamily: 'var(--font-sans)' }}>
          {line}<span style={{ color: 'var(--fg-subdued)' }}> · {n.time}</span>
        </div>
        {!isFollow && n.post && (
          <div style={{ marginTop: 3, fontSize: 14, lineHeight: 1.4, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{n.post.text}</div>
        )}
        {isFollow && n.single && n.bio && (
          <div style={{ marginTop: 3, fontSize: 14, lineHeight: 1.4, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{n.bio}</div>
        )}
      </div>
      {!isFollow && slide && <NotifThumb slide={slide} size={46} />}
      {isFollow && n.single && (
        <div style={{ flex: 'none', display: 'flex', alignItems: 'center' }}>
          <RowButton label={followed ? (isX ? 'Following' : '已关注') : (isX ? 'Follow back' : '回关')} filled={!followed} color="var(--accent)" active={followed} onClick={() => setFollowed(f => !f)} />
        </div>
      )}
    </article>
  );
}

/* ── engagement card: reply / mention / quote ── */
function NotifEngageRow({ n, isX, unread, onOpenPost, onOpenProfile, onReply, onSeen }) {
  const [hover, setHover] = React.useState(false);
  const [liked, setLiked] = React.useState(false);
  const meta = NOTIF_KIND[n.kind];
  const src = n.post;                                   // the post that carries the engagement
  const actor = n.kind === 'reply' ? n.actor : (src ? src.author : n.actor);
  const ctx = isX ? meta.ctx_x : meta.ctx_w;
  const text = n.kind === 'reply' ? n.text : (src ? src.text : n.text);
  const open = () => { onSeen && onSeen(n.id); if (src && onOpenPost) onOpenPost(src); };
  const openProfile = (e) => { e.stopPropagation(); onSeen && onSeen(n.id); onOpenProfile && onOpenProfile(actor); };

  return (
    <article onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)} onClick={open}
      style={{ position: 'relative', display: 'flex', gap: 11, padding: '13px 16px 11px 14px', borderBottom: '1px solid var(--border-default)', cursor: 'pointer', transition: 'background .12s',
        background: hover ? 'var(--bg-layer-1)' : (unread ? 'color-mix(in srgb, var(--accent) 7%, var(--bg-base))' : 'transparent') }}>
      {unread && <span style={{ position: 'absolute', left: 5, top: 19, width: 6, height: 6, borderRadius: '50%', background: 'var(--accent)' }} />}
      <span onClick={openProfile} style={{ flex: 'none', cursor: 'pointer', position: 'relative' }}>
        <PAvatar person={actor} size={40} />
        <span style={{ position: 'absolute', right: -3, bottom: -3, width: 19, height: 19, borderRadius: '50%', background: 'var(--bg-base)', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 0 0 2px var(--bg-base)' }}>
          <KindIcon meta={meta} size={13} color={meta.color} />
        </span>
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span onClick={openProfile} style={{ fontSize: 15, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', whiteSpace: 'nowrap', cursor: 'pointer', flex: 'none' }}>{actor.name}</span>
          {actor.verified && <Verified size={14} />}
          {isX && <span style={{ fontSize: 13.5, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', minWidth: 0 }}>@{actor.handle}</span>}
          <span style={{ fontSize: 13.5, color: 'var(--fg-subdued)', whiteSpace: 'nowrap', flex: 'none' }}>· {n.time}</span>
        </div>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 5, marginTop: 1, color: 'var(--fg-subdued)', fontSize: 12.5, fontWeight: 600, fontFamily: 'var(--font-sans)', whiteSpace: 'nowrap' }}>
          <KindIcon meta={meta} size={13} color="var(--fg-subdued)" />{ctx}
        </div>
        <div style={{ marginTop: 4, fontSize: 15, lineHeight: 1.46, color: 'var(--fg-body)', fontFamily: 'var(--font-sans)', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
          <RichText text={text} onMention={() => {}} />
        </div>
        {n.kind === 'reply' && <RefPost post={src} isX={isX} />}
        {n.kind === 'mention' && src && src.media && (src.media.type === 'images' || src.media.type === 'gallery') && <MediaImages items={src.media.items} />}
        {n.kind === 'quote' && src && src.quote && <QuotePost q={src.quote} />}
        <div style={{ display: 'flex', gap: 8, marginTop: 11 }}>
          <RowButton label={isX ? 'Reply' : '回复'} icon="reply" color="var(--accent)" onClick={() => { onSeen && onSeen(n.id); onReply && onReply(src); }} />
          <RowButton icon="heart" color="var(--magenta-800)" active={liked} onClick={() => setLiked(l => !l)} />
        </div>
      </div>
    </article>
  );
}

/* ── segmented sub-tab strip (selected tab expands to show its label) ── */
function NotifSeg({ f, isX, selected, unread, onClick }) {
  const [h, setH] = React.useState(false);
  const label = isX ? f.label_x : f.label_w;
  return (
    <button role="tab" aria-selected={selected} onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)} title={label}
      style={{ position: 'relative', height: 32, minWidth: 36, padding: selected ? '0 14px' : 0, flex: '0 0 auto', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', borderRadius: 9999, border: 'none', cursor: 'pointer', whiteSpace: 'nowrap', fontFamily: 'var(--font-sans)', fontSize: 13, fontWeight: 700,
        background: selected ? 'var(--bg-elevated)' : (h ? 'color-mix(in srgb, var(--gray-400) 38%, transparent)' : 'transparent'),
        color: selected ? 'var(--fg-heading)' : 'var(--fg-subdued)', boxShadow: selected ? 'var(--shadow-emphasized)' : 'none',
        transition: 'background .18s var(--ease-default), color .18s, box-shadow .18s, padding .3s var(--ease-default)' }}>
      <span style={{ display: 'inline-flex', flex: 'none', transform: selected ? 'scale(1)' : 'scale(.96)', transition: 'transform .3s var(--ease-default)' }}><KindIcon meta={f} size={15} color={selected ? 'var(--fg-heading)' : 'currentColor'} /></span>
      <span style={{ display: 'inline-block', overflow: 'hidden', whiteSpace: 'nowrap', maxWidth: selected ? 120 : 0, opacity: selected ? 1 : 0, marginInlineStart: selected ? 6 : 0,
        transition: selected
          ? 'max-width .3s var(--ease-default), opacity .22s var(--ease-default) .13s, margin .3s var(--ease-default)'
          : 'max-width .26s var(--ease-default) .04s, opacity .11s var(--ease-default), margin .26s var(--ease-default) .04s' }}>{label}</span>
      {!selected && unread && <span style={{ position: 'absolute', top: 5, right: 5, width: 6, height: 6, borderRadius: '50%', background: 'var(--accent)', boxShadow: '0 0 0 1.5px var(--gray-100)' }} />}
    </button>
  );
}

function NotifTabs({ platform, filters, value, onChange, unreadFilters }) {
  const isX = platform === 'x';
  return (
    <div style={{ flex: 'none', padding: '8px 12px', borderBottom: '1px solid var(--border-default)', background: 'var(--bg-base)', position: 'relative', zIndex: 1 }}>
      <div role="tablist" style={{ display: 'flex', gap: 3, padding: 3, borderRadius: 9999, background: 'var(--gray-100)' }}>
        {filters.map(f => (
          <NotifSeg key={f.id} f={f} isX={isX} selected={value === f.id} unread={unreadFilters.has(f.id)} onClick={() => onChange(f.id)} />
        ))}
      </div>
    </div>
  );
}

/* ── feed: owns filter + read state, renders the rows ── */
function NotifList({ account, bodyRef, onOpenPost, onOpenProfile, onReply }) {
  const isX = account.platform === 'x';
  const filters = filtersFor(account.platform);
  const all = React.useMemo(() => notificationsFor(account.platform), [account.platform]);
  const [filter, setFilter] = React.useState('all');
  const [read, setRead] = React.useState(() => new Set());
  React.useEffect(() => { setRead(new Set()); setFilter('all'); }, [account.platform]);

  const isUnread = (n) => n.unread && !read.has(n.id);
  const seen = (id) => setRead(s => { if (s.has(id)) return s; const c = new Set(s); c.add(id); return c; });

  // Entering the notifications view auto-marks everything read — no manual
  // "mark all" needed. The unread tint + per-tab dots show briefly so you can
  // spot what's new, then settle on their own a beat after you've landed.
  React.useEffect(() => {
    const t = setTimeout(() => setRead(new Set(all.map(n => n.id))), 1300);
    return () => clearTimeout(t);
  }, [account.platform, all]);

  const unreadFilters = React.useMemo(() => {
    const s = new Set();
    all.forEach(n => { if (isUnread(n)) { filters.forEach(f => { if (filterMatch(f.id, n)) s.add(f.id); }); } });
    return s;
  }, [all, read]);

  const rows = all.filter(n => filterMatch(filter, n));

  return (
    <React.Fragment>
      <NotifTabs platform={account.platform} filters={filters} value={filter} onChange={setFilter} unreadFilters={unreadFilters} />
      <div ref={bodyRef} className="col-scroll" style={{ flex: 1, overflowY: 'auto', overflowX: 'hidden' }}>
        {rows.length === 0 ? (
          <div style={{ padding: '64px 28px', textAlign: 'center' }}>
            <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', marginBottom: 6 }}>{isX ? 'Nothing here yet' : '这里还什么都没有'}</div>
            <div style={{ fontSize: 14, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>{isX ? 'New activity will show up here.' : '新的互动会显示在这里。'}</div>
          </div>
        ) : rows.map(n => (
          (n.kind === 'like' || n.kind === 'repost' || n.kind === 'follow')
            ? <NotifAggRow key={n.id} n={n} isX={isX} unread={isUnread(n)} onOpenPost={onOpenPost} onOpenProfile={onOpenProfile} onSeen={seen} />
            : <NotifEngageRow key={n.id} n={n} isX={isX} unread={isUnread(n)} onOpenPost={onOpenPost} onOpenProfile={onOpenProfile} onReply={onReply} onSeen={seen} />
        ))}
        <div style={{ height: 24 }} />
      </div>
    </React.Fragment>
  );
}

Object.assign(window, { NotifList });

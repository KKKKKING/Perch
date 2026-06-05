/* Post + media sub-components. Loaded as Babel JSX. */

function fmt(n) {
  if (typeof n !== 'number') return n;
  if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
  if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'K';
  return String(n);
}

// inline-player time helpers (media.jsx has its own copies in a separate scope)
function vParseDur(s) {
  if (!s) return 30;
  const m = String(s).split(':').map(n => parseInt(n, 10) || 0);
  return m.length === 2 ? m[0] * 60 + m[1] : m[0];
}
function vFmtTime(sec) {
  sec = Math.max(0, Math.round(sec));
  const m = Math.floor(sec / 60), s = sec % 60;
  return m + ':' + String(s).padStart(2, '0');
}

function PAvatar({ person, size = 40 }) {
  const initials = (person.name || '?').replace(/\s+/g, ' ').trim().split(' ').map(w => w[0]).slice(0, 2).join('');
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%', flex: 'none',
      background: person.color, color: '#fff',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontSize: size * 0.42, fontWeight: 700, fontFamily: 'var(--font-sans)',
      boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.18), inset 0 -6px 14px rgba(0,0,0,.18)',
      userSelect: 'none', letterSpacing: '-.02em',
    }}>{initials}</div>
  );
}

function Verified({ size = 15 }) {
  return (
    <span title="Verified" style={{ display: 'inline-flex', width: size, height: size, color: 'var(--accent)', flex: 'none' }}>
      <svg viewBox="0 0 22 22" width="100%" height="100%" style={{ display: 'block' }}>
        <path fill="currentColor" d="M11 1.5l2.2 1.9 2.9-.3 1.2 2.7 2.6 1.3-.3 2.9 1.9 2.2-1.9 2.2.3 2.9-2.6 1.3-1.2 2.7-2.9-.3L11 20.5l-2.2-1.9-2.9.3-1.2-2.7-2.6-1.3.3-2.9L.5 11l1.9-2.2-.3-2.9 2.6-1.3 1.2-2.7 2.9.3L11 1.5z"/>
        <path d="M7.3 11.1l2.5 2.5 4.9-5.2" stroke="#fff" strokeWidth="1.7" fill="none" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    </span>
  );
}

// Literal-JSX icons for the action bar — this exact pattern (explicit-color
// wrapper + literal <path>) renders AND screen-captures reliably.
function SvgIcon({ size = 18, color, children }) {
  return (
    <span style={{ display: 'inline-flex', width: size, height: size, color: color || 'currentColor', flex: 'none' }}>
      <svg width="100%" height="100%" viewBox="0 0 20 20" style={{ display: 'block' }}>{children}</svg>
    </span>
  );
}
const ACT_ICONS = {
  reply: <path fill="currentColor" d="M4.6 3.5H15.4A2.1 2.1 0 0 1 17.5 5.6V12A2.1 2.1 0 0 1 15.4 14.1H9L5.6 17V14.1H4.6A2.1 2.1 0 0 1 2.5 12V5.6A2.1 2.1 0 0 1 4.6 3.5Z" />,
  repost: <g fill="currentColor"><path d="M5.83 5.83h8.34v2.5l3.33-3.33-3.33-3.34v2.5H4.17v5h1.66V5.83Z" /><path d="M14.17 14.17H5.83v-2.5L2.5 15l3.33 3.33v-2.5h9.84v-5h-1.5v3.34Z" /></g>,
  heart: <path fill="currentColor" d="M10 17.3c-.3 0-.6-.1-.83-.32C4.6 12.85 2.2 10.1 2.2 7.2 2.2 4.85 4.05 3 6.4 3c1.5 0 2.85.78 3.6 1.96C10.75 3.78 12.1 3 13.6 3 15.95 3 17.8 4.85 17.8 7.2c0 2.9-2.4 5.65-6.97 9.78-.23.22-.53.32-.83.32Z" />,
  bookmark: <path fill="currentColor" d="M6 2.8h8a1.6 1.6 0 0 1 1.6 1.6v12.9a.6.6 0 0 1-.93.5L10 14.6l-4.67 3.2A.6.6 0 0 1 4.4 17.3V4.4A1.6 1.6 0 0 1 6 2.8Z" />,
  share: <g fill="currentColor"><path d="M10 2.4 6 6.4l1.4 1.4L9 6.2v6.2a1 1 0 0 0 2 0V6.2l1.6 1.6L14 6.4 10 2.4Z" /><path d="M4.4 10.2a1 1 0 0 1 2 0v5.3h7.2v-5.3a1 1 0 0 1 2 0V16a1.5 1.5 0 0 1-1.5 1.5H5.9A1.5 1.5 0 0 1 4.4 16Z" /></g>,
  pin: <path fill="currentColor" d="M8.7 2.6h2.6l-.55 4.5 3 2.55-2.5.72-1.25 4.7-1.25-4.7-2.5-.72 3-2.55L8.7 2.6Z" />,
};

// rich-text: color @mentions, #/＃hashtags, links — @mentions are clickable
function RichText({ text, onMention }) {
  const parts = text.split(/(\s+)/);
  return (
    <span>
      {parts.map((tok, i) => {
        if (/^@/.test(tok) && tok.length > 1) {
          const handle = tok.replace(/^@/, '').replace(/[，,。.!！?？:：;；、)）]+$/, '');
          return (
            <span key={i} onClick={onMention ? (e) => { e.stopPropagation(); onMention(handle); } : undefined}
              style={{ color: 'var(--accent)', cursor: onMention ? 'pointer' : 'inherit' }}>{tok}</span>
          );
        }
        if (/^[#＃]/.test(tok) || /^https?:\/\//.test(tok) || /链接$/.test(tok)) {
          return <span key={i} style={{ color: 'var(--accent)' }}>{tok}</span>;
        }
        return <React.Fragment key={i}>{tok}</React.Fragment>;
      })}
    </span>
  );
}

/* A small badge used over media: muted-speaker + duration, or a play chip. */
function VidBadge({ dur, small }) {
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 5, height: small ? 19 : 22, padding: small ? '0 6px 0 5px' : '0 8px 0 6px', borderRadius: 7, background: 'rgba(0,0,0,.62)', color: '#fff', fontSize: small ? 11 : 12, fontWeight: 700, fontFamily: 'var(--font-sans)', backdropFilter: 'blur(4px)', WebkitBackdropFilter: 'blur(4px)' }}>
      <span style={{ display: 'inline-flex', width: small ? 13 : 14, height: small ? 13 : 14 }}><Glyph name="mute" size={small ? 13 : 14} /></span>
      {dur}
    </div>
  );
}

/* One media cell. Static gradient for images; for videos, an animated
   (drifting) gradient that reads as auto-playing muted, with a looping
   progress bar + a muted/duration badge. Clicking opens the shared viewer. */
function MediaCell({ item, idx, onOpen, style }) {
  const [hover, setHover] = React.useState(false);
  const [showAlt, setShowAlt] = React.useState(false);
  const isVideo = item.video || item.kind === 'video';
  const grad = `linear-gradient(135deg, ${(item.grad || ['#3a3a44', '#16151b'])[0]}, ${(item.grad || ['#3a3a44', '#16151b'])[1]})`;
  return (
    <div onClick={onOpen ? (e) => { e.stopPropagation(); onOpen(idx); } : undefined}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => { setHover(false); setShowAlt(false); }}
      style={{ position: 'relative', overflow: 'hidden', cursor: onOpen ? 'zoom-in' : 'default', ...style }}>
      <div className={isVideo ? 'perch-vid-anim' : undefined} style={{ position: 'absolute', inset: 0, background: grad }} />
      {item.url && !isVideo && <img src={item.url} alt="" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />}
      {hover && <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.12)' }} />}
      {isVideo && (
        <React.Fragment>
          <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none' }}>
            <div style={{ width: 44, height: 44, borderRadius: '50%', background: 'rgba(0,0,0,.4)', backdropFilter: 'blur(6px)', WebkitBackdropFilter: 'blur(6px)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', transform: hover ? 'scale(1.08)' : 'scale(1)', transition: 'transform .14s var(--ease-default)', boxShadow: '0 2px 10px rgba(0,0,0,.3)' }}>
              <span style={{ display: 'inline-flex', width: 20, height: 20, marginLeft: 2 }}><Glyph name="play" size={20} /></span>
            </div>
          </div>
          <div style={{ position: 'absolute', left: 8, bottom: 8, pointerEvents: 'none' }}><VidBadge dur={item.dur || '0:24'} small /></div>
          <div className="perch-vid-prog" style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 3, background: 'rgba(255,255,255,.85)', transformOrigin: 'left center' }} />
        </React.Fragment>
      )}
      {!isVideo && item.alt && (
        <React.Fragment>
          <button onClick={(e) => { e.stopPropagation(); setShowAlt(s => !s); }} title="Image description"
            style={{ position: 'absolute', left: 8, bottom: 8, height: 19, padding: '0 6px', borderRadius: 5, border: 'none', cursor: 'pointer', background: showAlt ? '#fff' : 'rgba(0,0,0,.62)', color: showAlt ? '#15141a' : '#fff', fontSize: 10.5, fontWeight: 800, letterSpacing: '.04em', fontFamily: 'var(--font-sans)', backdropFilter: 'blur(4px)', WebkitBackdropFilter: 'blur(4px)' }}>ALT</button>
          {showAlt && (
            <div onClick={(e) => e.stopPropagation()} style={{ position: 'absolute', left: 8, right: 8, bottom: 33, padding: '8px 10px', borderRadius: 9, background: 'rgba(15,14,20,.92)', color: '#fff', fontSize: 12.5, lineHeight: 1.45, fontFamily: 'var(--font-sans)', backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)', boxShadow: '0 6px 20px rgba(0,0,0,.4)', cursor: 'default', maxHeight: '70%', overflowY: 'auto' }}>{item.alt}</div>
          )}
        </React.Fragment>
      )}
    </div>
  );
}

function MediaImages({ items, onOpen }) {
  const n = items.length;
  const radius = 14;
  const cellOf = (it, i, st) => <MediaCell key={i} item={it} idx={i} onOpen={onOpen} style={{ width: '100%', height: '100%', ...st }} />;
  let body;
  if (n === 1) {
    body = <div style={{ aspectRatio: '16 / 10' }}>{cellOf(items[0], 0)}</div>;
  } else if (n === 2) {
    body = <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 2, aspectRatio: '16 / 9' }}>{cellOf(items[0], 0)}{cellOf(items[1], 1)}</div>;
  } else if (n === 3) {
    body = (
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gridTemplateRows: '1fr 1fr', gap: 2, aspectRatio: '16 / 9' }}>
        <div style={{ gridRow: '1 / 3' }}>{cellOf(items[0], 0)}</div>
        {cellOf(items[1], 1)}{cellOf(items[2], 2)}
      </div>
    );
  } else {
    body = (
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gridTemplateRows: '1fr 1fr', gap: 2, aspectRatio: '16 / 9' }}>
        {items.slice(0, 4).map((it, i) => (
          <div key={i} style={{ position: 'relative' }}>
            {cellOf(it, i)}
            {i === 3 && n > 4 && (
              <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: 22, fontWeight: 800, fontFamily: 'var(--font-sans)', pointerEvents: 'none' }}>+{n - 4}</div>
            )}
          </div>
        ))}
      </div>
    );
  }
  return <div style={{ marginTop: 10, borderRadius: radius, overflow: 'hidden', border: '1px solid var(--border-default)' }}>{body}</div>;
}

/* Inline Timeline video player — a thin wrapper around the shared VideoPlayer.
   onOpen(idx) opens the floating new-window gallery viewer (reached from the
   settings menu's "Open in window" item). */
function MediaVideo({ media, onOpen, isX }) {
  return (
    <VideoPlayer
      grad={media.grad}
      dur={media.dur}
      isX={isX}
      variant="inline"
      onOpenWindow={onOpen ? () => onOpen(0) : undefined}
    />
  );
}

/* Source credit for a reposted clip. X shows a "From <creator>" line under a
   video that was lifted from another account; Weibo says "视频来自". The row
   is clickable through to the original creator's profile. */
function MediaSource({ source, isX, onOpenProfile }) {
  const [h, setH] = React.useState(false);
  return (
    <div onClick={(e) => { e.stopPropagation(); onOpenProfile && onOpenProfile(source); }}
      onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'inline-flex', alignItems: 'center', gap: 7, marginTop: 9, maxWidth: '100%', cursor: 'pointer' }}>
      <span style={{ fontSize: 13, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', flex: 'none' }}>{isX ? 'From' : '视频来自'}</span>
      <PAvatar person={source} size={18} />
      <span style={{ fontSize: 13.5, fontWeight: 700, color: h ? 'var(--accent)' : 'var(--fg-heading)', fontFamily: 'var(--font-sans)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', minWidth: 0 }}>{source.name}</span>
      {source.verified && <Verified size={13} />}
      {isX && <span style={{ fontSize: 13, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', whiteSpace: 'nowrap', flex: 'none' }}>@{source.handle}</span>}
    </div>
  );
}

function LinkCard({ media }) {
  const [hover, setHover] = React.useState(false);
  return (
    <a onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{ marginTop: 10, display: 'block', borderRadius: 14, overflow: 'hidden', border: '1px solid var(--border-default)', textDecoration: 'none', background: hover ? 'var(--bg-layer-1)' : 'transparent', transition: 'background .13s', cursor: 'pointer' }}>
      <div style={{ aspectRatio: '16 / 8', background: `linear-gradient(135deg, ${media.grad[0]}, ${media.grad[1]})` }} />
      <div style={{ padding: '10px 14px 12px' }}>
        <div style={{ fontSize: 12, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', marginBottom: 3 }}>{media.domain}</div>
        <div style={{ fontSize: 15, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', lineHeight: 1.3, marginBottom: 3 }}>{media.title}</div>
        <div style={{ fontSize: 13.5, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', lineHeight: 1.4, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{media.desc}</div>
      </div>
    </a>
  );
}

function QuotePost({ q }) {
  return (
    <div style={{ marginTop: 10, borderRadius: 12, border: '1px solid var(--border-default)', padding: '10px 12px', cursor: 'pointer' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
        <PAvatar person={q.author} size={18} />
        <span style={{ fontSize: 13.5, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)' }}>{q.author.name}</span>
        {q.author.verified && <Verified size={13} />}
        {q.author.platform === 'x' && <span style={{ fontSize: 13.5, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>@{q.author.handle}</span>}
        <span style={{ fontSize: 13.5, color: 'var(--fg-subdued)' }}>· {q.time}</span>
      </div>
      <div style={{ fontSize: 13.5, color: 'var(--fg-body)', fontFamily: 'var(--font-sans)', lineHeight: 1.45, display: '-webkit-box', WebkitLineClamp: 4, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{q.text}</div>
      {q.media && q.media.type === 'link' && (
        <div style={{ marginTop: 8, borderRadius: 10, overflow: 'hidden', border: '1px solid var(--border-default)' }}>
          <div style={{ position: 'relative', aspectRatio: '16 / 9', background: `linear-gradient(135deg, ${(q.media.grad && q.media.grad[0]) || '#3a3a44'}, ${(q.media.grad && q.media.grad[1]) || '#16151b'})` }}>
            <span style={{ position: 'absolute', left: 8, bottom: 8, height: 22, padding: '0 8px', borderRadius: 6, background: 'rgba(15,14,18,.72)', color: '#fff', display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 11, fontWeight: 700, fontFamily: 'var(--font-sans)', backdropFilter: 'blur(4px)' }}>
              {q.author.platform === 'x' ? 'Article' : '文章'}
            </span>
          </div>
          <div style={{ padding: '8px 11px 10px' }}>
            <div style={{ fontSize: 11.5, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', marginBottom: 2 }}>{q.media.domain}</div>
            <div style={{ fontSize: 13.5, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', lineHeight: 1.3, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{q.media.title}</div>
          </div>
        </div>
      )}
      {q.media && q.media.type !== 'link' && (() => { const s = mediaSlides(q.media); if (!s.length) return null; const it = s[0]; return (
        <div style={{ marginTop: 8, position: 'relative', borderRadius: 8, overflow: 'hidden', aspectRatio: '16 / 9', border: '1px solid var(--border-default)' }}>
          <div style={{ width: '100%', height: '100%', background: `linear-gradient(135deg, ${it.grad[0]}, ${it.grad[1]})` }} />
          {it.kind === 'video' && (
            <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <div style={{ width: 32, height: 32, borderRadius: '50%', background: 'rgba(0,0,0,.42)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}><span style={{ display: 'inline-flex', width: 15, height: 15, marginLeft: 2 }}><Glyph name="play" size={15} /></span></div>
            </div>
          )}
        </div>
      ); })()}
    </div>
  );
}

function ActionButton({ icon, count, color, active, onClick, title }) {
  const [hover, setHover] = React.useState(false);
  const c = active ? color : (hover ? color : 'var(--fg-subdued)');
  return (
    <button title={title} onClick={(e) => { e.stopPropagation(); onClick && onClick(); }}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{ display: 'inline-flex', alignItems: 'center', gap: 6, background: 'none', border: 'none', cursor: 'pointer', padding: '2px 0', color: c, transition: 'color .12s', fontFamily: 'var(--font-sans)' }}>
      <SvgIcon size={18} color={c}>{ACT_ICONS[icon]}</SvgIcon>
      {count != null && count !== 0 && <span style={{ fontSize: 13, fontWeight: 500, minWidth: 8 }}>{fmt(count)}</span>}
    </button>
  );
}

/* Repost control. Weibo → opens a compose sheet to repost-with-comment.
   X → small menu: Repost (direct) or Quote (compose). */
function RepostMenuItem({ icon, label, danger, onClick }) {
  const [h, setH] = React.useState(false);
  return (
    <button onClick={(e) => { e.stopPropagation(); onClick(); }} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 11, width: '100%', padding: '9px 11px', borderRadius: 9, border: 'none', cursor: 'pointer', background: h ? 'var(--gray-100)' : 'transparent', color: danger ? 'var(--negative)' : 'var(--fg-body)', fontSize: 14, fontWeight: 600, fontFamily: 'var(--font-sans)', textAlign: 'left' }}>
      <span style={{ display: 'inline-flex', width: 18, height: 18, color: danger ? 'var(--negative)' : 'var(--fg-subdued)', flex: 'none' }}><Glyph name={icon} size={18} /></span>
      {label}
    </button>
  );
}

function RepostAction({ post, count, active, onDirectRepost, onQuote, onRepost, up }) {
  const isX = post.author.platform === 'x';
  const [menu, setMenu] = React.useState(false);
  const handle = () => { if (!isX) { onRepost(post); } else { setMenu(m => !m); } };
  return (
    <span style={{ position: 'relative', display: 'inline-flex' }}>
      <ActionButton icon="repost" count={count} color="var(--green-700)" active={active} title={isX ? 'Repost' : '转发'} onClick={handle} />
      {menu && (
        <React.Fragment>
          <div onClick={(e) => { e.stopPropagation(); setMenu(false); }} style={{ position: 'fixed', inset: 0, zIndex: 70 }} />
          <div onClick={(e) => e.stopPropagation()} style={{ position: 'absolute', [up ? 'bottom' : 'top']: 30, left: -6, width: 184, background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', borderRadius: 12, boxShadow: 'var(--shadow-elevated)', padding: 6, zIndex: 71 }}>
            <RepostMenuItem icon="repost" label={active ? 'Undo repost' : 'Repost'} danger={active} onClick={() => { setMenu(false); onDirectRepost(post); }} />
            <RepostMenuItem icon="pencil" label="Quote" onClick={() => { setMenu(false); onQuote(post); }} />
          </div>
        </React.Fragment>
      )}
    </span>
  );
}

function Post({ post, platform, connectAbove, connectBelow, onAction, onReply, onOpenPost, onOpenProfile, onMention, onQuote, onRepost, onDirectRepost, onOpenMedia }) {
  const a = post.author;
  const [hover, setHover] = React.useState(false);
  const isX = a.platform === 'x';
  const openProfile = (e) => { e.stopPropagation(); onOpenProfile && onOpenProfile(a); };
  const openMedia = (i) => { if (onOpenMedia) onOpenMedia(mediaSlides(post.media), i, post.author); };
  // Thread connector — a hairline running through the 40px avatar gutter that
  // visually stitches consecutive posts in the same conversation together.
  const THREAD_LINE = 'var(--gray-400)';
  return (
    <article onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      onClick={() => onOpenPost && onOpenPost(post)}
      style={{ position: 'relative', padding: '12px 16px', paddingBottom: connectBelow ? 8 : 12, borderBottom: connectBelow ? 'none' : '1px solid var(--border-default)', background: hover ? 'var(--bg-layer-1)' : 'transparent', transition: 'background .12s', cursor: 'pointer' }}>
      {connectAbove && <span aria-hidden="true" style={{ position: 'absolute', left: 35, top: 0, width: 2, height: 18, background: THREAD_LINE, pointerEvents: 'none', zIndex: 0 }} />}
      {connectBelow && <span aria-hidden="true" style={{ position: 'absolute', left: 35, top: 50, width: 2, bottom: 0, background: THREAD_LINE, pointerEvents: 'none', zIndex: 0 }} />}
      {post.repostedBy && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginLeft: 51, marginBottom: 5, color: 'var(--fg-subdued)', fontSize: 12.5, fontWeight: 600, fontFamily: 'var(--font-sans)' }}>
          <SvgIcon size={14} color="var(--fg-subdued)">{ACT_ICONS.repost}</SvgIcon>
          {post.repostedBy} {isX ? 'reposted' : '转发了'}
        </div>
      )}
      {post.pinned && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginLeft: 51, marginBottom: 5, color: 'var(--fg-subdued)', fontSize: 12.5, fontWeight: 600, fontFamily: 'var(--font-sans)' }}>
          <SvgIcon size={13} color="var(--fg-subdued)">{ACT_ICONS.pin}</SvgIcon>
          {isX ? 'Pinned' : '置顶'}
        </div>
      )}
      <div style={{ display: 'flex', gap: 11 }}>
        <span onClick={openProfile} style={{ flex: 'none', cursor: 'pointer', position: 'relative', zIndex: 1 }}><PAvatar person={a} size={40} /></span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span onClick={openProfile} style={{ fontSize: 15, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', whiteSpace: 'nowrap', flex: 'none', cursor: 'pointer' }}>{a.name}</span>
            {a.verified && <Verified size={15} />}
            {isX && <span onClick={openProfile} style={{ fontSize: 14, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: '0 1 auto', minWidth: 0, marginLeft: -1, cursor: 'pointer' }}>@{a.handle}</span>}
            <span style={{ fontSize: 14, color: 'var(--fg-subdued)', whiteSpace: 'nowrap', flex: 'none' }}>· {post.time}</span>
            <div style={{ flex: 1 }} />
            {window.DebugBus && DebugBus.inline() && (
              <button onClick={(e) => { e.stopPropagation(); DebugBus.openJson(isX ? 'Tweet · ' + a.name : '微博 · ' + a.name, post, (isX ? '@' + a.handle : a.name) + ' · id ' + post.id); }}
                title={isX ? 'View raw JSON' : '查看原始 JSON'}
                style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', width: 22, height: 22, marginRight: 2, borderRadius: 6, border: 'none', cursor: 'pointer', background: 'transparent', color: 'var(--fg-subdued)', opacity: hover ? 1 : 0, transition: 'opacity .12s, background .12s, color .12s', flex: 'none' }}
                onMouseEnter={(e) => { e.currentTarget.style.background = 'var(--gray-100)'; e.currentTarget.style.color = 'var(--accent)'; }}
                onMouseLeave={(e) => { e.currentTarget.style.background = 'transparent'; e.currentTarget.style.color = 'var(--fg-subdued)'; }}>
                <span style={{ display: 'inline-flex', width: 15, height: 15 }}><Glyph name="code" size={15} /></span>
              </button>
            )}
            <span style={{ display: 'inline-flex', width: 18, height: 18, color: 'var(--fg-subdued)', opacity: hover ? 1 : 0, transition: 'opacity .12s' }}><Glyph name="more" size={18} /></span>
          </div>
          <div style={{ marginTop: 2, fontSize: 15, lineHeight: 1.46, color: 'var(--fg-body)', fontFamily: 'var(--font-sans)', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
            <RichText text={post.text} onMention={onMention} />
          </div>
          {post.media && (post.media.type === 'images' || post.media.type === 'gallery') && <MediaImages items={post.media.items} onOpen={openMedia} />}
          {post.media && post.media.type === 'video' && <MediaVideo media={post.media} onOpen={openMedia} isX={isX} />}
          {post.media && post.media.type === 'video' && post.media.source && <MediaSource source={post.media.source} isX={isX} onOpenProfile={onOpenProfile} />}
          {post.media && post.media.type === 'link' && <LinkCard media={post.media} />}
          {post.quote && <QuotePost q={post.quote} />}
          <div style={{ display: 'flex', justifyContent: 'space-between', maxWidth: 340, marginTop: 12 }}>
            <ActionButton icon="reply" count={post.stats.replies} color="var(--accent)" title={isX ? 'Reply' : '评论'} onClick={() => onReply && onReply(post)} />
            <RepostAction post={post} count={post.stats.reposts} active={post.reposted} onDirectRepost={onDirectRepost} onQuote={onQuote} onRepost={onRepost} />
            <ActionButton icon="heart" count={post.stats.likes} color="var(--magenta-800)" active={post.liked} title={isX ? 'Like' : '赞'} onClick={() => onAction(post.id, 'liked')} />
            <ActionButton icon="bookmark" color="var(--accent)" active={post.bookmarked} title={isX ? 'Bookmark' : '收藏'} onClick={() => onAction(post.id, 'bookmarked')} />
            <ActionButton icon="share" color="var(--accent)" title={isX ? 'Share' : '分享'} onClick={() => {}} />
          </div>
        </div>
      </div>
    </article>
  );
}

/* Closing affordance for a truncated thread group: a dotted continuation of
   the connector plus a “Show this thread” link, indented to the text column. */
function ThreadTail({ isX, onClick }) {
  const [h, setH] = React.useState(false);
  return (
    <div onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', gap: 11, padding: '0 16px 12px', cursor: 'pointer', borderBottom: '1px solid var(--border-default)', background: h ? 'var(--bg-layer-1)' : 'transparent', transition: 'background .12s' }}>
      <span style={{ width: 40, flex: 'none', display: 'flex', justifyContent: 'center' }}>
        <span aria-hidden="true" style={{ width: 2, alignSelf: 'stretch', minHeight: 24, marginTop: -2, backgroundImage: 'repeating-linear-gradient(var(--gray-400) 0 2.5px, transparent 2.5px 6.5px)' }} />
      </span>
      <span style={{ flex: 1, minWidth: 0, padding: '7px 0', fontSize: 14.5, fontWeight: 600, color: 'var(--accent)', fontFamily: 'var(--font-sans)' }}>{isX ? 'Show this thread' : '显示回复'}</span>
    </div>
  );
}

/* Renders a list of posts with X-style thread grouping: posts that share a
   `thread` id and sit next to each other are stitched by a vertical connector,
   with no divider between them. A `moreReplies` post closes its group with a
   “Show this thread” tail that opens the thread root. */
function ThreadedList({ posts, platform, handlers }) {
  const out = [];
  for (let i = 0; i < posts.length; i++) {
    const p = posts[i], prev = posts[i - 1], next = posts[i + 1];
    const samePrev = !!(p.thread && prev && prev.thread === p.thread);
    const sameNext = !!(p.thread && next && next.thread === p.thread);
    const hasTail = !!(p.thread && p.moreReplies && !sameNext);
    out.push(
      <Post key={p.id} post={p} platform={platform}
        connectAbove={samePrev} connectBelow={sameNext || hasTail} {...handlers} />
    );
    if (hasTail) {
      let root = p;
      for (let j = i; j >= 0 && posts[j].thread === p.thread; j--) root = posts[j];
      out.push(
        <ThreadTail key={p.id + '-tail'} isX={p.author.platform === 'x'}
          onClick={() => handlers.onOpenPost && handlers.onOpenPost(root)} />
      );
    }
  }
  return out;
}

Object.assign(window, { Post, ThreadedList, ThreadTail, PAvatar, Verified, fmt, RichText, MediaImages, MediaVideo, MediaSource, MediaCell, VidBadge, LinkCard, QuotePost, ActionButton, RepostAction, SvgIcon, ACT_ICONS });

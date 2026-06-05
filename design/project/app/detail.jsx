/* Navigation screens: post-detail and profile, rendered INSIDE a column
   (iOS-style push/pop). The column owns the stack + slide animation;
   these components are just the screen bodies. */

/* A reply. In the X conversation model every reply is itself openable: tapping
   the row pushes a focal screen where this reply becomes the big post, its
   parents stack above, and its own replies list below (see resolvePost). The
   avatar / name still deep-link to the author; the action buttons act in place.
   A "show replies" cue appears when the reply has its own thread. */
function CommentNode({ c, onOpenProfile, onMention, onReply, onOpenPost }) {
  const [hover, setHover] = React.useState(false);
  const [liked, setLiked] = React.useState(!!c.liked);
  const a = c.author;
  const isX = a.platform === 'x';
  const likes = (c.stats ? c.stats.likes : 0) + (liked ? 1 : 0) - (c.liked ? 1 : 0);
  const replyN = c.stats ? c.stats.replies : 0;
  const openP = (e) => { e.stopPropagation(); onOpenProfile(a); };
  const open = () => onOpenPost && onOpenPost(c);

  return (
    <article onClick={open} onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{ position: 'relative', display: 'flex', gap: 11, padding: '12px 16px', borderBottom: '1px solid var(--border-default)', background: hover ? 'var(--bg-layer-1)' : 'transparent', transition: 'background .12s', cursor: 'pointer' }}>
      <span onClick={openP} style={{ flex: 'none', cursor: 'pointer', position: 'relative', zIndex: 1 }}><PAvatar person={a} size={36} /></span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span onClick={openP} style={{ fontSize: 14.5, fontWeight: 700, color: 'var(--fg-heading)', cursor: 'pointer', whiteSpace: 'nowrap' }}>{a.name}</span>
          {a.verified && <Verified size={13} />}
          {isX && <span onClick={openP} style={{ fontSize: 13.5, color: 'var(--fg-subdued)', cursor: 'pointer', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>@{a.handle}</span>}
          <span style={{ fontSize: 13.5, color: 'var(--fg-subdued)', whiteSpace: 'nowrap', flex: 'none' }}>· {c.time}</span>
        </div>
        <div style={{ marginTop: 2, fontSize: 14.5, lineHeight: 1.46, color: 'var(--fg-body)', fontFamily: 'var(--font-sans)', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
          <RichText text={c.text} onMention={onMention} />
        </div>
        <div style={{ display: 'flex', gap: 24, marginTop: 8 }}>
          <ActionButton icon="reply" count={replyN} color="var(--accent)" title={isX ? 'Reply' : '回复'} onClick={() => onReply(c)} />
          <ActionButton icon="heart" count={likes} color="var(--magenta-800)" active={liked} title={isX ? 'Like' : '赞'} onClick={() => setLiked(v => !v)} />
        </div>
      </div>
    </article>
  );
}

/* Small circular icon button used in the focal-post header. */
function DetailIconBtn({ name, title, active, onClick }) {
  const [h, setH] = React.useState(false);
  return (
    <button title={title} onClick={(e) => { e.stopPropagation(); onClick && onClick(); }} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ width: 32, height: 32, borderRadius: '50%', border: 'none', flex: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', background: (h || active) ? 'var(--gray-100)' : 'transparent', color: (h || active) ? 'var(--fg-heading)' : 'var(--fg-subdued)', transition: 'background .12s, color .12s' }}>
      <span style={{ display: 'inline-flex', width: 19, height: 19 }}><Glyph name={name} size={19} /></span>
    </button>
  );
}

/* Full content of a post + its replies, with thread context above and an
   expandable reply tree below. */
function DetailScreen({ post, repliesOf, onOpenPost, onOpenProfile, onMention, onAction, onReply, onQuote, onRepost, onDirectRepost, onOpenMedia }) {
  const [moreOpen, setMoreOpen] = React.useState(false);
  const [shareOpen, setShareOpen] = React.useState(false);
  const [following, setFollowing] = React.useState(false);
  const [flash, setFlash] = React.useState(null);
  const flashRef = React.useRef(null);
  const doFlash = (m) => { setFlash(m); clearTimeout(flashRef.current); flashRef.current = setTimeout(() => setFlash(null), 1700); };

  if (!post) {
    return <div style={{ padding: '64px 28px', textAlign: 'center', color: 'var(--fg-subdued)', fontSize: 15 }}>Post unavailable</div>;
  }
  const a = post.author;
  const isX = a.platform === 'x';
  // for a focal comment the chain (root post + parent comments) is precomputed
  // by resolvePost; for a normal post fall back to its same-thread ancestors.
  const ancestors = post._ancestors ? post._ancestors
    : ((typeof threadAncestors === 'function') ? threadAncestors(post) : []);
  const reps = repliesOf(post);
  const hasMedia = !!post.media;
  const openA = (e) => { e.stopPropagation(); onOpenProfile(a); };
  const openMedia = (i) => { if (onOpenMedia) onOpenMedia(mediaSlides(post.media), i, post.author); };
  const shared = { onOpenPost, onOpenProfile, onMention, onAction, onReply, onQuote, onRepost, onDirectRepost, onOpenMedia };

  return (
    <div style={{ position: 'relative', minHeight: '100%' }}>
      {/* thread context — the posts that came before this one in the conversation */}
      {ancestors.map((p, i) => (
        <Post key={p.id} post={p} platform={p.author.platform} connectAbove={i > 0} connectBelow={true} {...shared} />
      ))}

      {/* focal post */}
      <div style={{ padding: '12px 16px 0', position: 'relative' }}>
        {ancestors.length > 0 && <span aria-hidden="true" style={{ position: 'absolute', left: 35, top: 0, width: 2, height: 14, background: 'var(--gray-400)' }} />}
        <div style={{ display: 'flex', gap: 11, alignItems: 'flex-start' }}>
          <span onClick={openA} style={{ flex: 'none', cursor: 'pointer', position: 'relative', zIndex: 1 }}><PAvatar person={a} size={44} /></span>
          <div onClick={openA} style={{ flex: 1, minWidth: 0, cursor: 'pointer', paddingTop: 1 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
              <span style={{ fontSize: 15.5, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.01em', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{a.name}</span>
              {a.verified && <Verified size={15} />}
            </div>
            <div style={{ fontSize: 14, color: 'var(--fg-subdued)', marginTop: 1 }}>{isX ? '@' + a.handle : '微博'}</div>
          </div>
          {isX && !following && <FollowBtn following={following} isX={isX} onClick={() => setFollowing(true)} />}
          <div style={{ position: 'relative', flex: 'none' }}>
            <DetailIconBtn name="more" title={isX ? 'More' : '更多'} active={moreOpen} onClick={() => { setMoreOpen(v => !v); setShareOpen(false); }} />
            {moreOpen && (
              <PostMoreMenu post={post} isX={isX} following={following} onToggleFollow={() => setFollowing(v => !v)} onFlash={doFlash} onClose={() => setMoreOpen(false)} />
            )}
          </div>
        </div>

        <div style={{ marginTop: 12, fontSize: 17, lineHeight: 1.5, color: 'var(--fg-body)', fontFamily: 'var(--font-sans)', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
          <RichText text={post.text} onMention={onMention} />
        </div>
        {post.media && (post.media.type === 'images' || post.media.type === 'gallery') && <MediaImages items={post.media.items} onOpen={openMedia} />}
        {post.media && post.media.type === 'video' && <MediaVideo media={post.media} onOpen={openMedia} isX={isX} />}
        {post.media && post.media.type === 'link' && <LinkCard media={post.media} />}
        {post.quote && <QuotePost q={post.quote} />}
        <div style={{ marginTop: 14, marginBottom: 12, fontSize: 13.5, color: 'var(--fg-subdued)' }}>
          {post.time}{post.stats.views ? ` · ` : ''}{post.stats.views ? <b style={{ color: 'var(--fg-heading)', fontWeight: 700 }}>{post.stats.views}</b> : null}{post.stats.views ? ` ${isX ? 'Views' : '查看'}` : ''}
        </div>
      </div>

      {/* action bar — counts inline, share opens its own menu */}
      <div style={{ position: 'relative', display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 16px', borderTop: '1px solid var(--border-default)', borderBottom: '1px solid var(--border-default)' }}>
        <ActionButton icon="reply" count={post.stats.replies} color="var(--accent)" title={isX ? 'Reply' : '评论'} onClick={() => onReply(post)} />
        <RepostAction post={post} count={post.stats.reposts} active={post.reposted} onDirectRepost={onDirectRepost} onQuote={onQuote} onRepost={onRepost} />
        <ActionButton icon="heart" count={post.stats.likes} color="var(--magenta-800)" active={post.liked} title={isX ? 'Like' : '赞'} onClick={() => onAction(post.id, 'liked')} />
        <ActionButton icon="bookmark" color="var(--accent)" active={post.bookmarked} title={isX ? 'Bookmark' : '收藏'} onClick={() => onAction(post.id, 'bookmarked')} />
        <div style={{ position: 'relative', display: 'inline-flex' }}>
          <ActionButton icon="share" color="var(--accent)" active={shareOpen} title={isX ? 'Share' : '分享'} onClick={() => { setShareOpen(v => !v); setMoreOpen(false); }} />
          {shareOpen && (
            <ShareMenu post={post} isX={isX} hasMedia={hasMedia} bookmarked={post.bookmarked} onBookmark={() => onAction(post.id, 'bookmarked')} onFlash={doFlash} onClose={() => setShareOpen(false)} />
          )}
        </div>
      </div>

      {/* replies sort header */}
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 16px 6px' }}>
        <button style={{ display: 'inline-flex', alignItems: 'center', gap: 3, padding: 0, border: 'none', background: 'none', cursor: 'pointer', color: 'var(--fg-subdued)', fontSize: 13.5, fontWeight: 700, fontFamily: 'var(--font-sans)' }}>
          {isX ? 'Most relevant' : '相关'}
          <span style={{ display: 'inline-flex', width: 14, height: 14 }}><Glyph name="chevron-down" size={14} /></span>
        </button>
      </div>

      {/* tap-to-comment affordance */}
      <button onClick={() => onReply(post)}
        style={{ display: 'flex', alignItems: 'center', gap: 11, width: '100%', padding: '11px 16px 13px', border: 'none', borderBottom: '1px solid var(--border-default)', background: 'transparent', cursor: 'pointer', textAlign: 'left' }}>
        <span style={{ width: 36, height: 36, borderRadius: '50%', background: 'var(--bg-layer-2)', border: '1px solid var(--border-default)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: 'var(--fg-subdued)', flex: 'none' }}><Glyph name="pencil" size={17} /></span>
        <span style={{ fontSize: 15, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>{isX ? 'Post your reply' : '写下你的评论…'}</span>
      </button>

      {reps.map(c => (
        <CommentNode key={c.id} c={c}
          onOpenProfile={onOpenProfile} onMention={onMention}
          onReply={onReply} onOpenPost={onOpenPost} />
      ))}
      <div style={{ height: 20 }} />
      <ColFlash msg={flash} />
    </div>
  );
}

function FollowBtn({ following, isX, onClick }) {
  const [h, setH] = React.useState(false);
  const label = following ? (isX ? (h ? 'Unfollow' : 'Following') : (h ? '取消关注' : '已关注')) : (isX ? 'Follow' : '关注');
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ height: 34, padding: '0 18px', borderRadius: 9999, fontFamily: 'var(--font-sans)', fontSize: 14, fontWeight: 700, cursor: 'pointer', flex: 'none', transition: 'all .12s',
        border: following ? '1px solid var(--border-strong)' : 'none',
        background: following ? 'transparent' : 'var(--fg-heading)',
        color: following ? (h ? 'var(--negative)' : 'var(--fg-heading)') : 'var(--bg-base)',
        borderColor: following && h ? 'var(--negative)' : (following ? 'var(--border-strong)' : 'transparent') }}>{label}</button>
  );
}

/* A user's profile: banner, identity, bio, stats, and their posts. */
function ProfileScreen({ person, isOwn, profileFor, authorPosts, onAction, onReply, onOpenPost, onOpenProfile, onMention, onQuote, onRepost, onDirectRepost, onOpenMedia }) {
  const p = profileFor(person);
  const isX = person.platform === 'x';
  const [following, setFollowing] = React.useState(false);
  const posts = authorPosts(person);
  const meta = { fontSize: 13.5, color: 'var(--fg-subdued)', display: 'inline-flex', alignItems: 'center', gap: 5 };
  return (
    <div>
      <div style={{ height: 124, background: p.banner }} />
      <div style={{ padding: '0 16px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginTop: -42 }}>
          <span style={{ borderRadius: '50%', padding: 4, background: 'var(--bg-base)', display: 'inline-flex' }}><PAvatar person={person} size={82} /></span>
          {isOwn ? (
            <button style={{ height: 34, padding: '0 18px', borderRadius: 9999, border: '1px solid var(--border-strong)', background: 'transparent', color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', fontSize: 14, fontWeight: 700, cursor: 'pointer', marginBottom: 6 }}>{isX ? 'Edit profile' : '编辑资料'}</button>
          ) : (
            <span style={{ marginBottom: 6 }}><FollowBtn following={following} isX={isX} onClick={() => setFollowing(v => !v)} /></span>
          )}
        </div>
        <div style={{ marginTop: 10 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ fontSize: 21, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.01em' }}>{person.name}</span>
            {person.verified && <Verified size={18} />}
          </div>
          {isX && <div style={{ fontSize: 14.5, color: 'var(--fg-subdued)', marginTop: 1 }}>@{person.handle}</div>}
          <div style={{ marginTop: 11, fontSize: 14.5, lineHeight: 1.5, color: 'var(--fg-body)', fontFamily: 'var(--font-sans)' }}>{p.bio}</div>
          <div style={{ marginTop: 11, display: 'flex', gap: 18, flexWrap: 'wrap' }}>
            <span style={meta}><Glyph name="location" size={15} />{p.location}</span>
            <span style={meta}><Glyph name="calendar" size={15} />{p.joined}</span>
          </div>
          <div style={{ marginTop: 11, display: 'flex', gap: 20, fontSize: 14 }}>
            <span><b style={{ color: 'var(--fg-heading)', fontWeight: 700 }}>{p.following}</b> <span style={{ color: 'var(--fg-subdued)' }}>{isX ? 'Following' : '关注'}</span></span>
            <span><b style={{ color: 'var(--fg-heading)', fontWeight: 700 }}>{p.followers}</b> <span style={{ color: 'var(--fg-subdued)' }}>{isX ? 'Followers' : '粉丝'}</span></span>
          </div>
        </div>
        <div style={{ display: 'flex', marginTop: 14, borderBottom: '1px solid var(--border-default)' }}>
          <div style={{ padding: '11px 2px', marginRight: 26, borderBottom: '3px solid var(--accent)', fontWeight: 800, color: 'var(--fg-heading)', fontSize: 14.5 }}>{isX ? 'Posts' : '微博'}</div>
          <div style={{ padding: '11px 2px', color: 'var(--fg-subdued)', fontSize: 14.5, fontWeight: 600 }}>{isX ? 'Media' : '相册'}</div>
        </div>
      </div>
      {posts.length ? (
        <ThreadedList posts={posts} platform={person.platform}
          handlers={{ onAction, onReply, onOpenPost, onOpenProfile, onMention, onQuote, onRepost, onDirectRepost, onOpenMedia }} />
      ) : (
        <div style={{ padding: '56px 28px', textAlign: 'center', color: 'var(--fg-subdued)' }}>
          <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--fg-heading)', marginBottom: 6 }}>{isX ? 'No posts yet' : '还没有内容'}</div>
          <div style={{ fontSize: 14 }}>{isX ? 'When they post, it’ll show up here.' : '发布的内容会显示在这里。'}</div>
        </div>
      )}
      <div style={{ height: 20 }} />
    </div>
  );
}

function NavTitle(screen, resolvePost) {
  if (screen.kind === 'post') { const p = resolvePost(screen.id); return p && p.author.platform === 'x' ? 'Post' : '微博正文'; }
  return screen.person.name;
}

Object.assign(window, { DetailScreen, ProfileScreen, CommentNode, DetailIconBtn, NavTitle });

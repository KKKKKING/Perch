/* Floating compose sheet — account-scoped posting with a character ring,
   @/# autocomplete, image attachments, polls (with image options),
   who-can-reply, scheduling, and content disclosure. */

function CharRing({ used, limit, threshold }) {
  const r = 10, c = 2 * Math.PI * r;
  // Below the threshold the control behaves as the classic countdown ring
  // (arc filling toward `threshold`). Past it, it morphs into a solid liquid
  // fill rising toward the long-post `limit` — fill height = used / limit.
  const fillMode = threshold != null && used > threshold;
  const ratio = Math.min(used / (fillMode ? limit : (threshold || limit)), 1);
  const remaining = limit - used;
  const near = remaining <= 20;
  const over = remaining < 0;
  const stroke = over ? 'var(--negative)' : near ? 'var(--notice-bg)' : 'var(--accent)';
  const fillH = 2 * r * ratio;               // liquid height, from the bottom up
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      {(near || over) && <span style={{ fontSize: 13, fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: over ? 'var(--negative)' : 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>{remaining}</span>}
      <svg width="26" height="26" viewBox="0 0 26 26">
        {fillMode ? (
          <React.Fragment>
            <defs><clipPath id="charFillClip"><circle cx="13" cy="13" r={r - 0.4} /></clipPath></defs>
            <circle cx="13" cy="13" r={r} fill="none" stroke={stroke} strokeWidth="2.5" />
            <rect x={13 - r} y={13 + r - fillH} width={2 * r} height={fillH} fill={stroke} clipPath="url(#charFillClip)"
              style={{ transition: 'y .15s var(--ease-default), height .15s var(--ease-default), fill .15s' }} />
          </React.Fragment>
        ) : (
          <React.Fragment>
            <circle cx="13" cy="13" r={r} fill="none" stroke="var(--gray-300)" strokeWidth="2.5" />
            <circle cx="13" cy="13" r={r} fill="none" stroke={stroke} strokeWidth="2.5" strokeLinecap="round"
              strokeDasharray={c} strokeDashoffset={c * (1 - ratio)} transform="rotate(-90 13 13)"
              style={{ transition: 'stroke-dashoffset .15s var(--ease-default), stroke .15s' }} />
          </React.Fragment>
        )}
      </svg>
    </div>
  );
}

function ComposeTool({ name, title, onClick, active, disabled, custom }) {
  const [h, setH] = React.useState(false);
  const color = disabled ? 'var(--fg-disabled)' : 'var(--accent)';
  return (
    <button title={title} disabled={disabled} onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ width: 34, height: 34, borderRadius: 8, border: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', cursor: disabled ? 'default' : 'pointer', background: active ? 'color-mix(in srgb, var(--accent) 16%, transparent)' : (h && !disabled ? 'var(--gray-100)' : 'transparent'), color, transition: 'background .12s', flex: 'none' }}>
      <span style={{ display: 'inline-flex', width: 20, height: 20 }}>{custom || <Glyph name={name} size={20} />}</span>
    </button>
  );
}

function ComposeChip({ icon, label, onRemove, isX }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 26, padding: '0 6px 0 10px', borderRadius: 9999, background: 'color-mix(in srgb, var(--accent) 14%, transparent)', color: 'var(--accent)', fontSize: 12.5, fontWeight: 700, fontFamily: 'var(--font-sans)' }}>
      <span style={{ display: 'inline-flex', width: 13, height: 13 }}>{icon}</span>
      {label}
      <button onClick={onRemove} title={isX ? 'Remove' : '移除'} style={{ width: 18, height: 18, borderRadius: '50%', border: 'none', background: 'transparent', color: 'inherit', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', opacity: .8 }}><Glyph name="close" size={11} /></button>
    </span>
  );
}

/* Original post being replied to — full author header, text, media, and any
   nested quote, with a thread line running down through the avatar gutter to
   connect into the reply composer below. */
function ReplyRefBlock({ post, isX }) {
  const a = post.author;
  return (
    <div style={{ display: 'flex', gap: 12, padding: '14px 16px 0' }}>
      <div style={{ flex: 'none', width: 44, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <PAvatar person={a} size={44} />
        <div style={{ width: 2, flex: 1, minHeight: 14, marginTop: 4, background: 'var(--gray-400)', borderRadius: 1 }} />
      </div>
      <div style={{ flex: 1, minWidth: 0, paddingBottom: 8 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span style={{ fontSize: 15, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)', whiteSpace: 'nowrap', flex: 'none' }}>{a.name}</span>
          {a.verified && <Verified size={15} />}
          {isX && <span style={{ fontSize: 14, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: '0 1 auto', minWidth: 0 }}>@{a.handle}</span>}
          <span style={{ fontSize: 14, color: 'var(--fg-subdued)', whiteSpace: 'nowrap', flex: 'none' }}>· {post.time}</span>
        </div>
        {post.text && (
          <div style={{ marginTop: 2, fontSize: 15, lineHeight: 1.46, color: 'var(--fg-body)', fontFamily: 'var(--font-sans)', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
            <RichText text={post.text} />
          </div>
        )}
        {post.media && (post.media.type === 'images' || post.media.type === 'gallery') && <MediaImages items={post.media.items} />}
        {post.media && post.media.type === 'video' && <MediaVideo media={post.media} isX={isX} />}
        {post.media && post.media.type === 'link' && <LinkCard media={post.media} />}
        {post.quote && <QuotePost q={post.quote} />}
      </div>
    </div>
  );
}

function Compose({ accounts, fromId, onChangeFrom, onClose, onPost, context }) {
  const from = accounts.find(a => a.id === fromId) || accounts[0];
  const isX = from.platform === 'x';
  // Primary accounts get a long-post limit (10,000); others keep the standard
  // limit (X 280 / Weibo 2,000). Past 280 chars the ring switches to a liquid
  // fill that tracks progress toward the long-post limit.
  const isPrimary = !!from.primary;
  const limit = isPrimary ? 10000 : (isX ? 280 : 2000);
  const ringThreshold = isPrimary ? 280 : null;
  const ctx = context || null;
  const mode = ctx && ctx.mode;            // 'reply' | 'quote' | 'repost'
  const orig = ctx && ctx.post;            // the post being replied to / quoted / reposted

  const [text, setText] = React.useState('');
  const [caret, setCaret] = React.useState(0);
  const [menu, setMenu] = React.useState(false);
  const [images, setImages] = React.useState([]);                 // [{ id, url, alt }]
  const [poll, setPoll] = React.useState(null);                   // null | { choices, days, hours, minutes }
  const [replyScope, setReplyScope] = React.useState('everyone');
  const [scopeMenu, setScopeMenu] = React.useState(false);
  const [disclosure, setDisclosure] = React.useState({ paid: false, ai: false });
  const [scheduledAt, setScheduledAt] = React.useState(null);
  const [editing, setEditing] = React.useState(null);          // { id, tab } — image being edited
  const [dialog, setDialog] = React.useState(null);               // 'schedule' | 'disclosure' | 'drafts' | null
  const [acHi, setAcHi] = React.useState(0);
  const [acDismiss, setAcDismiss] = React.useState('');
  const taRef = React.useRef(null);
  const fileRef = React.useRef(null);

  React.useEffect(() => { const t = setTimeout(() => taRef.current && taRef.current.focus(), 60); return () => clearTimeout(t); }, []);

  // ── @/# autocomplete ──
  const tok = activeToken(text, caret);
  const matches = tok ? matchesFor(tok, from.platform) : [];
  const acSig = tok ? `${tok.type}:${tok.start}` : '';
  const acOpen = !!tok && matches.length > 0 && acSig !== acDismiss && document.activeElement === taRef.current;
  React.useEffect(() => { setAcHi(0); }, [acSig]);

  const syncCaret = (e) => setCaret(e.target.selectionStart || 0);
  const onText = (e) => { setText(e.target.value); setCaret(e.target.selectionStart || 0); };
  const pickAuto = (insert) => {
    if (!tok) return;
    const r = replaceToken(text, tok, insert);
    setText(r.text);
    requestAnimationFrame(() => { const ta = taRef.current; if (ta) { ta.focus(); ta.setSelectionRange(r.caret, r.caret); } setCaret(r.caret); });
  };
  const onTaKey = (e) => {
    if (acOpen) {
      if (e.key === 'ArrowDown') { e.preventDefault(); setAcHi(h => (h + 1) % matches.length); return; }
      if (e.key === 'ArrowUp') { e.preventDefault(); setAcHi(h => (h - 1 + matches.length) % matches.length); return; }
      if (e.key === 'Enter' || e.key === 'Tab') { e.preventDefault(); const it = matches[acHi]; pickAuto(it.handle ? '@' + it.handle : '#' + it.tag); return; }
      if (e.key === 'Escape') { e.preventDefault(); setAcDismiss(acSig); return; }
    }
  };

  // ── images ──
  const addFiles = (fileList) => {
    const files = Array.from(fileList || []).filter(f => f.type.startsWith('image/'));
    files.slice(0, 4 - images.length).forEach(f => {
      const reader = new FileReader();
      reader.onload = () => setImages(prev => prev.length >= 4 ? prev : [...prev, { id: 'im' + Date.now() + Math.round(Math.random() * 1e4), url: reader.result, alt: '' }]);
      reader.readAsDataURL(f);
    });
  };
  const removeImg = (id) => setImages(prev => prev.filter(i => i.id !== id));
  const applyEdit = (id, patch) => setImages(prev => prev.map(i => i.id === id ? { ...i, ...patch } : i));
  const editingImg = editing && images.find(i => i.id === editing.id);

  // ── poll ──
  const togglePoll = () => setPoll(p => p ? null : { choices: [{ id: 'c1', text: '', img: null }, { id: 'c2', text: '', img: null }], days: 1, hours: 0, minutes: 0 });
  const pollValid = poll && poll.choices.filter(c => c.text.trim() || c.img).length >= 2;

  const used = [...text].length;
  const hasContent = text.trim().length > 0 || images.length > 0 || (poll && pollValid);
  const canPost = mode === 'repost' ? used <= limit : (hasContent && used <= limit);

  const submit = () => {
    if (!canPost) return;
    const extras = { images: images.map(i => ({ url: i.url, alt: i.alt })), poll, replyScope, disclosure, scheduledAt };
    onPost(from, text.trim(), ctx, extras);
  };

  React.useEffect(() => {
    const onKey = (e) => {
      if (e.key === 'Escape') { if (editing) return; if (dialog) { setDialog(null); return; } if (scopeMenu) { setScopeMenu(false); return; } if (acOpen) return; onClose(); }
      if ((e.metaKey || e.ctrlKey) && e.key === 'Enter' && canPost && !dialog && !editing) submit();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [text, from, limit, canPost, dialog, scopeMenu, acOpen, images, poll, scheduledAt, editing]);

  const confirmSchedule = (date) => { setScheduledAt(date); setDialog(null); };

  const placeholder = mode === 'reply' ? (isX ? 'Post your reply' : '回复…')
    : mode === 'quote' ? (isX ? 'Add a comment' : '添加评论')
    : mode === 'repost' ? (isX ? 'Add a comment' : '说点什么…（选填）')
    : (isX ? 'What’s happening?' : '有什么新鲜事想分享给大家？');
  const label = scheduledAt ? (isX ? 'Schedule' : '定时发布')
    : mode === 'reply' ? (isX ? 'Reply' : '回复')
    : mode === 'quote' ? (isX ? 'Post' : '发布')
    : mode === 'repost' ? (isX ? 'Repost' : '转发')
    : (isX ? 'Post' : '发布');
  const quoteSnap = orig && { author: orig.author, time: orig.time, text: orig.text, media: orig.media };
  const titleText = mode === 'reply' ? (isX ? 'Reply' : '评论')
    : mode === 'quote' ? (isX ? 'Quote Post' : '引用')
    : mode === 'repost' ? (isX ? 'Repost' : '转发')
    : (isX ? 'New Post' : '发新微博');
  const MacWindow = window.MacWindow;
  const disclosureOn = disclosure.paid || disclosure.ai;
  const flagCustom = <svg viewBox="0 0 20 20" width="100%" height="100%"><g fill="currentColor"><path d="M5 2.5a.8.8 0 0 1 .8.8v.36c1.9-.83 3.45.55 5.12.55.86 0 1.62-.27 2.3-.66a.72.72 0 0 1 1.08.62v5.92a.72.72 0 0 1-.37.63c-.78.44-1.66.81-2.66.81-1.74 0-3.3-1.39-5.07-.58a.2.2 0 0 0-.13.18v5.84a.8.8 0 0 1-1.6 0V3.3A.8.8 0 0 1 5 2.5Z" /></g></svg>;

  return (
    <React.Fragment>
      <MacWindow title={titleText} onClose={onClose} width={560}>
        <div className="col-scroll" style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column' }}>
          {/* scheduled banner */}
          {scheduledAt && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '11px 16px', borderBottom: '1px solid var(--border-default)', color: 'var(--accent)' }}>
              <SchedGlyph size={19} />
              <span style={{ flex: 1, fontSize: 14, fontWeight: 600, fontFamily: 'var(--font-sans)' }}>{isX ? `Will send on ${fmtWhen(scheduledAt, true)}` : `将于 ${fmtWhen(scheduledAt, false)} 发送`}</span>
              <button onClick={() => setDialog('schedule')} style={{ height: 28, padding: '0 12px', borderRadius: 9999, border: '1px solid var(--border-default)', background: 'var(--bg-base)', color: 'var(--fg-body)', fontSize: 12.5, fontWeight: 700, cursor: 'pointer', fontFamily: 'var(--font-sans)' }}>{isX ? 'Edit' : '修改'}</button>
              <button onClick={() => setScheduledAt(null)} title={isX ? 'Cancel schedule' : '取消定时'} style={{ width: 28, height: 28, borderRadius: '50%', border: 'none', background: 'transparent', color: 'var(--fg-subdued)', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}><Glyph name="close" size={15} /></button>
            </div>
          )}
          {/* original post being replied to */}
          {mode === 'reply' && orig && <ReplyRefBlock post={orig} isX={isX} />}
          {/* body */}
          <div style={{ display: 'flex', gap: 12, padding: mode === 'reply' ? '0 16px 6px' : '14px 16px 6px' }}>
            {mode === 'reply' ? (
              <div style={{ flex: 'none', width: 44, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                <div style={{ width: 2, height: 8, marginBottom: 4, background: 'var(--gray-400)', borderRadius: 1 }} />
                <PAvatar person={from} size={44} />
              </div>
            ) : (
              <PAvatar person={from} size={44} />
            )}
            <div style={{ flex: 1, minWidth: 0 }}>
              {/* posting context + account selector share one line */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10, position: 'relative' }}>
                {mode === 'reply' ? (
                  <span style={{ fontSize: 13.5, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>
                    {isX ? 'Replying to ' : '回复 '}<span style={{ color: 'var(--accent)' }}>@{orig.author.handle || orig.author.name}</span>
                  </span>
                ) : (
                  <div style={{ position: 'relative' }}>
                    <button onClick={() => setScopeMenu(m => !m)} title={isX ? 'Who can reply?' : '谁可以回复？'}
                      style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 26, padding: '0 10px', borderRadius: 9999, border: '1px solid var(--border-default)', background: 'var(--bg-base)', color: 'var(--accent)', fontSize: 12.5, fontWeight: 600, fontFamily: 'var(--font-sans)', cursor: 'pointer' }}>
                      <span style={{ display: 'inline-flex', width: 14, height: 14 }}>{scopeIcon(REPLY_SCOPES.find(s => s.id === replyScope).icon, 14)}</span>
                      {scopeLabel(replyScope, isX)}{isX ? ' can reply' : ' 可回复'}
                    </button>
                    {scopeMenu && <ReplyScopeMenu value={replyScope} onPick={setReplyScope} onClose={() => setScopeMenu(false)} isX={isX} />}
                  </div>
                )}
                <div style={{ flex: 1 }} />
                {/* account selector */}
                <button onClick={() => setMenu(m => !m)} title={isX ? 'Posting as' : '发布身份'}
                  style={{ display: 'inline-flex', alignItems: 'center', gap: 5, height: 30, padding: '0 7px 0 11px', borderRadius: 9999, border: '1px solid var(--border-default)', background: 'var(--bg-base)', cursor: 'pointer', fontFamily: 'var(--font-sans)', flex: 'none' }}>
                  <span style={{ fontSize: 13, fontWeight: 700, color: 'var(--fg-heading)', whiteSpace: 'nowrap' }}>{isX ? '@' + from.handle : from.name}</span>
                  <span style={{ display: 'inline-flex', width: 15, height: 15, color: 'var(--fg-subdued)' }}><Glyph name="chevron-down" size={15} /></span>
                </button>
                {menu && (
                  <div style={{ position: 'absolute', top: 36, right: 0, width: 248, background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', borderRadius: 12, boxShadow: 'var(--shadow-elevated)', padding: 6, zIndex: 60 }}>
                    {accounts.map(a => (
                      <button key={a.id} onClick={() => { onChangeFrom(a.id); setMenu(false); }} style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%', padding: '7px 8px', borderRadius: 8, border: 'none', background: a.id === fromId ? 'var(--gray-100)' : 'transparent', cursor: 'pointer', textAlign: 'left' }}>
                        <PAvatar person={a} size={30} />
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ fontSize: 13.5, fontWeight: 700, color: 'var(--fg-heading)', fontFamily: 'var(--font-sans)' }}>{a.name}</div>
                          <div style={{ fontSize: 12, color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)' }}>{a.platform === 'x' ? '@' + a.handle + ' · X' : '微博'}</div>
                        </div>
                        {a.id === fromId && <span style={{ display: 'inline-flex', width: 16, height: 16, color: 'var(--accent)' }}><Glyph name="checkmark" size={16} /></span>}
                      </button>
                    ))}
                  </div>
                )}
              </div>

              {/* textarea + autocomplete */}
              <div style={{ position: 'relative' }}>
                <textarea ref={taRef} value={text} onChange={onText} onKeyDown={onTaKey} onKeyUp={syncCaret} onClick={syncCaret} onSelect={syncCaret} rows={mode ? 3 : 4}
                  placeholder={placeholder}
                  style={{ width: '100%', minHeight: mode ? 84 : 110, resize: 'none', border: 'none', outline: 'none', background: 'none', fontSize: 19, lineHeight: 1.45, fontFamily: 'var(--font-sans)', color: 'var(--fg-body)', boxSizing: 'border-box' }} />
                {acOpen && <AutoComplete tok={tok} platform={from.platform} hi={acHi} onPick={pickAuto} onHover={setAcHi} />}
              </div>

              {/* disclosure chips */}
              {disclosureOn && (
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 4, marginBottom: 2 }}>
                  {disclosure.paid && <ComposeChip isX={isX} label={isX ? 'Paid partnership' : '付费合作'} onRemove={() => setDisclosure(d => ({ ...d, paid: false }))} icon={<Glyph name="info" size={13} />} />}
                  {disclosure.ai && <ComposeChip isX={isX} label={isX ? 'Made with AI' : 'AI 生成'} onRemove={() => setDisclosure(d => ({ ...d, ai: false }))} icon={<Glyph name="sparkle" size={13} />} />}
                </div>
              )}

              {/* images */}
              <ImageGrid images={images} onRemove={removeImg} onEdit={(id, tab) => setEditing({ id, tab })} isX={isX} />

              {/* poll */}
              {poll && <PollEditor poll={poll} setPoll={setPoll} onRemove={() => setPoll(null)} isX={isX} />}

              {(mode === 'quote' || mode === 'repost') && quoteSnap && <QuotePost q={quoteSnap} />}
            </div>
          </div>

          {/* footer */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 2, padding: '8px 14px 12px', borderTop: '1px solid var(--border-default)', marginTop: 6, position: 'sticky', bottom: 0, background: 'var(--bg-elevated)' }}>
            <input ref={fileRef} type="file" accept="image/*" multiple onChange={e => { addFiles(e.target.files); e.target.value = ''; }} style={{ display: 'none' }} />
            <ComposeTool name="image" title={isX ? 'Add image' : '图片'} onClick={() => fileRef.current && fileRef.current.click()} disabled={!!poll || images.length >= 4} active={images.length > 0} />
            <ComposeTool name="poll" title={isX ? 'Poll' : '投票'} onClick={togglePoll} disabled={images.length > 0} active={!!poll} />
            <ComposeTool name="emoji" title={isX ? 'Emoji' : '表情'} onClick={() => { const ta = taRef.current; const e = isX ? '🙂' : '😀'; const c = caret; const nt = text.slice(0, c) + e + text.slice(c); setText(nt); requestAnimationFrame(() => { if (ta) { ta.focus(); ta.setSelectionRange(c + e.length, c + e.length); } setCaret(c + e.length); }); }} />
            <ComposeTool name="calendar" title={isX ? 'Schedule' : '定时发布'} onClick={() => setDialog('schedule')} active={!!scheduledAt} />
            <ComposeTool name="location" title={isX ? 'Location' : '位置'} />
            <ComposeTool custom={flagCustom} title={isX ? 'Content disclosure' : '内容披露'} onClick={() => setDialog('disclosure')} active={disclosureOn} />
            <div style={{ flex: 1 }} />
            <CharRing used={used} limit={limit} threshold={ringThreshold} />
            <div style={{ width: 1, height: 26, background: 'var(--border-default)', margin: '0 12px 0 10px' }} />
            <PostBtn disabled={!canPost} onClick={submit} label={label} />
          </div>
        </div>
      </MacWindow>

      {dialog === 'schedule' && <ScheduleDialog isX={isX} initial={scheduledAt} onConfirm={confirmSchedule} onClose={() => setDialog(null)} onOpenDrafts={() => setDialog('drafts')} />}
      {dialog === 'disclosure' && <DisclosureDialog isX={isX} value={disclosure} onChange={setDisclosure} onClose={() => setDialog(null)} />}
      {dialog === 'drafts' && <DraftsDialog isX={isX} onClose={() => setDialog('schedule')} />}
      {editingImg && <MediaEditor image={{ ...editingImg, _tab: editing.tab }} isX={isX} onClose={() => setEditing(null)} onSave={(patch) => { applyEdit(editing.id, patch); setEditing(null); }} />}
    </React.Fragment>
  );
}

function PostBtn({ disabled, onClick, label }) {
  const [h, setH] = React.useState(false);
  const [p, setP] = React.useState(false);
  return (
    <button onClick={onClick} disabled={disabled}
      onMouseEnter={() => setH(true)} onMouseLeave={() => { setH(false); setP(false); }}
      onMouseDown={() => setP(true)} onMouseUp={() => setP(false)}
      style={{ height: 36, padding: '0 20px', borderRadius: 9999, border: 'none', fontFamily: 'var(--font-sans)', fontWeight: 700, fontSize: 15, cursor: disabled ? 'default' : 'pointer',
        background: disabled ? 'var(--gray-100)' : (h ? 'var(--accent-bg-hover)' : 'var(--accent-bg)'), color: disabled ? 'var(--fg-disabled)' : '#fff',
        transform: p && !disabled ? 'scale(0.96)' : 'scale(1)', transition: 'all .13s var(--ease-default)' }}>{label}</button>
  );
}

Object.assign(window, { Compose });

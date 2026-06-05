/* Shared media viewer — opens as its own floating macOS window (reuses the
   MacWindow chrome from addaccount.jsx). Plays videos and shows images in ONE
   player; arrow keys / on-screen chevrons / the filmstrip switch between slides
   horizontally. Videos auto-play muted, matching the timeline. */

function parseDur(s) {
  if (!s) return 30;
  const m = String(s).split(':').map(n => parseInt(n, 10) || 0);
  return m.length === 2 ? m[0] * 60 + m[1] : m[0];
}
function fmtTime(sec) {
  sec = Math.max(0, Math.floor(sec));
  const m = Math.floor(sec / 60), s = sec % 60;
  return m + ':' + String(s).padStart(2, '0');
}

/* Render a slide's gradient to a canvas so download/copy produce a real file. */
function slideCanvas(slide, w = 1280, h = 720) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const ctx = c.getContext('2d');
  const g = ctx.createLinearGradient(0, 0, w, h);
  g.addColorStop(0, slide.grad[0]); g.addColorStop(1, slide.grad[1]);
  ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  return c;
}
function downloadSlide(slide, name) {
  try {
    slideCanvas(slide).toBlob((b) => {
      const url = URL.createObjectURL(b);
      const a = document.createElement('a');
      a.href = url; a.download = (name || (slide.kind === 'video' ? 'perch-video' : 'perch-photo')) + '.png';
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1500);
    });
  } catch (e) { /* no-op */ }
}
async function copySlideImage(slide) {
  try {
    const blob = await new Promise(r => slideCanvas(slide).toBlob(r));
    await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
    return true;
  } catch (e) { return false; }
}
async function copyText(t) {
  try { await navigator.clipboard.writeText(t); return true; } catch (e) { return false; }
}

function ViewerIconBtn({ name, size = 20, onClick, title, big }) {
  const [h, setH] = React.useState(false);
  const d = big ? 48 : 38;
  return (
    <button onClick={onClick} title={title} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ width: d, height: d, borderRadius: '50%', border: 'none', flex: 'none', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', background: h ? 'rgba(255,255,255,.22)' : 'rgba(255,255,255,.12)', color: '#fff', backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)', transition: 'background .12s, transform .12s', transform: h ? 'scale(1.05)' : 'scale(1)' }}>
      <span style={{ display: 'inline-flex', width: size, height: size, marginLeft: name === 'play' ? 2 : 0 }}><Glyph name={name} size={size} /></span>
    </button>
  );
}

/* Small pill button used inside the download status surface (Retry / etc). */
function StatusBtn({ label, icon, onClick, primary }) {
  const [h, setH] = React.useState(false);
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 28, padding: '0 13px', borderRadius: 9999, border: 'none', cursor: 'pointer', fontFamily: 'var(--font-sans)', fontSize: 12.5, fontWeight: 700, whiteSpace: 'nowrap', flex: 'none', color: '#fff', background: primary ? (h ? 'var(--accent-bg-hover)' : 'var(--accent-bg)') : (h ? 'rgba(255,255,255,.26)' : 'rgba(255,255,255,.16)'), transition: 'background .12s' }}>
      {icon && <span style={{ display: 'inline-flex', width: 14, height: 14 }}><Glyph name={icon} size={14} /></span>}
      {label}
    </button>
  );
}

function MiniClose({ onClick, title }) {
  const [h, setH] = React.useState(false);
  return (
    <button onClick={onClick} title={title} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ width: 24, height: 24, borderRadius: '50%', border: 'none', flex: 'none', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', background: h ? 'rgba(255,255,255,.2)' : 'transparent', color: '#fff', transition: 'background .12s' }}>
      <span style={{ display: 'inline-flex', width: 14, height: 14 }}><Glyph name="close" size={14} /></span>
    </button>
  );
}

function ShareItem({ icon, label, onClick }) {
  const [h, setH] = React.useState(false);
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 11, width: '100%', padding: '8px 10px', borderRadius: 9, border: 'none', cursor: 'pointer', background: h ? 'var(--gray-100)' : 'transparent', color: 'var(--fg-body)', fontSize: 13.5, fontWeight: 600, fontFamily: 'var(--font-sans)', textAlign: 'left' }}>
      <span style={{ display: 'inline-flex', width: 18, height: 18, color: 'var(--fg-subdued)', flex: 'none' }}><Glyph name={icon} size={18} /></span>
      {label}
    </button>
  );
}

function MediaViewer({ slides, index = 0, author, onClose }) {
  const n = slides.length;
  const [idx, setIdx] = React.useState(Math.max(0, Math.min(index, n - 1)));
  const cur = slides[idx] || {};
  const isVideo = cur.kind === 'video';
  const isX = author && author.platform === 'x';

  const [feedback, setFeedback] = React.useState(null);
  const [shareOpen, setShareOpen] = React.useState(false);
  const [altOpen, setAltOpen] = React.useState(false);
  const [chrome, setChrome] = React.useState(false);  // hover reveals viewer chrome
  const [dl, setDl] = React.useState(null);  // { state:'downloading'|'success'|'error', pct, reason }
  const chromeOn = chrome || shareOpen || altOpen || !!dl;
  const fbTimer = React.useRef(null);
  const dlTimer = React.useRef(null);
  const dlDismiss = React.useRef(null);
  const toast = (msg) => { setFeedback(msg); clearTimeout(fbTimer.current); fbTimer.current = setTimeout(() => setFeedback(null), 1900); };

  const link = (isX ? 'https://x.com/' : 'https://weibo.com/') + ((author && author.handle) || 'media') + '/status';
  const fileName = (isVideo ? 'perch-video' : 'perch-photo') + '.png';

  // Simulated download with determinate progress; sometimes fails so we can show
  // a recoverable error with a reason + retry. The real file save fires at 100%.
  const failReasons = isX
    ? ['Network connection lost. Check your connection and try again.',
       'Server didn\u2019t respond (503). The media server is busy.',
       'Couldn\u2019t reach Perch media servers. Try again in a moment.']
    : ['\u7f51\u7edc\u8fde\u63a5\u4e2d\u65ad\uff0c\u8bf7\u68c0\u67e5\u7f51\u7edc\u540e\u91cd\u8bd5\u3002',
       '\u670d\u52a1\u5668\u65e0\u54cd\u5e94 (503)\uff0c\u5a92\u4f53\u670d\u52a1\u5668\u7e41\u5fd9\u3002',
       '\u65e0\u6cd5\u8fde\u63a5\u5230 Perch \u5a92\u4f53\u670d\u52a1\u5668\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002'];

  const stopDownload = () => { clearInterval(dlTimer.current); clearTimeout(dlDismiss.current); };
  const runDownload = () => {
    stopDownload();
    setShareOpen(false);
    const slide = cur;
    const willFail = Math.random() < 0.3;
    const failAt = 32 + Math.random() * 44;
    let pct = 0;
    setDl({ state: 'downloading', pct: 0 });
    dlTimer.current = setInterval(() => {
      pct += 4 + Math.random() * 11;
      if (willFail && pct >= failAt) {
        clearInterval(dlTimer.current);
        setDl({ state: 'error', pct: Math.floor(failAt), reason: failReasons[Math.floor(Math.random() * failReasons.length)] });
        return;
      }
      if (pct >= 100) {
        clearInterval(dlTimer.current);
        downloadSlide(slide);
        setDl({ state: 'success', pct: 100 });
        dlDismiss.current = setTimeout(() => setDl(null), 2400);
        return;
      }
      setDl({ state: 'downloading', pct: Math.floor(pct) });
    }, 90);
  };
  const cancelDownload = () => { stopDownload(); setDl(null); };
  const onDownload = runDownload;
  const onCopy = async () => {
    if (isVideo) { await copyText(link); toast(isX ? 'Link copied' : '已复制链接'); }
    else { await copySlideImage(cur); toast(isX ? 'Image copied' : '已复制图片'); }
    setShareOpen(false);
  };
  const onCopyLink = async () => { await copyText(link); toast(isX ? 'Link copied' : '已复制链接'); setShareOpen(false); };
  const onShareTo = (where) => { toast((isX ? 'Shared to ' : '已分享到') + where); setShareOpen(false); };

  const go = (d) => setIdx(i => (i + d + n) % n);

  // close transient UI when the active slide changes (VideoPlayer remounts per slide)
  React.useEffect(() => { setAltOpen(false); setShareOpen(false); stopDownload(); setDl(null); }, [idx]);
  // clear any pending timers on unmount
  React.useEffect(() => () => { stopDownload(); clearTimeout(fbTimer.current); }, []);

  // keyboard: ←/→ switch, Esc close (the shared player owns space / play-pause)
  React.useEffect(() => {
    const onKey = (e) => {
      if (e.key === 'Escape') { onClose(); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); go(1); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); go(-1); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [n]);

  const title = author ? author.name : (isX ? 'Media' : '媒体');
  const W = 860, H = 624;

  return (
    <React.Fragment>
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, background: 'rgba(8,7,11,.55)', zIndex: 88 }} />
      <MacWindow title={title} onClose={onClose} width={W} height={H}>
        <div onMouseEnter={() => setChrome(true)} onMouseLeave={() => setChrome(false)}
          style={{ display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0, background: '#0b0a0e' }}>
          {/* stage */}
          <div style={{ position: 'relative', flex: 1, minHeight: 0, overflow: 'hidden' }}>
            <div style={{ display: 'flex', height: '100%', width: (n * 100) + '%', transform: 'translateX(-' + (idx * (100 / n)) + '%)', transition: 'transform .34s var(--ease-default)' }}>
              {slides.map((s, i) => {
                const active = i === idx;
                const vid = s.kind === 'video';
                return (
                  <div key={i} style={{ flex: '0 0 ' + (100 / n) + '%', height: '100%', position: 'relative', overflow: 'hidden', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    {vid && active ? (
                      <VideoPlayer key={'vp' + idx} grad={s.grad} dur={s.dur} isX={isX} variant="window" />
                    ) : s.url ? (
                      <img src={s.url} alt={s.alt || ''} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'contain' }} />
                    ) : (
                      <div className={vid ? 'perch-vid-anim' : (active ? 'perch-img-zoom' : undefined)} style={{ position: 'absolute', inset: 0, background: 'linear-gradient(135deg, ' + s.grad[0] + ', ' + s.grad[1] + ')' }} />
                    )}
                  </div>
                );
              })}
            </div>

            {/* counter — top-left */}
            {n > 1 && (
              <div style={{ position: 'absolute', top: 12, left: 12, height: 26, padding: '0 11px', borderRadius: 9999, background: 'rgba(0,0,0,.5)', color: '#fff', fontSize: 12.5, fontWeight: 700, fontFamily: 'var(--font-sans)', display: 'flex', alignItems: 'center', backdropFilter: 'blur(6px)', WebkitBackdropFilter: 'blur(6px)', fontVariantNumeric: 'tabular-nums', opacity: chromeOn ? 1 : 0, transition: 'opacity .18s var(--ease-default)', pointerEvents: 'none', zIndex: 6 }}>{idx + 1} / {n}</div>
            )}

            {/* prev / next — hover-revealed */}
            {n > 1 && (
              <div style={{ opacity: chromeOn ? 1 : 0, transition: 'opacity .18s var(--ease-default)', pointerEvents: chromeOn ? 'auto' : 'none' }}>
                <div style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%) rotate(90deg)' }}>
                  <ViewerIconBtn name="chevron-down" size={22} onClick={() => go(-1)} title={isX ? 'Previous' : '上一个'} big />
                </div>
                <div style={{ position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%) rotate(-90deg)' }}>
                  <ViewerIconBtn name="chevron-down" size={22} onClick={() => go(1)} title={isX ? 'Next' : '下一个'} big />
                </div>
              </div>
            )}

            {/* actions: download · copy (images only) · share — top-right, hover-revealed */}
            <div style={{ position: 'absolute', top: 12, right: 12, display: 'flex', gap: 8, opacity: chromeOn ? 1 : 0, transition: 'opacity .18s var(--ease-default)', pointerEvents: chromeOn ? 'auto' : 'none', zIndex: 6 }}>
              <ViewerIconBtn name="download" size={19} onClick={onDownload} title={isX ? 'Download' : '下载'} />
              {!isVideo && (
                <ViewerIconBtn name="copy" size={18} onClick={onCopy} title={isX ? 'Copy image' : '复制图片'} />
              )}
              <div style={{ position: 'relative' }}>
                <ViewerIconBtn name="share" size={18} onClick={() => setShareOpen(o => !o)} title={isX ? 'Share' : '分享'} />
                {shareOpen && (
                  <React.Fragment>
                    <div onClick={() => setShareOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 1 }} />
                    <div style={{ position: 'absolute', top: 46, right: 0, width: 204, background: 'var(--bg-elevated)', border: '1px solid var(--border-default)', borderRadius: 12, boxShadow: 'var(--shadow-elevated)', padding: 6, zIndex: 2 }}>
                      <ShareItem icon="link" label={isX ? 'Copy link' : '复制链接'} onClick={onCopyLink} />
                      <ShareItem icon="download" label={isX ? 'Save to Downloads' : '保存到下载'} onClick={onDownload} />
                      <div style={{ height: 1, background: 'var(--border-default)', margin: '5px 8px' }} />
                      <ShareItem icon="share" label={isX ? 'Messages' : '信息'} onClick={() => onShareTo(isX ? 'Messages' : '信息')} />
                      <ShareItem icon="globe" label={isX ? 'Mail' : '邮件'} onClick={() => onShareTo(isX ? 'Mail' : '邮件')} />
                    </div>
                  </React.Fragment>
                )}
              </div>
            </div>

            {/* ALT description (images) */}
            {!isVideo && cur.alt && (
              <div style={{ position: 'absolute', left: 12, bottom: 12, maxWidth: 'min(72%, 520px)' }}>
                {altOpen && (
                  <div style={{ marginBottom: 8, padding: '10px 13px', borderRadius: 10, background: 'rgba(15,14,20,.92)', color: '#fff', fontSize: 13.5, lineHeight: 1.5, fontFamily: 'var(--font-sans)', backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)', boxShadow: '0 8px 24px rgba(0,0,0,.45)' }}>{cur.alt}</div>
                )}
                <button onClick={() => setAltOpen(o => !o)} title={isX ? 'Image description' : '图片描述'}
                  style={{ height: 24, padding: '0 9px', borderRadius: 6, border: 'none', cursor: 'pointer', background: altOpen ? '#fff' : 'rgba(0,0,0,.6)', color: altOpen ? '#15141a' : '#fff', fontSize: 11, fontWeight: 800, letterSpacing: '.04em', fontFamily: 'var(--font-sans)', backdropFilter: 'blur(4px)', WebkitBackdropFilter: 'blur(4px)' }}>ALT</button>
              </div>
            )}

            {/* action feedback (copy / share / link) */}
            {feedback && !dl && (
              <div style={{ position: 'absolute', left: '50%', bottom: isVideo ? 76 : 18, transform: 'translateX(-50%)', display: 'flex', alignItems: 'center', gap: 8, height: 38, padding: '0 16px', borderRadius: 9999, background: 'rgba(15,14,20,.94)', color: '#fff', fontSize: 13.5, fontWeight: 600, fontFamily: 'var(--font-sans)', boxShadow: '0 8px 24px rgba(0,0,0,.4)', backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)', zIndex: 5, whiteSpace: 'nowrap' }}>
                <span style={{ display: 'inline-flex', width: 17, height: 17, color: 'var(--green-700)' }}><Glyph name="checkmark-circle" size={17} /></span>
                {feedback}
              </div>
            )}

            {/* download status — progress / success / error */}
            {dl && (
              <div style={{ position: 'absolute', left: '50%', bottom: isVideo ? 76 : 18, transform: 'translateX(-50%)', width: dl.state === 'downloading' ? 360 : 'auto', maxWidth: 'calc(100% - 24px)', background: 'rgba(15,14,20,.95)', color: '#fff', borderRadius: 14, border: dl.state === 'error' ? '1px solid rgba(255,107,107,.5)' : '1px solid rgba(255,255,255,.1)', boxShadow: '0 10px 30px rgba(0,0,0,.5)', backdropFilter: 'blur(10px)', WebkitBackdropFilter: 'blur(10px)', fontFamily: 'var(--font-sans)', zIndex: 7, padding: dl.state === 'downloading' ? '12px 14px' : '11px 13px', animation: 'bmPop .14s var(--ease-default)' }}>

                {dl.state === 'downloading' && (
                  <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                    <span style={{ display: 'inline-flex', width: 19, height: 19, color: 'rgba(255,255,255,.85)', flex: 'none' }}><Glyph name={isVideo ? 'image' : 'image'} size={19} /></span>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 10, marginBottom: 7 }}>
                        <span style={{ fontSize: 12.5, fontWeight: 700, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{isX ? 'Downloading' : '\u6b63\u5728\u4e0b\u8f7d'} {fileName}</span>
                        <span style={{ fontSize: 12, fontWeight: 700, color: 'rgba(255,255,255,.75)', fontVariantNumeric: 'tabular-nums', flex: 'none' }}>{dl.pct}%</span>
                      </div>
                      <div style={{ height: 5, borderRadius: 9999, background: 'rgba(255,255,255,.18)', overflow: 'hidden' }}>
                        <div style={{ height: '100%', width: dl.pct + '%', borderRadius: 9999, background: 'var(--accent-bg)', transition: 'width .14s linear' }} />
                      </div>
                    </div>
                    <MiniClose onClick={cancelDownload} title={isX ? 'Cancel' : '\u53d6\u6d88'} />
                  </div>
                )}

                {dl.state === 'success' && (
                  <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '1px 3px' }}>
                    <span style={{ display: 'inline-flex', width: 18, height: 18, color: 'var(--green-700)', flex: 'none' }}><Glyph name="checkmark-circle" size={18} /></span>
                    <span style={{ fontSize: 13.5, fontWeight: 600, whiteSpace: 'nowrap' }}>{isX ? 'Saved to Downloads' : '\u5df2\u4fdd\u5b58\u5230\u4e0b\u8f7d'}</span>
                  </div>
                )}

                {dl.state === 'error' && (
                  <div style={{ display: 'flex', alignItems: 'flex-start', gap: 11, maxWidth: 420 }}>
                    <span style={{ display: 'inline-flex', width: 19, height: 19, color: 'var(--red-700)', flex: 'none', marginTop: 1 }}><Glyph name="info" size={19} /></span>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 2 }}>{isX ? 'Download failed' : '\u4e0b\u8f7d\u5931\u8d25'}</div>
                      <div style={{ fontSize: 12.5, fontWeight: 500, lineHeight: 1.45, color: 'rgba(255,255,255,.72)', textWrap: 'pretty' }}>{dl.reason}</div>
                      <div style={{ display: 'flex', gap: 8, marginTop: 11 }}>
                        <StatusBtn label={isX ? 'Retry' : '\u91cd\u8bd5'} icon="refresh" onClick={runDownload} primary />
                        <StatusBtn label={isX ? 'Dismiss' : '\u5173\u95ed'} onClick={() => setDl(null)} />
                      </div>
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>


        </div>
      </MacWindow>
    </React.Fragment>
  );
}

Object.assign(window, { MediaViewer });

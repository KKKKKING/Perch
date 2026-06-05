/* Add-account workflow — platform picker → in-app browser login → OAuth authorize.
   The Perch chrome (picker + browser frame) uses Spectrum 2 tokens. The *pages*
   inside the browser are the real branded sites (X = black/white, Weibo = red),
   rendered as a webview would show them. New accounts are minted on authorize. */

const AA_NEW_COLORS = ['var(--cyan-700)', 'var(--purple-700)', 'var(--turquoise-800)', 'var(--celery-800)', 'var(--pink-700)', 'var(--seafoam-700)', 'var(--indigo-700)', 'var(--chartreuse-800)'];

function aaNameFromHandle(h) {
  const base = String(h || '').replace(/^@/, '').split(/[._\-\/\s]+/).filter(Boolean);
  if (!base.length) return 'New account';
  return base.slice(0, 2).map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
}

function aaMakeAccount({ platform, handle, name, verified = false, followers, following }) {
  return {
    id: (platform === 'x' ? 'axn' : 'awn') + Date.now().toString(36),
    name, handle: String(handle || '').replace(/^@/, ''), platform,
    color: AA_NEW_COLORS[Math.floor(Math.random() * AA_NEW_COLORS.length)],
    verified,
    followers: followers || (platform === 'x' ? '128' : '86'),
    following: following || (platform === 'x' ? '312' : '164'),
    unread: 0,
  };
}

/* ── A convincing faux QR code (deterministic finder squares + noise field) ── */
function FauxQR({ size = 176 }) {
  const N = 25;
  const cells = React.useMemo(() => {
    const out = [];
    let s = 20260601;
    const rnd = () => { s = (s * 9301 + 49297) % 233280; return s / 233280; };
    const finder = (r, c) => {
      const box = (br, bc) => { if (r < br || r >= br + 7 || c < bc || c >= bc + 7) return null; const lr = r - br, lc = c - bc; return (lr === 0 || lr === 6 || lc === 0 || lc === 6) || (lr >= 2 && lr <= 4 && lc >= 2 && lc <= 4); };
      const a = box(0, 0); if (a !== null) return a;
      const b = box(0, N - 7); if (b !== null) return b;
      const d = box(N - 7, 0); if (d !== null) return d;
      return undefined;
    };
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
      const f = finder(r, c);
      out.push(f === undefined ? rnd() > 0.52 : f);
    }
    return out;
  }, []);
  return (
    <div style={{ position: 'relative', width: size, height: size, background: '#fff', borderRadius: 10, padding: 10, boxSizing: 'border-box', boxShadow: 'inset 0 0 0 1px rgba(0,0,0,.06)' }}>
      <div style={{ width: '100%', height: '100%', display: 'grid', gridTemplateColumns: `repeat(${N}, 1fr)`, gridTemplateRows: `repeat(${N}, 1fr)` }}>
        {cells.map((on, i) => <div key={i} style={{ background: on ? '#15141a' : 'transparent' }} />)}
      </div>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none' }}>
        <div style={{ width: size * 0.2, height: size * 0.2, borderRadius: 7, background: '#e6162d', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 0 0 3px #fff', color: '#fff', fontWeight: 800, fontSize: size * 0.11 }}>微</div>
      </div>
    </div>
  );
}

/* ── macOS window chrome: draggable title bar + functional traffic lights ── */
function MacTraffic({ onClose }) {
  const [h, setH] = React.useState(false);
  const dot = (bg, fn, sym) => (
    <button onClick={fn || undefined} onMouseDown={e => e.stopPropagation()}
      style={{ width: 12, height: 12, borderRadius: '50%', border: 'none', padding: 0, background: bg, cursor: fn ? 'pointer' : 'default', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', boxShadow: 'inset 0 0 0 .5px rgba(0,0,0,.22)', color: 'rgba(0,0,0,.55)', fontSize: 8.5, fontWeight: 900, lineHeight: 1, flex: 'none' }}>
      {h && sym ? sym : ''}
    </button>
  );
  return (
    <div onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
      {dot('#ff5f57', onClose, '✕')}
      {dot('#febc2e', null, '–')}
      {dot('#28c840', null, '+')}
    </div>
  );
}

function MacWindow({ title, onClose, width, height, children }) {
  const [off, setOff] = React.useState({ x: 0, y: 0 });
  const startDrag = (e) => {
    if (e.button !== 0) return;
    const sx = e.clientX, sy = e.clientY, bx = off.x, by = off.y;
    const move = (ev) => setOff({ x: bx + (ev.clientX - sx), y: by + (ev.clientY - sy) });
    const up = () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up); document.body.style.userSelect = ''; };
    document.body.style.userSelect = 'none';
    window.addEventListener('mousemove', move); window.addEventListener('mouseup', up);
  };
  return (
    <div style={{ position: 'fixed', left: '50%', top: '50%', transform: `translate(-50%, -50%) translate(${off.x}px, ${off.y}px)`, width, maxWidth: '94vw', height, maxHeight: '90vh', zIndex: 90, display: 'flex', flexDirection: 'column', background: 'var(--bg-elevated)', borderRadius: 12, border: '1px solid var(--border-default)', boxShadow: '0 0 0 1px rgba(0,0,0,.28), 0 32px 84px rgba(0,0,0,.52)', overflow: 'hidden', animation: 'winPop .2s var(--ease-default)' }}>
      <div onMouseDown={startDrag} style={{ height: 38, flex: 'none', position: 'relative', display: 'flex', alignItems: 'center', padding: '0 14px', borderBottom: '1px solid var(--border-default)', background: 'var(--bg-layer-1)' }}>
        <MacTraffic onClose={onClose} />
        <div style={{ position: 'absolute', left: 64, right: 64, textAlign: 'center', fontSize: 13, fontWeight: 700, color: 'var(--fg-heading)', letterSpacing: '-.01em', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', pointerEvents: 'none' }}>{title}</div>
      </div>
      <div style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>{children}</div>
    </div>
  );
}

/* ── In-app browser body (nav + address bar + content well), fills its window ── */
function BrowserBody({ url, secure = true, isX, onBack, busy, children }) {
  const navBtn = (glyph, fn, dim, title) => (
    <button onClick={fn} disabled={dim} title={title}
      onMouseEnter={e => { if (!dim) e.currentTarget.style.background = 'var(--gray-200)'; }} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
      style={{ width: 28, height: 28, borderRadius: 7, border: 'none', background: 'transparent', cursor: dim ? 'default' : 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: dim ? 'var(--fg-disabled)' : 'var(--fg-subdued)', flex: 'none' }}>
      <span style={{ display: 'inline-flex', width: 17, height: 17, transform: glyph === 'chevron-down' ? 'rotate(90deg)' : 'none' }}><Glyph name={glyph} size={17} /></span>
    </button>
  );
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0 }}>
      {/* toolbar */}
      <div style={{ height: 46, flex: 'none', display: 'flex', alignItems: 'center', gap: 6, padding: '0 10px', borderBottom: '1px solid var(--border-default)', background: 'var(--bg-base)' }}>
        {navBtn('chevron-down', onBack, false, isX ? 'Back' : '后退')}
        {navBtn('refresh', () => {}, false, isX ? 'Reload' : '刷新')}
        {/* address bar */}
        <div style={{ flex: 1, minWidth: 0, height: 32, borderRadius: 9999, background: 'var(--bg-layer-1)', border: '1px solid var(--border-default)', display: 'flex', alignItems: 'center', gap: 7, padding: '0 12px', margin: '0 2px' }}>
          <span style={{ display: 'inline-flex', width: 13, height: 13, color: secure ? 'var(--positive)' : 'var(--fg-subdued)', flex: 'none' }}><Glyph name={secure ? 'lock' : 'globe'} size={13} /></span>
          <span style={{ flex: 1, minWidth: 0, fontSize: 13, color: 'var(--fg-body)', fontFamily: 'var(--font-sans)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{url}</span>
          {busy && <span style={{ width: 13, height: 13, borderRadius: '50%', border: '2px solid var(--gray-300)', borderTopColor: 'var(--accent)', animation: 'aaSpin .7s linear infinite', flex: 'none' }} />}
        </div>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 5, height: 24, padding: '0 9px', borderRadius: 9999, background: 'var(--gray-100)', color: 'var(--fg-subdued)', fontSize: 11, fontWeight: 700, flex: 'none', letterSpacing: '.01em' }}>
          <span style={{ display: 'inline-flex', width: 12, height: 12 }}><Glyph name="lock" size={12} /></span>
          {isX ? 'In‑app' : '内置浏览器'}
        </div>
      </div>
      {/* page well */}
      <div className="col-scroll" style={{ flex: 1, minHeight: 0, overflowY: 'auto' }}>{children}</div>
    </div>
  );
}

/* ── shared bits for the branded pages ── */
function PerchAppIcon({ size = 56 }) {
  return (
    <div style={{ width: size, height: size, borderRadius: size * 0.26, background: 'linear-gradient(150deg, var(--blue-900), var(--purple-1100))', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 6px 18px rgba(59,99,251,.32), inset 0 0 0 1px rgba(255,255,255,.18)', flex: 'none' }}>
      <span style={{ fontFamily: 'var(--font-serif)', fontSize: size * 0.56, fontWeight: 700, color: '#fff', lineHeight: 1, marginTop: size * 0.03 }}>P</span>
    </div>
  );
}

function PermissionRow({ text, accent }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '7px 0' }}>
      <span style={{ width: 20, height: 20, borderRadius: '50%', background: accent, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>
        <span style={{ display: 'inline-flex', width: 13, height: 13, color: '#fff' }}><Glyph name="checkmark" size={13} /></span>
      </span>
      <span style={{ fontSize: 14, color: '#1a1a1a' }}>{text}</span>
    </div>
  );
}

/* ════════════════════════ X (Twitter) pages ════════════════════════ */
function XField({ value, onChange, placeholder, type = 'text', onEnter, autoFocus, readOnly }) {
  const ref = React.useRef(null);
  React.useEffect(() => { if (autoFocus) { const t = setTimeout(() => ref.current && ref.current.focus(), 70); return () => clearTimeout(t); } }, [autoFocus]);
  return (
    <input ref={ref} value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder} type={type} readOnly={readOnly}
      onKeyDown={e => { if (e.key === 'Enter' && onEnter) onEnter(); }}
      style={{ width: '100%', height: 54, boxSizing: 'border-box', borderRadius: 6, border: '1px solid #333639', background: readOnly ? '#16181c' : '#000', color: readOnly ? '#71767b' : '#e7e9ea', fontSize: 16, fontFamily: 'var(--font-sans)', padding: '0 12px', outline: 'none' }}
      onFocus={e => { if (!readOnly) e.target.style.borderColor = '#1d9bf0'; }} onBlur={e => e.target.style.borderColor = '#333639'} />
  );
}

function XPillButton({ label, onClick, disabled, light = true }) {
  return (
    <button onClick={onClick} disabled={disabled}
      style={{ width: '100%', height: 52, borderRadius: 9999, border: light ? 'none' : '1px solid #536471', cursor: disabled ? 'default' : 'pointer', fontFamily: 'var(--font-sans)', fontWeight: 700, fontSize: 16,
        background: light ? (disabled ? '#3a3a3c' : '#eff3f4') : 'transparent', color: light ? (disabled ? '#71767b' : '#0f1419') : '#e7e9ea', transition: 'opacity .12s' }}>{label}</button>
  );
}

function XLogin({ step, username, setUsername, password, setPassword, onNext, onLogin, identity }) {
  return (
    <div style={{ minHeight: '100%', background: '#000', display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '44px 24px 32px' }}>
      <div style={{ fontSize: 38, lineHeight: 1, color: '#fff', marginBottom: 30 }}>𝕏</div>
      <div style={{ width: '100%', maxWidth: 364 }}>
        {step === 'username' && (
          <React.Fragment>
            <h1 style={{ color: '#e7e9ea', fontSize: 27, fontWeight: 800, margin: '0 0 26px', letterSpacing: '-.01em' }}>Sign in to X</h1>
            <button style={{ width: '100%', height: 44, borderRadius: 9999, border: 'none', background: '#fff', color: '#0f1419', fontSize: 14.5, fontWeight: 700, fontFamily: 'var(--font-sans)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, marginBottom: 12 }}>
              <span style={{ fontSize: 16, fontWeight: 800, color: '#4285F4' }}>G</span> Sign in with Google
            </button>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, color: '#71767b', fontSize: 13, margin: '8px 0 16px' }}>
              <span style={{ flex: 1, height: 1, background: '#2f3336' }} /><span>or</span><span style={{ flex: 1, height: 1, background: '#2f3336' }} />
            </div>
            <div style={{ marginBottom: 18 }}><XField value={username} onChange={setUsername} placeholder="Phone, email, or username" onEnter={() => username.trim() && onNext()} autoFocus /></div>
            <XPillButton label="Next" onClick={onNext} disabled={!username.trim()} />
            <div style={{ color: '#71767b', fontSize: 14.5, marginTop: 26 }}>Don't have an account? <span style={{ color: '#1d9bf0', cursor: 'pointer' }}>Sign up</span></div>
          </React.Fragment>
        )}
        {step === 'password' && (
          <React.Fragment>
            <h1 style={{ color: '#e7e9ea', fontSize: 27, fontWeight: 800, margin: '0 0 22px', letterSpacing: '-.01em' }}>Enter your password</h1>
            <div style={{ marginBottom: 14 }}><XField value={'@' + username.replace(/^@/, '')} onChange={() => {}} readOnly /></div>
            <div style={{ marginBottom: 14 }}><XField value={password} onChange={setPassword} placeholder="Password" type="password" onEnter={onLogin} autoFocus /></div>
            <div style={{ color: '#1d9bf0', fontSize: 14, cursor: 'pointer', marginBottom: 28 }}>Forgot password?</div>
            <XPillButton label="Log in" onClick={onLogin} disabled={!password.length} />
          </React.Fragment>
        )}
      </div>
    </div>
  );
}

function XAuthorize({ identity, onAuthorize, onCancel, isX }) {
  return (
    <div style={{ minHeight: '100%', background: '#000', display: 'flex', justifyContent: 'center', padding: '0' }}>
      <div style={{ width: '100%', maxWidth: 600, background: '#fff', minHeight: '100%' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '20px 28px', borderBottom: '1px solid #eff3f4' }}>
          <PerchAppIcon size={52} />
          <div style={{ fontSize: 17, lineHeight: 1.3, color: '#0f1419' }}>
            <span style={{ fontWeight: 800 }}>Perch</span><br />
            <span style={{ color: '#536471', fontSize: 14.5 }}>wants to access your X account</span>
          </div>
        </div>
        <div style={{ padding: '22px 28px 28px' }}>
          {/* signed-in identity */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '11px 13px', borderRadius: 12, background: '#f7f9f9', marginBottom: 22 }}>
            <PAvatar person={identity} size={40} />
            <div style={{ minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 15, fontWeight: 800, color: '#0f1419' }}>{identity.name}{identity.verified && <Verified size={15} />}</div>
              <div style={{ fontSize: 13.5, color: '#536471' }}>@{identity.handle}</div>
            </div>
            <div style={{ marginLeft: 'auto', fontSize: 12.5, fontWeight: 700, color: '#00ba7c', display: 'inline-flex', alignItems: 'center', gap: 5 }}>
              <span style={{ width: 8, height: 8, borderRadius: '50%', background: '#00ba7c' }} /> Signed in
            </div>
          </div>
          <div style={{ fontSize: 15, fontWeight: 800, color: '#0f1419', marginBottom: 4 }}>Perch will be able to</div>
          <div style={{ marginBottom: 18 }}>
            {['See posts from your timeline and the accounts you follow', 'See your profile information and account settings', 'Post, repost, and like on your behalf', 'Follow and unfollow accounts for you'].map(t => <PermissionRow key={t} text={t} accent="#1d9bf0" />)}
          </div>
          <button onClick={onAuthorize} style={{ width: '100%', height: 50, borderRadius: 9999, border: 'none', background: '#0f1419', color: '#fff', fontSize: 16, fontWeight: 800, fontFamily: 'var(--font-sans)', cursor: 'pointer', marginBottom: 10 }}>Authorize app</button>
          <button onClick={onCancel} style={{ width: '100%', height: 50, borderRadius: 9999, border: '1px solid #cfd9de', background: '#fff', color: '#0f1419', fontSize: 16, fontWeight: 700, fontFamily: 'var(--font-sans)', cursor: 'pointer' }}>Cancel</button>
          <div style={{ fontSize: 12.5, color: '#536471', textAlign: 'center', marginTop: 16, lineHeight: 1.5 }}>Perch won't see your password. You can revoke access anytime in your X settings.</div>
        </div>
      </div>
    </div>
  );
}

/* ════════════════════════ Weibo pages ════════════════════════ */
function WeiboLogin({ tab, setTab, qrStage, onScan, onConfirm, wUser, setWUser, wPass, setWPass, onAccountLogin }) {
  const RED = '#e6162d';
  return (
    <div style={{ minHeight: '100%', background: '#f7f7f9', display: 'flex', flexDirection: 'column' }}>
      {/* weibo top bar */}
      <div style={{ height: 56, flex: 'none', background: '#fff', borderBottom: '1px solid #ececef', display: 'flex', alignItems: 'center', padding: '0 28px', gap: 10 }}>
        <span style={{ width: 26, height: 26, borderRadius: '50%', background: RED, color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, fontSize: 15 }}>微</span>
        <span style={{ fontSize: 18, fontWeight: 800, color: '#222', letterSpacing: '.02em' }}>微博</span>
        <span style={{ fontSize: 13, color: '#999', marginLeft: 2 }}>Weibo</span>
      </div>
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '24px' }}>
        <div style={{ width: 380, maxWidth: '100%', background: '#fff', borderRadius: 14, boxShadow: '0 8px 30px rgba(0,0,0,.08), 0 0 0 1px rgba(0,0,0,.04)', overflow: 'hidden' }}>
          {/* tabs */}
          <div style={{ display: 'flex', borderBottom: '1px solid #f0f0f2' }}>
            {[['qr', '扫码登录'], ['account', '账号登录']].map(([t, lbl]) => (
              <button key={t} onClick={() => setTab(t)} style={{ flex: 1, height: 50, border: 'none', background: 'transparent', cursor: 'pointer', fontFamily: 'var(--font-sans)', fontSize: 15, fontWeight: tab === t ? 800 : 600, color: tab === t ? RED : '#888', position: 'relative' }}>
                {lbl}
                {tab === t && <span style={{ position: 'absolute', bottom: 0, left: '50%', transform: 'translateX(-50%)', width: 28, height: 3, borderRadius: 3, background: RED }} />}
              </button>
            ))}
          </div>

          {tab === 'qr' && (
            <div style={{ padding: '28px 28px 30px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
              <div style={{ position: 'relative' }}>
                <FauxQR size={184} />
                {qrStage !== 'idle' && (
                  <div style={{ position: 'absolute', inset: 0, background: 'rgba(255,255,255,.93)', borderRadius: 10, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 12 }}>
                    <span style={{ width: 52, height: 52, borderRadius: '50%', background: '#e8faf0', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: '#00a854' }}><Glyph name="checkmark-circle" size={34} /></span>
                    <div style={{ fontSize: 15, fontWeight: 700, color: '#222' }}>扫描成功</div>
                    <div style={{ fontSize: 12.5, color: '#999' }}>请在手机上确认登录</div>
                  </div>
                )}
              </div>
              <div style={{ fontSize: 14.5, color: '#333', marginTop: 18, fontWeight: 600 }}>打开微博 App 扫一扫登录</div>
              <div style={{ fontSize: 12.5, color: '#aaa', marginTop: 5, textAlign: 'center', lineHeight: 1.5 }}>扫描成功后在手机端点击确认，<br />即可授权 Perch 使用此账号</div>
              {/* simulated phone action (stands in for the real handset) */}
              <div style={{ width: '100%', marginTop: 20, padding: '12px 14px', borderRadius: 12, background: '#fafafb', border: '1px dashed #e0e0e4', display: 'flex', alignItems: 'center', gap: 11 }}>
                <span style={{ width: 34, height: 34, borderRadius: 9, background: '#fff', border: '1px solid #ececef', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: '#bbb', flex: 'none' }}><Glyph name="user" size={18} /></span>
                <div style={{ flex: 1, minWidth: 0, fontSize: 12, color: '#999' }}>{qrStage === 'idle' ? '模拟手机端操作' : '已扫描 · 等待确认'}</div>
                {qrStage === 'idle'
                  ? <button onClick={onScan} style={{ height: 34, padding: '0 15px', borderRadius: 9999, border: 'none', background: '#fff', color: RED, fontWeight: 700, fontSize: 13, fontFamily: 'var(--font-sans)', cursor: 'pointer', boxShadow: 'inset 0 0 0 1px ' + RED, flex: 'none' }}>扫一扫</button>
                  : <button onClick={onConfirm} style={{ height: 34, padding: '0 18px', borderRadius: 9999, border: 'none', background: RED, color: '#fff', fontWeight: 700, fontSize: 13, fontFamily: 'var(--font-sans)', cursor: 'pointer', flex: 'none' }}>确认登录</button>}
              </div>
            </div>
          )}

          {tab === 'account' && (
            <div style={{ padding: '26px 28px 30px' }}>
              <label style={{ display: 'block', fontSize: 13, color: '#888', fontWeight: 600, marginBottom: 6 }}>账号</label>
              <input value={wUser} onChange={e => setWUser(e.target.value)} placeholder="手机号 / 邮箱 / 用户名"
                style={{ width: '100%', height: 46, boxSizing: 'border-box', borderRadius: 8, border: '1px solid #e3e3e6', background: '#fafafb', fontSize: 15, fontFamily: 'var(--font-sans)', padding: '0 13px', outline: 'none', color: '#222', marginBottom: 16 }}
                onFocus={e => e.target.style.borderColor = RED} onBlur={e => e.target.style.borderColor = '#e3e3e6'} />
              <label style={{ display: 'block', fontSize: 13, color: '#888', fontWeight: 600, marginBottom: 6 }}>密码</label>
              <input value={wPass} onChange={e => setWPass(e.target.value)} type="password" placeholder="请输入密码"
                onKeyDown={e => { if (e.key === 'Enter' && wUser.trim() && wPass.length) onAccountLogin(); }}
                style={{ width: '100%', height: 46, boxSizing: 'border-box', borderRadius: 8, border: '1px solid #e3e3e6', background: '#fafafb', fontSize: 15, fontFamily: 'var(--font-sans)', padding: '0 13px', outline: 'none', color: '#222', marginBottom: 22 }}
                onFocus={e => e.target.style.borderColor = RED} onBlur={e => e.target.style.borderColor = '#e3e3e6'} />
              <button onClick={onAccountLogin} disabled={!wUser.trim() || !wPass.length}
                style={{ width: '100%', height: 48, borderRadius: 9999, border: 'none', cursor: (!wUser.trim() || !wPass.length) ? 'default' : 'pointer', fontFamily: 'var(--font-sans)', fontWeight: 800, fontSize: 16, background: (!wUser.trim() || !wPass.length) ? '#f3c2c8' : RED, color: '#fff' }}>登录</button>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12.5, color: '#aaa', marginTop: 14 }}><span style={{ cursor: 'pointer' }}>立即注册</span><span style={{ cursor: 'pointer' }}>忘记密码？</span></div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function WeiboAuthorize({ identity, onAuthorize, onCancel }) {
  const RED = '#e6162d';
  return (
    <div style={{ minHeight: '100%', background: '#f7f7f9', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '24px' }}>
      <div style={{ width: 420, maxWidth: '100%', background: '#fff', borderRadius: 14, boxShadow: '0 8px 30px rgba(0,0,0,.08), 0 0 0 1px rgba(0,0,0,.04)', overflow: 'hidden' }}>
        <div style={{ height: 52, background: RED, display: 'flex', alignItems: 'center', padding: '0 22px', gap: 9 }}>
          <span style={{ width: 24, height: 24, borderRadius: '50%', background: 'rgba(255,255,255,.22)', color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, fontSize: 14 }}>微</span>
          <span style={{ color: '#fff', fontWeight: 800, fontSize: 15.5 }}>微博授权</span>
          <span style={{ marginLeft: 'auto', color: 'rgba(255,255,255,.85)', fontSize: 12.5 }}>api.weibo.com</span>
        </div>
        <div style={{ padding: '24px 26px 26px' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 16, marginBottom: 22 }}>
            <PerchAppIcon size={50} />
            <span style={{ color: '#ccc', fontSize: 22 }}>⇄</span>
            <span style={{ position: 'relative', display: 'inline-flex' }}><PAvatar person={identity} size={50} /><span style={{ position: 'absolute', right: -3, bottom: -3, width: 18, height: 18, borderRadius: '50%', background: RED, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, fontSize: 10, boxShadow: '0 0 0 2px #fff' }}>微</span></span>
          </div>
          <div style={{ textAlign: 'center', fontSize: 16, color: '#222', marginBottom: 3 }}><span style={{ fontWeight: 800 }}>Perch</span> 请求访问你的微博账号</div>
          <div style={{ textAlign: 'center', fontSize: 13.5, color: '#999', marginBottom: 20 }}>{identity.name} · @{identity.handle}</div>
          <div style={{ background: '#fafafb', borderRadius: 10, padding: '8px 16px', marginBottom: 22 }}>
            {['查看你的微博与时间线', '获取你的公开资料信息', '代你发布、转发与点赞', '代你关注或取消关注用户'].map(t => <PermissionRow key={t} text={t} accent={RED} />)}
          </div>
          <button onClick={onAuthorize} style={{ width: '100%', height: 48, borderRadius: 9999, border: 'none', background: RED, color: '#fff', fontSize: 16, fontWeight: 800, fontFamily: 'var(--font-sans)', cursor: 'pointer', marginBottom: 10 }}>授权</button>
          <button onClick={onCancel} style={{ width: '100%', height: 48, borderRadius: 9999, border: '1px solid #e3e3e6', background: '#fff', color: '#555', fontSize: 16, fontWeight: 700, fontFamily: 'var(--font-sans)', cursor: 'pointer' }}>取消</button>
          <div style={{ fontSize: 12, color: '#aaa', textAlign: 'center', marginTop: 15, lineHeight: 1.5 }}>授权后 Perch 不会获取你的微博密码，<br />你可随时在微博账号设置中解除授权。</div>
        </div>
      </div>
    </div>
  );
}

/* ════════════════════════ Success splash ════════════════════════ */
function AuthSuccess({ identity, isX }) {
  const RED = identity.platform === 'x' ? '#0f1419' : '#e6162d';
  return (
    <div style={{ minHeight: '100%', background: identity.platform === 'x' ? '#000' : '#f7f7f9', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 16, padding: 24 }}>
      <span style={{ width: 66, height: 66, borderRadius: '50%', background: identity.platform === 'x' ? '#16181c' : '#e8faf0', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: 'var(--positive)', animation: 'winPop .3s var(--ease-default)' }}>
        <Glyph name="checkmark-circle" size={42} />
      </span>
      <div style={{ fontSize: 19, fontWeight: 800, color: identity.platform === 'x' ? '#e7e9ea' : '#222' }}>{isX ? 'Connected' : '连接成功'}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '7px 14px 7px 8px', borderRadius: 9999, background: identity.platform === 'x' ? '#16181c' : '#fff', boxShadow: identity.platform === 'x' ? 'none' : '0 0 0 1px rgba(0,0,0,.05)' }}>
        <PAvatar person={identity} size={26} />
        <span style={{ fontSize: 14, fontWeight: 700, color: identity.platform === 'x' ? '#e7e9ea' : '#222' }}>{identity.platform === 'x' ? '@' + identity.handle : identity.name}</span>
      </div>
      <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, fontSize: 13, color: identity.platform === 'x' ? '#71767b' : '#999', marginTop: 4 }}>
        <span style={{ width: 13, height: 13, borderRadius: '50%', border: '2px solid currentColor', borderTopColor: 'transparent', animation: 'aaSpin .7s linear infinite' }} />
        {isX ? 'Returning to Perch…' : '正在返回 Perch…'}
      </div>
    </div>
  );
}

/* ════════════════════════ Orchestrator ════════════════════════ */
function AddAccount({ platform: initPlatform, isX, onClose, onAdded }) {
  const [platform, setPlatform] = React.useState(initPlatform || null);
  // x: username | password | authorize | success ; weibo: login | authorize | success
  const [step, setStep] = React.useState(initPlatform ? (initPlatform === 'x' ? 'username' : 'login') : 'pick');
  const [username, setUsername] = React.useState('');
  const [password, setPassword] = React.useState('');
  const [wTab, setWTab] = React.useState('qr');
  const [qrStage, setQrStage] = React.useState('idle'); // idle | scanned
  const [wUser, setWUser] = React.useState('');
  const [wPass, setWPass] = React.useState('');
  const [identity, setIdentity] = React.useState(null);

  React.useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const pick = (p) => { setPlatform(p); setStep(p === 'x' ? 'username' : 'login'); };

  // build identity then jump to the authorize screen
  const toAuthorizeX = () => {
    setIdentity(aaMakeAccount({ platform: 'x', handle: username, name: aaNameFromHandle(username), verified: Math.random() > 0.5 }));
    setStep('authorize');
  };
  const toAuthorizeWeiboQR = () => {
    setIdentity(aaMakeAccount({ platform: 'weibo', handle: 'yunxiu_film', name: '云岫', verified: true, followers: '2.3万', following: '186' }));
    setStep('authorize');
  };
  const toAuthorizeWeiboAccount = () => {
    const name = /[\u4e00-\u9fff]/.test(wUser) ? wUser : aaNameFromHandle(wUser);
    setIdentity(aaMakeAccount({ platform: 'weibo', handle: wUser, name, verified: false, followers: '1.2万', following: '208' }));
    setStep('authorize');
  };

  const authorize = () => {
    setStep('success');
    setTimeout(() => { onAdded(identity); }, 1100);
  };

  // browser "back" / picker back
  const goBack = () => {
    if (step === 'pick') { onClose(); return; }
    if (platform === 'x') {
      if (step === 'username') { setPlatform(null); setStep('pick'); }
      else if (step === 'password') setStep('username');
      else if (step === 'authorize') setStep('password');
    } else {
      if (step === 'login') { setPlatform(null); setStep('pick'); }
      else if (step === 'authorize') { setStep('login'); setQrStage('idle'); }
    }
  };

  // address-bar url per state
  const url = platform === 'x'
    ? (step === 'authorize' ? 'x.com/i/oauth2/authorize?client=perch' : step === 'success' ? 'perch.app/auth/callback' : 'x.com/i/flow/login')
    : (step === 'authorize' ? 'api.weibo.com/oauth2/authorize' : step === 'success' ? 'perch.app/auth/callback' : 'passport.weibo.com/sso/signin');

  const browserMode = step !== 'pick';
  const titleText = step === 'pick'
    ? (isX ? 'Add Account' : '添加账号')
    : (platform === 'x' ? (isX ? 'Sign in to X' : '登录 X') : (isX ? 'Sign in to Weibo' : '微博登录'));

  return (
    <MacWindow title={titleText} onClose={onClose} width={browserMode ? 820 : 460} height={browserMode ? 600 : undefined}>
      {step === 'pick' ? (
        /* ── platform picker ── */
        <React.Fragment>
          <div style={{ padding: '15px 18px 4px' }}>
            <div style={{ fontSize: 13, color: 'var(--fg-subdued)', lineHeight: 1.45 }}>{isX ? 'Sign in through the in‑app browser to connect a new account.' : '通过应用内浏览器登录以连接新账号。'}</div>
          </div>
          <div style={{ padding: 16, display: 'flex', flexDirection: 'column', gap: 11 }}>
            <PlatformChoice platform="x" isX={isX} title="X" sub={isX ? 'Sign in with your X username' : '使用 X 用户名登录'} onClick={() => pick('x')} />
            <PlatformChoice platform="weibo" isX={isX} title={isX ? 'Weibo' : '微博'} sub={isX ? 'Scan a QR code or sign in' : '扫码或账号密码登录'} onClick={() => pick('weibo')} />
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '0 18px 18px', color: 'var(--fg-subdued)', fontSize: 12, lineHeight: 1.5 }}>
            <span style={{ display: 'inline-flex', width: 14, height: 14, flex: 'none' }}><Glyph name="lock" size={14} /></span>
            {isX ? 'Perch signs in through the official site. Your password is never stored.' : 'Perch 通过官方网站登录，绝不存储你的密码。'}
          </div>
        </React.Fragment>
      ) : (
        <BrowserBody url={url} isX={isX} onBack={goBack} busy={step === 'success'}>
          {platform === 'x' && (step === 'username' || step === 'password') && (
            <XLogin step={step} username={username} setUsername={setUsername} password={password} setPassword={setPassword}
              onNext={() => username.trim() && setStep('password')} onLogin={() => password.length && toAuthorizeX()} />
          )}
          {platform === 'x' && step === 'authorize' && <XAuthorize identity={identity} isX={isX} onAuthorize={authorize} onCancel={onClose} />}
          {platform === 'weibo' && step === 'login' && (
            <WeiboLogin tab={wTab} setTab={setWTab} qrStage={qrStage}
              onScan={() => setQrStage('scanned')} onConfirm={toAuthorizeWeiboQR}
              wUser={wUser} setWUser={setWUser} wPass={wPass} setWPass={setWPass} onAccountLogin={() => wUser.trim() && wPass.length && toAuthorizeWeiboAccount()} />
          )}
          {platform === 'weibo' && step === 'authorize' && <WeiboAuthorize identity={identity} onAuthorize={authorize} onCancel={onClose} />}
          {step === 'success' && identity && <AuthSuccess identity={identity} isX={isX} />}
        </BrowserBody>
      )}
    </MacWindow>
  );
}

function PlatformChoice({ platform, title, sub, onClick, isX }) {
  const [h, setH] = React.useState(false);
  const px = platform === 'x';
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 14, width: '100%', padding: '14px 16px', borderRadius: 13, border: '1px solid ' + (h ? 'var(--accent)' : 'var(--border-default)'), background: h ? 'var(--gray-75)' : 'var(--bg-base)', cursor: 'pointer', textAlign: 'left', transition: 'border-color .12s, background .12s', fontFamily: 'var(--font-sans)' }}>
      <span style={{ width: 46, height: 46, borderRadius: '50%', flex: 'none', background: px ? '#15141a' : '#e6162d', color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: px ? 22 : 20, fontWeight: 800 }}>{px ? '𝕏' : '微'}</span>
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'block', fontSize: 16, fontWeight: 800, color: 'var(--fg-heading)' }}>{title}</span>
        <span style={{ display: 'block', fontSize: 13, color: 'var(--fg-subdued)', marginTop: 1 }}>{sub}</span>
      </span>
      <span style={{ display: 'inline-flex', width: 18, height: 18, color: h ? 'var(--accent)' : 'var(--fg-disabled)', transform: 'rotate(-90deg)', flex: 'none' }}><Glyph name="chevron-down" size={18} /></span>
    </button>
  );
}

Object.assign(window, { AddAccount, MacWindow, MacTraffic });

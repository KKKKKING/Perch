/* Perch — first-launch / empty-state welcome window.
   Shown when Perch has no connected accounts (fresh install, or right after the
   last account is removed). It introduces the app and guides the user to connect
   their first X or Weibo account through the real in-app login flow (AddAccount).
   Built entirely from the app's Spectrum 2 vocabulary + Perch brand. */
const { useState, useEffect } = React;

/* Accent override, mirrors settings.jsx accentVars so the welcome screen honors
   the same accent palette as the rest of Perch. */
function wAccentVars(id) {
  if (!id || id === 'blue') return {
    '--accent': '#1D9BF0',
    '--accent-bg': '#1D9BF0',
    '--accent-bg-hover': '#1A8CD8',
    '--accent-bg-down': '#1781C4',
  };
  return { '--accent': `var(--${id}-900)`, '--accent-bg': `var(--${id}-900)`, '--accent-bg-hover': `var(--${id}-1000)`, '--accent-bg-down': `var(--${id}-1000)` };
}

/* ── Perch brand mark — the perched-bird app icon (shared PerchIcon). ── */
function PerchMark({ size = 56 }) {
  return <PerchIcon size={size} />;
}

/* Decorative macOS traffic lights (welcome window can't be closed mid-onboarding). */
function WTraffic() {
  const dot = (bg) => <span style={{ width: 12, height: 12, borderRadius: '50%', background: bg, boxShadow: 'inset 0 0 0 .5px rgba(0,0,0,.22)' }} />;
  return <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>{dot('#ff5f57')}{dot('#febc2e')}{dot('#28c840')}</div>;
}

function WBadge({ platform, size = 16 }) {
  const isX = platform === 'x';
  return (
    <span style={{ width: size, height: size, borderRadius: '50%', flex: 'none',
      background: isX ? '#15141a' : '#e6162d', color: '#fff',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontSize: isX ? size * 0.6 : size * 0.56, fontWeight: 800, fontFamily: 'var(--font-sans)',
      boxShadow: '0 0 0 2px var(--bg-base)' }}>{isX ? '𝕏' : '微'}</span>
  );
}

/* ── A single platform connect row (launches the login flow). ── */
function ConnectRow({ platform, title, sub, onClick }) {
  const [h, setH] = useState(false);
  const px = platform === 'x';
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 14, width: '100%', padding: '14px 16px', borderRadius: 14,
        border: '1px solid ' + (h ? 'var(--accent)' : 'var(--border-default)'), background: h ? 'var(--gray-75)' : 'var(--bg-base)',
        cursor: 'pointer', textAlign: 'left', transition: 'border-color .14s var(--ease-default), background .14s var(--ease-default)', fontFamily: 'var(--font-sans)',
        boxShadow: h ? '0 1px 6px rgba(0,0,0,.10)' : 'none' }}>
      <span style={{ width: 46, height: 46, borderRadius: '50%', flex: 'none', background: px ? '#15141a' : '#e6162d', color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: px ? 22 : 20, fontWeight: 800 }}>{px ? '𝕏' : '微'}</span>
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'block', fontSize: 16, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.01em' }}>{title}</span>
        <span style={{ display: 'block', fontSize: 13, color: 'var(--fg-subdued)', marginTop: 1 }}>{sub}</span>
      </span>
      <span style={{ display: 'inline-flex', width: 18, height: 18, color: h ? 'var(--accent)' : 'var(--fg-disabled)', transform: 'rotate(-90deg)', flex: 'none', transition: 'color .14s' }}><Glyph name="chevron-down" size={18} /></span>
    </button>
  );
}

/* ── The connect panel (heading + value line + platform rows + reassurance). ── */
function ConnectPanel({ centered, onConnect }) {
  const align = centered ? 'center' : 'flex-start';
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: align, textAlign: centered ? 'center' : 'left', width: '100%', maxWidth: centered ? 420 : 'none' }}>
      {/* brand lockup */}
      <div style={{ display: 'flex', flexDirection: centered ? 'column' : 'row', alignItems: 'center', gap: centered ? 12 : 11, marginBottom: centered ? 22 : 24 }}>
        <PerchMark size={centered ? 60 : 38} />
        <span style={{ fontFamily: 'var(--font-serif)', fontSize: centered ? 30 : 23, fontWeight: 700, color: 'var(--fg-heading)', letterSpacing: '-.01em', lineHeight: 1 }}>Perch</span>
      </div>

      <h1 style={{ margin: 0, width: '100%', fontSize: centered ? 28 : 31, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.025em', lineHeight: 1.08 }}>Welcome to Perch</h1>
      <p style={{ margin: '11px 0 0', width: '100%', fontSize: 15, lineHeight: 1.5, color: 'var(--fg-body)', maxWidth: 384, textWrap: 'pretty' }}>Read X and Weibo together — calm, dense, and native to your Mac. Connect an account to get started.</p>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 11, width: '100%', marginTop: 26 }}>
        <ConnectRow platform="x" title="X" sub="Sign in with your X account" onClick={() => onConnect('x')} />
        <ConnectRow platform="weibo" title="微博 Weibo" sub="Scan a QR code or sign in" onClick={() => onConnect('weibo')} />
      </div>

      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8, marginTop: 22, color: 'var(--fg-subdued)', justifyContent: centered ? 'center' : 'flex-start' }}>
        <span style={{ display: 'inline-flex', width: 14, height: 14, flex: 'none', marginTop: 1 }}><Glyph name="lock" size={14} /></span>
        <span style={{ fontSize: 12, lineHeight: 1.5, maxWidth: 360 }}>Perch signs in through the official site. Your password is never stored.</span>
      </div>
    </div>
  );
}

/* ── Success state after the first account connects. ── */
function SuccessPanel({ acct, onAddAnother }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', width: '100%', maxWidth: 420 }}>
      <span style={{ width: 64, height: 64, borderRadius: '50%', background: 'color-mix(in srgb, var(--positive) 16%, transparent)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: 'var(--positive)', marginBottom: 18, animation: 'winPop .3s var(--ease-default)' }}>
        <Glyph name="checkmark-circle" size={40} />
      </span>
      <h1 style={{ margin: 0, fontSize: 27, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.02em' }}>You're all set</h1>
      <p style={{ margin: '10px 0 0', fontSize: 15, color: 'var(--fg-body)', lineHeight: 1.5 }}>
        <strong style={{ color: 'var(--fg-heading)' }}>{acct.name}</strong> is connected. Your timeline is ready.
      </p>

      <div style={{ display: 'inline-flex', alignItems: 'center', gap: 9, padding: '8px 15px 8px 8px', borderRadius: 9999, background: 'var(--bg-layer-1)', border: '1px solid var(--border-default)', marginTop: 20 }}>
        <span style={{ position: 'relative', display: 'inline-flex' }}>
          <PAvatar person={acct} size={28} />
          <span style={{ position: 'absolute', right: -3, bottom: -3 }}><WBadge platform={acct.platform} size={14} /></span>
        </span>
        <span style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 14, fontWeight: 700, color: 'var(--fg-heading)' }}>
          {acct.name}{acct.verified && <Verified size={13} />}
        </span>
        <span style={{ fontSize: 12.5, fontWeight: 700, color: 'var(--positive)', display: 'inline-flex', alignItems: 'center', gap: 5, marginLeft: 2 }}>
          <span style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--positive)' }} /> {acct.platform === 'x' ? 'Signed in' : '已连接'}
        </span>
      </div>

      <a href="Perch.html" style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 9, height: 50, padding: '0 26px', borderRadius: 9999, border: 'none', background: 'var(--accent-bg)', color: '#fff', fontSize: 16, fontWeight: 800, fontFamily: 'var(--font-sans)', textDecoration: 'none', cursor: 'pointer', marginTop: 26, boxShadow: '0 2px 10px color-mix(in srgb, var(--accent-bg) 42%, transparent)' }}>
        Open Perch
        <span style={{ display: 'inline-flex', width: 18, height: 18, transform: 'rotate(-90deg)' }}><Glyph name="chevron-down" size={18} /></span>
      </a>
      <button onClick={onAddAnother} style={{ height: 40, padding: '0 16px', borderRadius: 9999, border: 'none', background: 'transparent', color: 'var(--fg-subdued)', fontSize: 14, fontWeight: 700, fontFamily: 'var(--font-sans)', cursor: 'pointer', marginTop: 8 }}>Add another account</button>
    </div>
  );
}

/* ── The window itself — centered layout. ── */
function Welcome({ theme, accent, connected, onConnect, onAddAnother }) {
  const desktop = theme === 'dark'
    ? 'radial-gradient(120% 120% at 20% 0%, #2a2730, #131216 60%)'
    : 'radial-gradient(120% 120% at 20% 0%, #e7ecf5, #cdd6e6 70%)';
  return (
    <div data-theme={theme} style={{ position: 'fixed', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', background: desktop, fontFamily: 'var(--font-sans)' }}>
      <div style={{ width: 'min(560px, 94vw)', height: 'min(584px, 92vh)', borderRadius: 13, overflow: 'hidden', display: 'flex', background: 'var(--bg-base)', position: 'relative',
        boxShadow: '0 0 0 1px rgba(0,0,0,.28), 0 28px 70px rgba(0,0,0,.45)', ...wAccentVars(accent) }}>

        <div style={{ position: 'absolute', top: 16, left: 16, zIndex: 5 }}><WTraffic /></div>

        <div style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '56px 48px' }}>
          {connected
            ? <SuccessPanel acct={connected} onAddAnother={onAddAnother} />
            : <ConnectPanel centered={true} onConnect={onConnect} />}
        </div>
      </div>
    </div>
  );
}

/* ── Mount: state, the real AddAccount login flow, and Tweaks. ── */
const ACCENT_OPTS = [['#3b63fb', 'blue'], ['#7155fa', 'indigo'], ['#9a47e2', 'purple'], ['#07816d', 'seafoam']];

/* Perch's main window persists its preferences here (see shell.jsx). The welcome
   screen reads the same store so its appearance matches the app the moment it opens. */
const PERCH_LS = 'perch.v1';
function loadPerchState() { try { return JSON.parse(localStorage.getItem(PERCH_LS)) || {}; } catch (e) { return {}; } }

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "accent": "#3b63fb"
}/*EDITMODE-END*/;

function WelcomeApp() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const accent = (ACCENT_OPTS.find(o => o[0] === t.accent) || ACCENT_OPTS[0])[1];

  /* Appearance follows the app's saved setting; on first launch (no saved value)
     it falls back to the system's light/dark preference. */
  const themeMode = React.useMemo(() => {
    const s = loadPerchState();
    return s.themeMode || s.theme || 'system';
  }, []);
  const [sysDark, setSysDark] = useState(() => !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches));
  const theme = themeMode === 'system' ? (sysDark ? 'dark' : 'light') : themeMode;

  const [addOpen, setAddOpen] = useState(false);
  const [addPlatform, setAddPlatform] = useState(null);
  const [connected, setConnected] = useState(null);

  const onConnect = (p) => { setAddPlatform(p); setAddOpen(true); };
  const onAdded = (acct) => { setAddOpen(false); setConnected(acct); };
  const onAddAnother = () => { setConnected(null); setAddPlatform(null); setAddOpen(true); };

  /* Keep tracking the system preference live while in “system” mode. */
  useEffect(() => {
    if (!window.matchMedia) return;
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const fn = (e) => setSysDark(e.matches);
    mq.addEventListener ? mq.addEventListener('change', fn) : mq.addListener(fn);
    return () => { mq.removeEventListener ? mq.removeEventListener('change', fn) : mq.removeListener(fn); };
  }, []);

  useEffect(() => { document.documentElement.setAttribute('data-theme', theme); }, [theme]);

  return (
    <React.Fragment>
      <Welcome theme={theme} accent={accent} connected={connected} onConnect={onConnect} onAddAnother={onAddAnother} />

      {addOpen && <AddAccount platform={addPlatform} isX={true} onClose={() => setAddOpen(false)} onAdded={onAdded} />}

      <TweaksPanel>
        <TweakSection label="Brand" />
        <TweakColor label="Accent" value={t.accent} options={ACCENT_OPTS.map(o => o[0])} onChange={(v) => setTweak('accent', v)} />
      </TweaksPanel>
    </React.Fragment>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<WelcomeApp />);

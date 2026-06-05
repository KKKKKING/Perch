/* Shared video player — ONE component used by both the inline Timeline
   (post.jsx → MediaVideo) and the floating new-window viewer (media.jsx →
   MediaViewer). Handles: muted autoplay, hover-reveal controls, a bottom-left
   countdown at rest, click-to-play/pause (with "engage sound" on a
   default-muted clip), a two-level settings menu (speed + quality), real-ish
   fullscreen, and a floating picture-in-picture mini-player.

   variant="inline"  → Timeline card: rounded box, PiP + fullscreen + "open in
                       window" affordances.
   variant="window"  → fills its container inside the macOS viewer window;
                       fullscreen only (no PiP / open-in-window). */

function vpParseDur(s) {
  if (!s) return 30;
  const m = String(s).split(':').map(n => parseInt(n, 10) || 0);
  return m.length === 2 ? m[0] * 60 + m[1] : m[0];
}
function vpFmtTime(sec) {
  sec = Math.max(0, Math.round(sec));
  const m = Math.floor(sec / 60), s = sec % 60;
  return m + ':' + String(s).padStart(2, '0');
}

/* circular control-bar button (plain icon, subtle hover) */
function VPBtn({ name, size = 19, onClick, title, dim = 34 }) {
  const [h, setH] = React.useState(false);
  return (
    <button onClick={onClick} title={title} aria-label={title}
      onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ width: dim, height: dim, borderRadius: '50%', border: 'none', flex: 'none', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', padding: 0, background: h ? 'rgba(255,255,255,.18)' : 'transparent', color: '#fff', transition: 'background .12s, transform .12s', transform: h ? 'scale(1.06)' : 'scale(1)' }}>
      <span style={{ display: 'inline-flex', width: size, height: size }}><Glyph name={name} size={size} /></span>
    </button>
  );
}

/* a root row in the settings menu (speed / quality / open-in-window) */
function VPRootRow({ icon, circled, label, value, onClick }) {
  const [h, setH] = React.useState(false);
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 14, width: '100%', padding: '12px 16px', border: 'none', cursor: 'pointer', background: h ? 'rgba(255,255,255,.08)' : 'transparent', color: '#fff', fontSize: 15, fontWeight: 600, fontFamily: 'var(--font-sans)', textAlign: 'left' }}>
      <span style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', width: 22, height: 22, flex: 'none', borderRadius: circled ? '50%' : 0, boxShadow: circled ? 'inset 0 0 0 1.6px currentColor' : 'none', color: '#fff' }}>
        <span style={{ display: 'inline-flex', width: circled ? 12 : 18, height: circled ? 12 : 18, marginLeft: circled ? 1 : 0 }}><Glyph name={icon} size={circled ? 12 : 18} /></span>
      </span>
      <span style={{ flex: 1, minWidth: 0 }}>{label}{value != null && <span style={{ color: 'rgba(255,255,255,.55)', fontWeight: 500 }}> · {value}</span>}</span>
    </button>
  );
}

function VPRadio({ on }) {
  return (
    <span style={{ width: 20, height: 20, borderRadius: '50%', flex: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', background: on ? 'var(--accent)' : 'transparent', boxShadow: on ? 'none' : 'inset 0 0 0 1.5px rgba(255,255,255,.45)' }}>
      {on && <span style={{ display: 'inline-flex', width: 13, height: 13, color: '#fff' }}><Glyph name="checkmark" size={13} /></span>}
    </span>
  );
}
function VPOptRow({ label, on, onClick }) {
  const [h, setH] = React.useState(false);
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%', padding: '9px 14px', border: 'none', cursor: 'pointer', background: h ? 'rgba(255,255,255,.08)' : 'transparent', color: '#fff', fontSize: 14, fontWeight: 500, fontFamily: 'var(--font-sans)', fontVariantNumeric: 'tabular-nums' }}>
      <span>{label}</span><VPRadio on={on} />
    </button>
  );
}

function VideoPlayer({ grad, dur, isX, variant = 'inline', onOpenWindow }) {
  const D = vpParseDur(dur);
  const [playing, setPlaying] = React.useState(true);
  const [t, setT] = React.useState(0);
  const [muted, setMuted] = React.useState(true);        // Timeline default: muted…
  const [mutedManual, setMutedManual] = React.useState(false); // …until the user sets it
  const [speed, setSpeed] = React.useState(1);
  const [quality, setQuality] = React.useState('auto');
  const [hover, setHover] = React.useState(false);
  const [gearOpen, setGearOpen] = React.useState(false);
  const [gearView, setGearView] = React.useState('root');
  const [mode, setMode] = React.useState('normal');      // normal | fs | pip
  const [pipXY, setPipXY] = React.useState(null);

  // advance the playhead; loop at the end
  React.useEffect(() => {
    if (!playing) return;
    const id = setInterval(() => setT(p => { const nx = p + 0.1 * speed; return nx >= D ? 0 : nx; }), 100);
    return () => clearInterval(id);
  }, [playing, D, speed]);

  // Esc leaves fullscreen / picture-in-picture
  React.useEffect(() => {
    if (mode === 'normal') return;
    const onKey = (e) => { if (e.key === 'Escape') { e.stopPropagation(); setMode('normal'); } };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [mode]);

  const pct = D ? Math.min(100, (t / D) * 100) : 0;
  const remaining = Math.max(0, D - t);
  const stop = (e) => e.stopPropagation();
  const closeGear = () => { setGearOpen(false); setGearView('root'); };

  // click on the video body (not the controls)
  const onBodyClick = (e) => {
    stop(e);
    if (gearOpen) { closeGear(); return; }
    // Timeline card: tapping the body (outside the control bar) opens the floating viewer
    if (variant === 'inline' && mode === 'normal' && onOpenWindow) { onOpenWindow(); return; }
    if (muted && !mutedManual) { setMuted(false); setPlaying(true); }  // engage a default-muted clip
    else setPlaying(p => !p);
  };
  const onMute = (e) => { stop(e); setMutedManual(true); setMuted(m => !m); };
  const seek = (e) => {
    stop(e);
    const r = e.currentTarget.getBoundingClientRect();
    setT(Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)) * D);
  };

  const showControls = hover || !playing || gearOpen;
  const lang = (en, zh) => (isX ? en : zh);

  // ── settings menu ──────────────────────────────────────────────
  const SPEEDS = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
  const QUALS = [['auto', lang('Auto', '自动')], ['270p', '270p'], ['360p', '360p'], ['720p', '720p'], ['1080p', '1080p'], ['2160p', '2160p']];
  const speedLabel = speed === 1 ? '1x' : speed + 'x';
  const qLabel = quality === 'auto' ? lang('Auto (2160p)', '自动 (2160p)') : quality;
  const SubHeader = ({ title }) => {
    const [h, setH] = React.useState(false);
    return (
      <button onClick={(e) => { stop(e); setGearView('root'); }} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
        style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', padding: '11px 14px', border: 'none', borderBottom: '1px solid rgba(255,255,255,.1)', cursor: 'pointer', background: 'transparent', color: '#fff', fontSize: 15, fontWeight: 700, fontFamily: 'var(--font-sans)' }}>
        <span style={{ display: 'inline-flex', width: 18, height: 18, transform: 'rotate(90deg)', opacity: h ? 1 : .85 }}><Glyph name="chevron-down" size={18} /></span>
        {title}
      </button>
    );
  };
  const gearMenu = gearOpen ? (
    <React.Fragment>
      <div onClick={(e) => { stop(e); closeGear(); }} style={{ position: 'fixed', inset: 0, zIndex: 3 }} />
      <div onClick={stop} style={{ position: 'absolute', bottom: 42, right: -4, width: gearView === 'root' ? 252 : 230, maxHeight: 268, overflowY: 'auto', background: 'rgba(22,22,26,.97)', border: '1px solid rgba(255,255,255,.12)', borderRadius: 14, boxShadow: '0 12px 34px rgba(0,0,0,.5)', padding: '6px 0', zIndex: 4, backdropFilter: 'blur(12px)', WebkitBackdropFilter: 'blur(12px)' }}>
        {gearView === 'root' && (
          <React.Fragment>
            <VPRootRow icon="s2play" circled label={lang('Playback speed', '播放速度')} value={speedLabel} onClick={(e) => { stop(e); setGearView('speed'); }} />
            <VPRootRow icon="poll" label={lang('Quality', '视频质量')} value={qLabel} onClick={(e) => { stop(e); setGearView('quality'); }} />
          </React.Fragment>
        )}
        {gearView === 'speed' && (
          <React.Fragment>
            <SubHeader title={lang('Playback speed', '播放速度')} />
            <div style={{ padding: '4px 0' }}>
              {SPEEDS.map(sp => <VPOptRow key={sp} label={sp + 'x'} on={sp === speed} onClick={(e) => { stop(e); setSpeed(sp); closeGear(); }} />)}
            </div>
          </React.Fragment>
        )}
        {gearView === 'quality' && (
          <React.Fragment>
            <SubHeader title={lang('Quality', '视频质量')} />
            <div style={{ padding: '4px 0' }}>
              {QUALS.map(([v, lbl]) => <VPOptRow key={v} label={lbl} on={v === quality} onClick={(e) => { stop(e); setQuality(v); closeGear(); }} />)}
            </div>
          </React.Fragment>
        )}
      </div>
    </React.Fragment>
  ) : null;

  // ── control bar ────────────────────────────────────────────────
  const controlBar = (
    <div onClick={stop} style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: '40px 12px 10px', background: 'linear-gradient(to top, rgba(0,0,0,.64), rgba(0,0,0,0))', cursor: 'default' }}>
      <div onClick={seek} style={{ height: 16, display: 'flex', alignItems: 'center', cursor: 'pointer', margin: '0 4px 3px' }}>
        <div style={{ position: 'relative', width: '100%', height: 4, borderRadius: 9999, background: 'rgba(255,255,255,.3)' }}>
          <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: pct + '%', borderRadius: 9999, background: 'var(--accent)' }} />
          <div style={{ position: 'absolute', left: 'calc(' + pct + '% - 6px)', top: '50%', transform: 'translateY(-50%)', width: 12, height: 12, borderRadius: '50%', background: '#fff', boxShadow: '0 1px 4px rgba(0,0,0,.45)' }} />
        </div>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
        <VPBtn name={playing ? 's2pause' : 's2play'} size={17} onClick={(e) => { stop(e); closeGear(); setPlaying(p => !p); }} title={playing ? lang('Pause', '暂停') : lang('Play', '播放')} />
        <div style={{ flex: 1 }} />
        <span style={{ color: '#fff', fontSize: 12.5, fontWeight: 600, fontFamily: 'var(--font-sans)', fontVariantNumeric: 'tabular-nums', marginRight: 6, whiteSpace: 'nowrap' }}>{vpFmtTime(t)} / {vpFmtTime(D)}</span>
        <VPBtn name={muted ? 's2mute' : 's2volume'} size={18} onClick={onMute} title={muted ? lang('Unmute', '取消静音') : lang('Mute', '静音')} />
        <span style={{ position: 'relative', display: 'inline-flex' }}>
          <VPBtn name="settings" size={18} onClick={(e) => { stop(e); setGearView('root'); setGearOpen(o => !o); }} title={lang('Settings', '设置')} />
          {gearMenu}
        </span>
        {variant === 'inline' && mode === 'normal' && (
          <VPBtn name="pip" size={18} onClick={(e) => { stop(e); closeGear(); setPipXY(null); setMode('pip'); }} title={lang('Picture in picture', '画中画')} />
        )}
        <VPBtn name={mode === 'fs' ? 's2fullscreenexit' : 's2fullscreen'} size={18} onClick={(e) => { stop(e); closeGear(); setMode(mode === 'fs' ? 'normal' : 'fs'); }} title={mode === 'fs' ? lang('Exit fullscreen', '退出全屏') : lang('Fullscreen', '全屏')} />
      </div>
    </div>
  );

  // a gradient stage + optional overlays, reused at every size
  const stage = (extra) => (
    <div onClick={onBodyClick} onMouseEnter={() => setHover(true)} onMouseLeave={() => { setHover(false); }}
      style={{ position: 'absolute', inset: 0, overflow: 'hidden', cursor: 'pointer', background: '#000', ...extra }}>
      <div className={playing ? 'perch-vid-anim' : undefined} style={{ position: 'absolute', inset: 0, background: 'linear-gradient(135deg, ' + grad[0] + ', ' + grad[1] + ')' }} />
      {!playing && (variant !== 'inline' || mode !== 'normal') && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none' }}>
          <div style={{ width: 54, height: 54, borderRadius: '50%', background: 'rgba(0,0,0,.42)', backdropFilter: 'blur(6px)', WebkitBackdropFilter: 'blur(6px)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', boxShadow: '0 2px 10px rgba(0,0,0,.3)' }}>
            <span style={{ display: 'inline-flex', width: 24, height: 24 }}><Glyph name="s2play" size={24} /></span>
          </div>
        </div>
      )}
      {!showControls && (
        <div style={{ position: 'absolute', left: 10, bottom: 10, pointerEvents: 'none', display: 'inline-flex', alignItems: 'center', gap: 5, height: 22, padding: '0 8px 0 6px', borderRadius: 7, background: 'rgba(0,0,0,.62)', color: '#fff', fontSize: 12, fontWeight: 700, fontFamily: 'var(--font-sans)', fontVariantNumeric: 'tabular-nums', backdropFilter: 'blur(4px)', WebkitBackdropFilter: 'blur(4px)' }}>
          <span style={{ display: 'inline-flex', width: 14, height: 14 }}><Glyph name={muted ? 's2mute' : 's2volume'} size={14} /></span>
          {vpFmtTime(remaining)}
        </div>
      )}
      {showControls && controlBar}
    </div>
  );

  // ── fullscreen (simulated, fills the viewport — robust inside the preview) ──
  if (mode === 'fs') {
    return ReactDOM.createPortal(
      <div style={{ position: 'fixed', inset: 0, zIndex: 2000, background: '#000', animation: 'winPop .16s var(--ease-default)' }}>
        {stage({ borderRadius: 0 })}
      </div>, document.body);
  }

  // ── picture-in-picture (floating, draggable mini-player) ──
  const pipNode = mode === 'pip' ? ReactDOM.createPortal(
    <div style={{ position: 'fixed', zIndex: 2000, width: 320, aspectRatio: '16 / 9', borderRadius: 12, overflow: 'hidden', boxShadow: '0 12px 40px rgba(0,0,0,.55)', border: '1px solid rgba(255,255,255,.12)',
      ...(pipXY ? { left: pipXY.x, top: pipXY.y } : { right: 18, bottom: 18 }) }}>
      {stage({ borderRadius: 0 })}
      {/* drag handle + quick actions across the top */}
      <div onMouseDown={(e) => {
        e.preventDefault();
        const box = e.currentTarget.parentElement.getBoundingClientRect();
        const ox = e.clientX - box.left, oy = e.clientY - box.top;
        const mv = (ev) => setPipXY({ x: Math.max(6, Math.min(window.innerWidth - box.width - 6, ev.clientX - ox)), y: Math.max(6, Math.min(window.innerHeight - box.height - 6, ev.clientY - oy)) });
        const up = () => { window.removeEventListener('mousemove', mv); window.removeEventListener('mouseup', up); };
        window.addEventListener('mousemove', mv); window.addEventListener('mouseup', up);
      }} style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 34, cursor: 'grab', display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 2, padding: '0 4px', background: 'linear-gradient(to bottom, rgba(0,0,0,.5), rgba(0,0,0,0))' }}>
        {onOpenWindow && <VPBtn name="s2openin" size={15} dim={28} onClick={(e) => { stop(e); setMode('normal'); onOpenWindow(); }} title={lang('Open in window', '在新窗口打开')} />}
        <VPBtn name="close" size={15} dim={28} onClick={(e) => { stop(e); setMode('normal'); }} title={lang('Close', '关闭')} />
      </div>
    </div>, document.body) : null;

  // ── normal inline / window surface ──
  const base = variant === 'inline'
    ? { marginTop: 10, position: 'relative', borderRadius: 14, overflow: 'hidden', border: '1px solid var(--border-default)', aspectRatio: '16 / 9', background: '#000' }
    : { position: 'absolute', inset: 0 };

  return (
    <div style={base}>
      {mode === 'pip' ? (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', flexDirection: 'column', gap: 12, background: 'var(--bg-layer-1)', color: 'var(--fg-subdued)' }}>
          <span style={{ display: 'inline-flex', width: 30, height: 30, color: 'var(--fg-subdued)' }}><Glyph name="pip" size={30} /></span>
          <div style={{ fontSize: 13.5, fontWeight: 600, fontFamily: 'var(--font-sans)' }}>{lang('Playing in picture-in-picture', '正在画中画播放')}</div>
          <button onClick={() => setMode('normal')} style={{ height: 32, padding: '0 16px', borderRadius: 9999, border: '1px solid var(--border-strong)', cursor: 'pointer', background: 'var(--bg-layer-2)', color: 'var(--fg-body)', fontSize: 13, fontWeight: 700, fontFamily: 'var(--font-sans)' }}>{lang('Return here', '回到此处')}</button>
        </div>
      ) : stage()}
      {pipNode}
    </div>
  );
}

Object.assign(window, { VideoPlayer, vpParseDur, vpFmtTime });

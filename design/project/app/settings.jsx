/* Settings window — an in-app macOS-style preferences sheet.
   Sidebar of categories + scrollable panes, built from S2 controls.
   Theme (incl. System), accent color, and reduce-motion are wired live;
   the remaining switches persist their own state. */

const ACCENTS = [
  { id: 'blue',    label_x: 'Blue',    label_w: '蓝',   dot: '#1D9BF0' },
  { id: 'indigo',  label_x: 'Indigo',  label_w: '靛蓝', dot: 'var(--indigo-900)' },
  { id: 'purple',  label_x: 'Violet',  label_w: '紫',   dot: 'var(--purple-900)' },
  { id: 'magenta', label_x: 'Magenta', label_w: '品红', dot: 'var(--magenta-900)' },
  { id: 'green',   label_x: 'Green',   label_w: '绿',   dot: 'var(--green-900)' },
  { id: 'orange',  label_x: 'Orange',  label_w: '橙',   dot: 'var(--orange-900)' },
];

// CSS-var overrides merged onto the window root. Blue = the default, so no-op.
function accentVars(id) {
  // Default 'blue' is now Perch's soft sky-blue (old-Twitter direction),
  // overriding Spectrum's vivid blue-900 accent across the whole app.
  if (!id || id === 'blue') return {
    '--accent': '#1D9BF0',
    '--accent-bg': '#1D9BF0',
    '--accent-bg-hover': '#1A8CD8',
    '--accent-bg-down': '#1781C4',
  };
  return {
    '--accent': `var(--${id}-900)`,
    '--accent-bg': `var(--${id}-900)`,
    '--accent-bg-hover': `var(--${id}-1000)`,
    '--accent-bg-down': `var(--${id}-1000)`,
  };
}

const DEFAULT_PREFS = {
  accent: 'blue', launchAtLogin: true, openLinks: 'app', refreshEvery: '5', markRead: true,
  reduceMotion: false,
  notifMentions: true, notifReposts: true, notifLikes: false, notifFollowers: true, notifSound: true, dockBadge: true,
  autoplay: true, sensitive: false, linkPreviews: true, detailPane: true,
  debug: false, debugJson: true, debugNet: true,
};

/* ── Atoms ──────────────────────────────────────────────────── */

function Toggle({ on, onChange }) {
  const [p, setP] = React.useState(false);
  return (
    <button role="switch" aria-checked={on} onClick={() => onChange(!on)}
      onMouseDown={() => setP(true)} onMouseUp={() => setP(false)} onMouseLeave={() => setP(false)}
      style={{ width: 42, height: 25, borderRadius: 9999, border: 'none', cursor: 'pointer', padding: 0, position: 'relative', flex: 'none',
        background: on ? 'var(--accent-bg)' : 'var(--gray-400)', transition: 'background .16s var(--ease-default)' }}>
      <span style={{ position: 'absolute', top: 3, left: on ? 20 : 3, width: 19, height: 19, borderRadius: '50%', background: '#fff',
        boxShadow: '0 1px 2px rgba(0,0,0,.28), 0 0 0 .5px rgba(0,0,0,.06)', transform: p ? 'scaleX(1.12)' : 'none', transformOrigin: on ? 'right' : 'left',
        transition: 'left .16s var(--ease-default), transform .12s' }} />
    </button>
  );
}

function Seg({ value, options, onChange }) {
  return (
    <div style={{ display: 'inline-flex', background: 'var(--gray-100)', borderRadius: 9999, padding: 2, gap: 2 }}>
      {options.map(([val, lbl, icon]) => {
        const on = value === val;
        return (
          <button key={val} onClick={() => onChange(val)}
            style={{ height: 28, padding: icon ? '0 12px 0 9px' : '0 14px', borderRadius: 9999, border: 'none', cursor: 'pointer',
              display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 13, fontWeight: 600, fontFamily: 'var(--font-sans)',
              background: on ? 'var(--bg-elevated)' : 'transparent', color: on ? 'var(--fg-heading)' : 'var(--fg-subdued)',
              boxShadow: on ? 'var(--shadow-emphasized)' : 'none', transition: 'color .12s' }}>
            {icon && <span style={{ display: 'inline-flex', width: 15, height: 15 }}><Glyph name={icon} size={15} /></span>}
            {lbl}
          </button>
        );
      })}
    </div>
  );
}

const SEL_STYLE = { height: 32, borderRadius: 8, border: '1px solid var(--border-default)', background: 'var(--bg-base)', color: 'var(--fg-body)', fontSize: 13.5, fontFamily: 'var(--font-sans)', fontWeight: 600, padding: '0 30px 0 11px', cursor: 'pointer', appearance: 'none', WebkitAppearance: 'none', backgroundImage: 'none' };

function Picker({ value, options, onChange }) {
  return (
    <div style={{ position: 'relative', display: 'inline-flex', alignItems: 'center' }}>
      <select value={value} onChange={e => onChange(e.target.value)} style={SEL_STYLE}>
        {options.map(([val, lbl]) => <option key={val} value={val}>{lbl}</option>)}
      </select>
      <span style={{ position: 'absolute', right: 8, pointerEvents: 'none', display: 'inline-flex', width: 15, height: 15, color: 'var(--fg-subdued)' }}><Glyph name="chevron-down" size={15} /></span>
    </div>
  );
}

function AccentPicker({ value, isX, onChange }) {
  return (
    <div style={{ display: 'flex', gap: 11 }}>
      {ACCENTS.map(a => {
        const on = value === a.id;
        return (
          <button key={a.id} title={isX ? a.label_x : a.label_w} onClick={() => onChange(a.id)}
            style={{ width: 26, height: 26, borderRadius: '50%', border: 'none', cursor: 'pointer', padding: 0, background: a.dot,
              boxShadow: on ? '0 0 0 2px var(--bg-base), 0 0 0 4px var(--fg-heading)' : 'inset 0 0 0 1px rgba(0,0,0,.18)',
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center', transition: 'box-shadow .12s' }}>
            {on && <span style={{ display: 'inline-flex', width: 15, height: 15, color: '#fff' }}><Glyph name="checkmark" size={15} /></span>}
          </button>
        );
      })}
    </div>
  );
}

/* ── Layout pieces ──────────────────────────────────────────── */

function Group({ title, children }) {
  const items = React.Children.toArray(children);
  return (
    <div style={{ marginBottom: 22 }}>
      {title && <div style={{ fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.06em', color: 'var(--fg-subdued)', margin: '0 0 8px 4px' }}>{title}</div>}
      <div style={{ background: 'var(--bg-base)', border: '1px solid var(--border-default)', borderRadius: 12, padding: '0 14px' }}>
        {items.map((c, i) => React.cloneElement(c, { last: i === items.length - 1 }))}
      </div>
    </div>
  );
}

function Row({ label, desc, children, last }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '13px 0', borderBottom: last ? 'none' : '1px solid var(--border-default)' }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--fg-heading)' }}>{label}</div>
        {desc && <div style={{ fontSize: 12.5, color: 'var(--fg-subdued)', marginTop: 2, lineHeight: 1.4 }}>{desc}</div>}
      </div>
      <div style={{ flex: 'none' }}>{children}</div>
    </div>
  );
}

/* ── Panes ──────────────────────────────────────────────────── */

function GeneralPane({ isX, prefs, setPref }) {
  return (
    <React.Fragment>
      <Group title={isX ? 'Startup' : '启动'}>
        <Row label={isX ? 'Launch at login' : '登录时启动'} desc={isX ? 'Open Perch automatically when you sign in to your Mac.' : '登录 Mac 后自动打开 Perch。'}>
          <Toggle on={prefs.launchAtLogin} onChange={v => setPref('launchAtLogin', v)} />
        </Row>
        <Row label={isX ? 'Restore columns on launch' : '启动时恢复分栏'} desc={isX ? 'Reopen your last column layout each time.' : '每次打开时恢复上次的分栏布局。'}>
          <Toggle on={prefs.markRead} onChange={v => setPref('markRead', v)} />
        </Row>
      </Group>
      <Group title={isX ? 'Browsing' : '浏览'}>
        <Row label={isX ? 'Open links in' : '链接打开方式'} desc={isX ? 'Where posts and articles open when you click a link.' : '点击链接时帖子和文章的打开位置。'}>
          <Seg value={prefs.openLinks} onChange={v => setPref('openLinks', v)}
            options={[['app', isX ? 'In Perch' : '应用内'], ['browser', isX ? 'Browser' : '浏览器']]} />
        </Row>
        <Row label={isX ? 'Refresh timeline' : '刷新时间线'} desc={isX ? 'How often columns pull in new posts.' : '分栏自动拉取新帖子的频率。'}>
          <Picker value={prefs.refreshEvery} onChange={v => setPref('refreshEvery', v)}
            options={[['off', isX ? 'Manually' : '手动'], ['1', isX ? 'Every 1 min' : '每 1 分钟'], ['5', isX ? 'Every 5 min' : '每 5 分钟'], ['15', isX ? 'Every 15 min' : '每 15 分钟']]} />
        </Row>
      </Group>
    </React.Fragment>
  );
}

function AppearancePane({ isX, themeMode, onThemeMode, prefs, setPref }) {
  return (
    <React.Fragment>
      <Group title={isX ? 'Theme' : '主题'}>
        <Row label={isX ? 'Appearance' : '外观'} desc={isX ? 'System follows your macOS light or dark setting.' : '“跟随系统”将匹配 macOS 的浅色或深色设置。'}>
          <Seg value={themeMode} onChange={onThemeMode}
            options={[['light', isX ? 'Light' : '浅色', 'sun'], ['dark', isX ? 'Dark' : '深色', 'moon'], ['system', isX ? 'System' : '系统']]} />
        </Row>
        <Row label={isX ? 'Accent color' : '强调色'} desc={isX ? 'Used for the primary action, links, and selection.' : '用于主要操作、链接和选中状态。'}>
          <AccentPicker value={prefs.accent} isX={isX} onChange={v => setPref('accent', v)} />
        </Row>
      </Group>
      <Group title={isX ? 'Motion' : '动效'}>
        <Row label={isX ? 'Reduce motion' : '减弱动态效果'} desc={isX ? 'Turn off sliding panels and transitions throughout the app.' : '关闭应用内的面板滑动与过渡动画。'}>
          <Toggle on={prefs.reduceMotion} onChange={v => setPref('reduceMotion', v)} />
        </Row>
      </Group>
    </React.Fragment>
  );
}

function NotificationsPane({ isX, prefs, setPref }) {
  return (
    <React.Fragment>
      <Group title={isX ? 'Notify me about' : '通知我'}>
        <Row label={isX ? 'Mentions & replies' : '提及与回复'}><Toggle on={prefs.notifMentions} onChange={v => setPref('notifMentions', v)} /></Row>
        <Row label={isX ? 'Reposts' : '转发'}><Toggle on={prefs.notifReposts} onChange={v => setPref('notifReposts', v)} /></Row>
        <Row label={isX ? 'Likes' : '点赞'}><Toggle on={prefs.notifLikes} onChange={v => setPref('notifLikes', v)} /></Row>
        <Row label={isX ? 'New followers' : '新粉丝'}><Toggle on={prefs.notifFollowers} onChange={v => setPref('notifFollowers', v)} /></Row>
      </Group>
      <Group title={isX ? 'Delivery' : '提醒方式'}>
        <Row label={isX ? 'Play sound' : '播放提示音'} desc={isX ? 'A subtle chime when a new notification arrives.' : '新通知到达时播放轻柔提示音。'}>
          <Toggle on={prefs.notifSound} onChange={v => setPref('notifSound', v)} />
        </Row>
        <Row label={isX ? 'Show unread badge on Dock' : '在程序坞显示未读角标'} desc={isX ? 'Display the total unread count on the app icon.' : '在应用图标上显示未读总数。'}>
          <Toggle on={prefs.dockBadge} onChange={v => setPref('dockBadge', v)} />
        </Row>
      </Group>
    </React.Fragment>
  );
}

function TimelinePane({ isX, prefs, setPref }) {
  return (
    <Group title={isX ? 'Content' : '内容'}>
      <Row label={isX ? 'Autoplay videos' : '自动播放视频'} desc={isX ? 'Play videos as they scroll into view, muted.' : '视频滚动到可见区域时静音自动播放。'}>
        <Toggle on={prefs.autoplay} onChange={v => setPref('autoplay', v)} />
      </Row>
      <Row label={isX ? 'Show link previews' : '显示链接预览'} desc={isX ? 'Expand cards for shared articles and pages.' : '为分享的文章和页面展开预览卡片。'}>
        <Toggle on={prefs.linkPreviews} onChange={v => setPref('linkPreviews', v)} />
      </Row>
      <Row label={isX ? 'Display sensitive media' : '显示敏感内容'} desc={isX ? 'Show media that may contain sensitive content without a warning.' : '直接显示可能含敏感内容的媒体，不再提示。'}>
        <Toggle on={prefs.sensitive} onChange={v => setPref('sensitive', v)} />
      </Row>
      <Row label={isX ? 'Open posts in a side pane' : '在侧栏中打开帖子'} desc={isX ? 'Push post details within the column instead of a new window.' : '在分栏内推入帖子详情，而非新窗口。'}>
        <Toggle on={prefs.detailPane} onChange={v => setPref('detailPane', v)} />
      </Row>
    </Group>
  );
}

function AccountsPane({ isX, accounts, active, onAddAccount }) {
  return (
    <Group title={isX ? `Connected accounts · ${accounts.length}` : `已连接账号 · ${accounts.length}`}>
      {accounts.map(a => (
        <Row key={a.id}
          label={
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 11 }}>
              <span style={{ position: 'relative', display: 'inline-flex', flex: 'none' }}>
                <PAvatar person={a} size={34} />
                <span style={{ position: 'absolute', right: -3, bottom: -3 }}><PlatformBadge platform={a.platform} size={15} /></span>
              </span>
              <span>
                <span style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                  <span style={{ fontSize: 14, fontWeight: 700, color: 'var(--fg-heading)' }}>{a.name}</span>
                  {a.id === active.id && <span style={{ fontSize: 10, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.05em', color: 'var(--accent)', background: 'color-mix(in srgb, var(--accent) 14%, transparent)', borderRadius: 6, padding: '2px 6px' }}>{isX ? 'Active' : '当前'}</span>}
                </span>
                <span style={{ display: 'block', fontSize: 12.5, color: 'var(--fg-subdued)', marginTop: 1 }}>{a.platform === 'x' ? '@' + a.handle + ' · X' : '微博 · ' + a.followers + (isX ? '' : ' 粉丝')}</span>
              </span>
            </span>
          }>
          <SignOutBtn isX={isX} />
        </Row>
      ))}
      <AddAccountRow isX={isX} onAddAccount={onAddAccount} />
    </Group>
  );
}

function AddAccountRow({ isX, onAddAccount, last }) {
  const [h, setH] = React.useState(false);
  return (
    <div onClick={() => onAddAccount && onAddAccount()} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '13px 0', borderBottom: last ? 'none' : '1px solid var(--border-default)', cursor: 'pointer', borderRadius: 8, margin: '0 -6px', paddingLeft: 6, paddingRight: 6, background: h ? 'var(--gray-75)' : 'transparent', transition: 'background .12s' }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--accent)' }}>{isX ? 'Add account' : '添加账号'}</div>
        <div style={{ fontSize: 12.5, color: 'var(--fg-subdued)', marginTop: 2, lineHeight: 1.4 }}>{isX ? 'Connect another X or Weibo account.' : '连接另一个 X 或微博账号。'}</div>
      </div>
      <span style={{ width: 28, height: 28, borderRadius: '50%', border: '1.5px dashed ' + (h ? 'var(--accent)' : 'var(--gray-400)'), display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: h ? 'var(--accent)' : 'var(--fg-subdued)', flex: 'none', transition: 'color .12s, border-color .12s' }}>
        <span style={{ display: 'inline-flex', width: 15, height: 15 }}><Glyph name="add" size={15} /></span>
      </span>
    </div>
  );
}

function SignOutBtn({ isX }) {
  const [h, setH] = React.useState(false);
  return (
    <button onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ height: 30, padding: '0 13px', borderRadius: 8, border: '1px solid ' + (h ? 'var(--negative)' : 'var(--border-default)'), cursor: 'pointer',
        background: h ? 'color-mix(in srgb, var(--negative) 12%, transparent)' : 'var(--bg-base)', color: h ? 'var(--negative)' : 'var(--fg-body)',
        fontFamily: 'var(--font-sans)', fontSize: 13, fontWeight: 600, display: 'inline-flex', alignItems: 'center', gap: 6, transition: 'all .12s' }}>
      <span style={{ display: 'inline-flex', width: 15, height: 15 }}><Glyph name="signout" size={15} /></span>
      {isX ? 'Sign out' : '退出'}
    </button>
  );
}

function DeveloperPane({ isX, prefs, setPref, onClose }) {
  return (
    <React.Fragment>
      <Group title={isX ? 'Debugging' : '调试'}>
        <Row label={isX ? 'Debug tools' : '调试工具'} desc={isX ? 'Expose raw data and a network log for inspecting the app.' : '显示原始数据与网络请求日志，用于检查应用。'}>
          <Toggle on={prefs.debug} onChange={v => setPref('debug', v)} />
        </Row>
      </Group>
      {prefs.debug && (
        <React.Fragment>
          <Group title={isX ? 'What to expose' : '调试内容'}>
            <Row label={isX ? 'Raw JSON on posts & timelines' : '帖子与时间线的原始 JSON'} desc={isX ? 'Adds a code button to each tweet and column header to view its data.' : '为每条帖子和分栏标题添加查看原始数据的按钮。'}>
              <Toggle on={prefs.debugJson !== false} onChange={v => setPref('debugJson', v)} />
            </Row>
            <Row label={isX ? 'Log network requests' : '记录网络请求'} desc={isX ? 'Record every API call — URL and payload — with cookies and tokens stripped.' : '记录每个接口调用（URL 与提交数据），并剔除 Cookie 与令牌。'}>
              <Toggle on={prefs.debugNet !== false} onChange={v => setPref('debugNet', v)} />
            </Row>
          </Group>
          <Group title={isX ? 'Inspector' : '检查器'}>
            <Row label={isX ? 'Network & data inspector' : '网络与数据检查器'} desc={isX ? 'Open the floating window. Also reachable from the sidebar.' : '打开悬浮窗口，也可从侧边栏进入。'}>
              <button onClick={() => { if (window.DebugBus) window.DebugBus.openInspector('network'); onClose && onClose(); }}
                style={{ height: 32, padding: '0 16px', borderRadius: 8, border: 'none', cursor: 'pointer', background: 'var(--accent-bg)', color: '#fff', fontFamily: 'var(--font-sans)', fontSize: 13, fontWeight: 700 }}>{isX ? 'Open' : '打开'}</button>
            </Row>
          </Group>
        </React.Fragment>
      )}
    </React.Fragment>
  );
}

function AboutPane({ isX, prefs }) {
  const dot = ACCENTS.find(a => a.id === prefs.accent) || ACCENTS[0];
  const links = isX
    ? ['What\u2019s new', 'Help & support', 'Privacy policy', 'Acknowledgements']
    : ['更新内容', '帮助与支持', '隐私政策', '开源致谢'];
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', padding: '14px 0 4px' }}>
      <PerchIcon size={80} />
      <div style={{ fontSize: 24, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.02em', marginTop: 16 }}>Perch</div>
      <div style={{ fontSize: 13.5, color: 'var(--fg-subdued)', marginTop: 3 }}>{isX ? 'A calm multi-column reader for X & Weibo' : 'X 与微博的多列阅读器'}</div>
      <div style={{ fontSize: 12.5, color: 'var(--fg-disabled)', marginTop: 10, fontVariantNumeric: 'tabular-nums' }}>{isX ? 'Version 2.4.1 (1840)' : '版本 2.4.1 (1840)'}</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: 8, marginTop: 22, maxWidth: 320 }}>
        {links.map(l => <AboutLink key={l} label={l} />)}
      </div>
      <div style={{ fontSize: 11.5, color: 'var(--fg-disabled)', marginTop: 24 }}>© 2026 Riverside Studio</div>
    </div>
  );
}

function AboutLink({ label }) {
  const [h, setH] = React.useState(false);
  return (
    <button onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ height: 32, padding: '0 14px', borderRadius: 9999, border: '1px solid var(--border-default)', cursor: 'pointer',
        background: h ? 'var(--gray-100)' : 'var(--bg-base)', color: 'var(--fg-body)', fontFamily: 'var(--font-sans)', fontSize: 13, fontWeight: 600, transition: 'background .12s' }}>{label}</button>
  );
}

/* ── Window ─────────────────────────────────────────────────── */

function CatButton({ c, on, label, onClick }) {
  const [h, setH] = React.useState(false);
  const bg = on ? 'var(--accent-bg)' : h ? 'var(--gray-100)' : 'rgba(0,0,0,0)';
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 11, width: '100%', height: 38, padding: '0 10px', borderRadius: 9, border: 'none', cursor: 'pointer', textAlign: 'left',
        backgroundColor: bg, color: on ? '#fff' : 'var(--fg-body)', fontFamily: 'var(--font-sans)', fontSize: 14, fontWeight: 600 }}>
      <span style={{ display: 'inline-flex', width: 19, height: 19, color: on ? '#fff' : 'var(--fg-subdued)', flex: 'none' }}><Glyph name={c.icon} size={19} /></span>
      {label}
    </button>
  );
}

function Settings({ isX, accounts, active, themeMode, onThemeMode, prefs, setPref, onAddAccount, onClose }) {
  const [cat, setCat] = React.useState('general');
  React.useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const CATS = [
    { id: 'general',       icon: 'settings', label_x: 'General',       label_w: '通用' },
    { id: 'accounts',      icon: 'user',     label_x: 'Accounts',      label_w: '账号' },
    { id: 'appearance',    icon: 'sun',      label_x: 'Appearance',    label_w: '外观' },
    { id: 'notifications', icon: 'bell',     label_x: 'Notifications', label_w: '通知' },
    { id: 'timeline',      icon: 'list',     label_x: 'Timeline',      label_w: '时间线' },
    { id: 'developer',     icon: 'code',     label_x: 'Developer',     label_w: '开发者' },
    { id: 'about',         icon: 'info',     label_x: 'About',         label_w: '关于' },
  ];
  const meta = CATS.find(c => c.id === cat);

  return (
    <div onMouseDown={onClose} style={{ position: 'absolute', inset: 0, zIndex: 70, background: 'rgba(0,0,0,.42)', backdropFilter: 'blur(2px)', WebkitBackdropFilter: 'blur(2px)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <div onMouseDown={e => e.stopPropagation()} style={{ width: 720, maxWidth: '94%', height: 'min(580px, 88%)', background: 'var(--bg-elevated)', borderRadius: 14, border: '1px solid var(--border-default)', boxShadow: 'var(--shadow-dragged)', display: 'flex', overflow: 'hidden', ...accentVars(prefs.accent) }}>

        {/* sidebar */}
        <div style={{ width: 196, flex: 'none', background: 'var(--bg-layer-1)', borderRight: '1px solid var(--border-default)', display: 'flex', flexDirection: 'column' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 52, padding: '0 14px', flex: 'none' }}>
            <span onClick={onClose} title={isX ? 'Close' : '关闭'} style={{ width: 12, height: 12, borderRadius: '50%', background: '#ff5f57', boxShadow: 'inset 0 0 0 .5px rgba(0,0,0,.18)', cursor: 'pointer' }} />
            <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#febc2e', boxShadow: 'inset 0 0 0 .5px rgba(0,0,0,.18)' }} />
            <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#28c840', boxShadow: 'inset 0 0 0 .5px rgba(0,0,0,.18)' }} />
          </div>
          <div style={{ padding: '4px 10px', display: 'flex', flexDirection: 'column', gap: 2 }}>
            {CATS.map(c => (
              <CatButton key={c.id} c={c} on={cat === c.id} label={isX ? c.label_x : c.label_w} onClick={() => setCat(c.id)} />
            ))}
          </div>
          <div style={{ flex: 1 }} />
        </div>

        {/* content */}
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
          <div style={{ height: 52, flex: 'none', display: 'flex', alignItems: 'center', padding: '0 18px', borderBottom: '1px solid var(--border-default)' }}>
            <div style={{ fontSize: 16, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.01em' }}>{isX ? meta.label_x : meta.label_w}</div>
            <div style={{ flex: 1 }} />
            <button onClick={onClose} title={isX ? 'Done' : '完成'}
              onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-100)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
              style={{ height: 30, padding: '0 14px', borderRadius: 8, border: 'none', cursor: 'pointer', background: 'transparent', color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', fontSize: 13.5, fontWeight: 600, transition: 'background .12s' }}>{isX ? 'Done' : '完成'}</button>
          </div>
          <div className="col-scroll" style={{ flex: 1, overflowY: 'auto', padding: '20px 22px 8px' }}>
            {cat === 'general' && <GeneralPane isX={isX} prefs={prefs} setPref={setPref} />}
            {cat === 'accounts' && <AccountsPane isX={isX} accounts={accounts} active={active} onAddAccount={onAddAccount} />}
            {cat === 'appearance' && <AppearancePane isX={isX} themeMode={themeMode} onThemeMode={onThemeMode} prefs={prefs} setPref={setPref} />}
            {cat === 'notifications' && <NotificationsPane isX={isX} prefs={prefs} setPref={setPref} />}
            {cat === 'timeline' && <TimelinePane isX={isX} prefs={prefs} setPref={setPref} />}
            {cat === 'developer' && <DeveloperPane isX={isX} prefs={prefs} setPref={setPref} onClose={onClose} />}
            {cat === 'about' && <AboutPane isX={isX} prefs={prefs} />}
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { Settings, DEFAULT_PREFS, accentVars, ACCENTS });

/* ── Debug tools ──────────────────────────────────────────────────────────
   Developer affordances, gated behind a Settings switch:
     1. Raw-JSON inspector for any tweet and for a whole timeline.
     2. A network log of every (synthetic) API call the app makes, sanitized —
        cookies and bearer/CSRF tokens are stripped before anything is recorded.
     3. A floating inspector window (Network · Data tabs).

   `DebugBus` is a tiny global event bus so deeply-nested components (a post in
   a column, a row in the ··· menu) can request "show this JSON" or append a
   network entry without threading props down the whole tree. The App subscribes
   via useDebug() and renders the overlay. Loaded as Babel JSX before post.jsx. */

(function () {
  const listeners = new Set();
  const emit = () => listeners.forEach(fn => { try { fn(); } catch (e) {} });
  let seq = 0;

  // Headers we'd send, with anything sensitive redacted. Cookie is never
  // recorded at all — it's shown as ⟨stripped⟩ so it's clear it was removed.
  function safeHeaders(platform, method) {
    const h = {
      'accept': 'application/json',
      'authorization': 'Bearer ' + '•'.repeat(24) + '  ⟨redacted⟩',
      'user-agent': platform === 'weibo' ? 'Perch/2.4.1 (macOS; weibo)' : 'Perch/2.4.1 (macOS; x)',
      'cookie': '⟨stripped⟩',
    };
    if (method && method !== 'GET') {
      h['content-type'] = 'application/json; charset=utf-8';
      h['x-csrf-token'] = '•'.repeat(16) + '  ⟨redacted⟩';
    }
    return h;
  }

  const DebugBus = {
    cfg: { enabled: false, jsonInline: true, netLog: true },
    reqs: [],
    modal: null, // { kind:'json', title, subtitle, data } | { kind:'inspector', tab }
    MAX: 400,

    enabled() { return this.cfg.enabled; },
    inline() { return this.cfg.enabled && this.cfg.jsonInline; },
    configure(patch) {
      this.cfg = { ...this.cfg, ...patch };
      if (!this.cfg.enabled && this.modal) this.modal = null;
      emit();
    },
    subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); },

    log(o) {
      if (!this.cfg.enabled || !this.cfg.netLog) return;
      const platform = o.platform || 'x';
      const method = o.method || 'GET';
      const status = o.status != null ? o.status : 200;
      const entry = {
        id: 'rq' + (++seq),
        ts: Date.now(),
        method, status,
        url: o.url,
        ms: o.ms != null ? Math.round(o.ms) : Math.round(40 + Math.random() * 160),
        platform,
        account: o.account || null,
        kind: o.kind || '',
        reqHeaders: safeHeaders(platform, method),
        reqBody: o.reqBody != null ? o.reqBody : null,
        resBody: o.resBody != null ? o.resBody : null,
        error: status >= 400,
      };
      this.reqs.unshift(entry);
      if (this.reqs.length > this.MAX) this.reqs.length = this.MAX;
      emit();
    },
    clear() { this.reqs = []; emit(); },

    openJson(title, data, subtitle) { if (!this.cfg.enabled) return; this.modal = { kind: 'json', title, subtitle, data }; emit(); },
    openInspector(tab) { if (!this.cfg.enabled) return; this.modal = { kind: 'inspector', tab: tab || 'network' }; emit(); },
    close() { this.modal = null; emit(); },
  };
  window.DebugBus = DebugBus;
})();

function useDebug() {
  const [, force] = React.useReducer(x => x + 1, 0);
  React.useEffect(() => window.DebugBus.subscribe(force), []);
  return window.DebugBus;
}

/* ── JSON tree ────────────────────────────────────────────────────────────
   Collapsible, syntax-colored. Chromatic tokens carry their own light/dark
   values, so the colors adapt to the theme automatically. */
const JSON_COL = {
  key: 'var(--blue-1100)',
  string: 'var(--green-1100)',
  number: 'var(--magenta-1100)',
  boolean: 'var(--purple-1100)',
  null: 'var(--fg-disabled)',
  punct: 'var(--fg-subdued)',
};

function JsonPrimitive({ value }) {
  let col = JSON_COL.null, text = String(value);
  if (typeof value === 'string') { col = JSON_COL.string; text = JSON.stringify(value); }
  else if (typeof value === 'number') { col = JSON_COL.number; }
  else if (typeof value === 'boolean') { col = JSON_COL.boolean; }
  else if (value === null || value === undefined) { col = JSON_COL.null; text = 'null'; }
  return <span style={{ color: col, wordBreak: 'break-word' }}>{text}</span>;
}

function JsonNode({ k, value, depth, last, defaultOpen }) {
  const isArr = Array.isArray(value);
  const isObj = value && typeof value === 'object';
  const [open, setOpen] = React.useState(depth < 2 ? true : !!defaultOpen);
  const indent = { paddingLeft: depth === 0 ? 0 : 15 };
  const keyEl = k != null ? <span style={{ color: JSON_COL.key }}>"{k}"</span> : null;
  const comma = last ? '' : ',';

  if (!isObj) {
    return (
      <div style={indent}>
        {keyEl}{keyEl && <span style={{ color: JSON_COL.punct }}>: </span>}
        <JsonPrimitive value={value} /><span style={{ color: JSON_COL.punct }}>{comma}</span>
      </div>
    );
  }

  const entries = isArr ? value.map((v, i) => [i, v]) : Object.keys(value).map(kk => [kk, value[kk]]);
  const open_b = isArr ? '[' : '{';
  const close_b = isArr ? ']' : '}';
  const count = entries.length;

  return (
    <div style={indent}>
      <div onClick={() => setOpen(o => !o)} style={{ cursor: 'pointer', display: 'inline-flex', alignItems: 'baseline', userSelect: 'none' }}>
        <span style={{ display: 'inline-block', width: 13, marginLeft: -13, color: 'var(--fg-disabled)', flex: 'none' }}>{count ? (open ? '▾' : '▸') : ''}</span>
        {keyEl}{keyEl && <span style={{ color: JSON_COL.punct }}>: </span>}
        <span style={{ color: JSON_COL.punct }}>{open_b}</span>
        {!open && <span style={{ color: 'var(--fg-disabled)' }}>{count ? ` ${count} ` : ''}{close_b}{comma}</span>}
      </div>
      {open && (
        <React.Fragment>
          {entries.map(([kk, vv], i) => (
            <JsonNode key={kk} k={isArr ? null : kk} value={vv} depth={depth + 1} last={i === count - 1} />
          ))}
          <div><span style={{ color: JSON_COL.punct }}>{close_b}{comma}</span></div>
        </React.Fragment>
      )}
    </div>
  );
}

function JsonView({ data }) {
  return (
    <div style={{ fontFamily: 'var(--font-code)', fontSize: 12.5, lineHeight: 1.65, color: 'var(--fg-body)', paddingLeft: 13 }}>
      <JsonNode value={data} depth={0} last={true} />
    </div>
  );
}

/* Copy-to-clipboard chip with a transient "Copied" confirmation. */
function CopyJsonBtn({ data, isX }) {
  const [done, setDone] = React.useState(false);
  const copy = () => {
    const txt = JSON.stringify(data, null, 2);
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(txt);
      else {
        const ta = document.createElement('textarea'); ta.value = txt; document.body.appendChild(ta); ta.select();
        document.execCommand('copy'); document.body.removeChild(ta);
      }
      setDone(true); setTimeout(() => setDone(false), 1400);
    } catch (e) {}
  };
  return (
    <button onClick={copy}
      style={{ height: 30, padding: '0 13px', borderRadius: 8, border: '1px solid var(--border-default)', cursor: 'pointer', background: 'var(--bg-base)', color: done ? 'var(--positive)' : 'var(--fg-body)', fontFamily: 'var(--font-sans)', fontSize: 13, fontWeight: 600, display: 'inline-flex', alignItems: 'center', gap: 6, transition: 'color .12s' }}>
      <span style={{ display: 'inline-flex', width: 15, height: 15 }}><Glyph name={done ? 'checkmark' : 'copy'} size={15} /></span>
      {done ? (isX ? 'Copied' : '已复制') : (isX ? 'Copy' : '复制')}
    </button>
  );
}

/* Shared dialog shell — the macOS sheet chrome used by Settings. */
function DebugSheet({ width, height, onClose, children }) {
  React.useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
  return (
    <div onMouseDown={onClose} style={{ position: 'absolute', inset: 0, zIndex: 86, background: 'rgba(0,0,0,.42)', backdropFilter: 'blur(2px)', WebkitBackdropFilter: 'blur(2px)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <div onMouseDown={e => e.stopPropagation()} style={{ width, maxWidth: '94%', height, maxHeight: '90%', background: 'var(--bg-elevated)', borderRadius: 14, border: '1px solid var(--border-default)', boxShadow: 'var(--shadow-dragged)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {children}
      </div>
    </div>
  );
}

function TrafficClose({ onClose, isX }) {
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center', flex: 'none' }}>
      <span onClick={onClose} title={isX ? 'Close' : '关闭'} style={{ width: 12, height: 12, borderRadius: '50%', background: '#ff5f57', boxShadow: 'inset 0 0 0 .5px rgba(0,0,0,.18)', cursor: 'pointer' }} />
      <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#febc2e', boxShadow: 'inset 0 0 0 .5px rgba(0,0,0,.18)' }} />
      <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#28c840', boxShadow: 'inset 0 0 0 .5px rgba(0,0,0,.18)' }} />
    </div>
  );
}

/* ── Raw-JSON modal — one tweet or one timeline ──────────────────────────── */
function JsonModal({ title, subtitle, data, isX, onClose }) {
  return (
    <DebugSheet width={560} height="min(640px, 86%)" onClose={onClose}>
      <div style={{ height: 52, flex: 'none', display: 'flex', alignItems: 'center', gap: 12, padding: '0 16px', borderBottom: '1px solid var(--border-default)' }}>
        <TrafficClose onClose={onClose} isX={isX} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 14.5, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.01em', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</div>
          {subtitle && <div style={{ fontSize: 11.5, color: 'var(--fg-subdued)', fontFamily: 'var(--font-code)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{subtitle}</div>}
        </div>
        <CopyJsonBtn data={data} isX={isX} />
      </div>
      <div className="col-scroll" style={{ flex: 1, overflow: 'auto', padding: '14px 18px 18px', background: 'var(--bg-layer-1)' }}>
        <JsonView data={data} />
      </div>
    </DebugSheet>
  );
}

/* ── Network inspector ───────────────────────────────────────────────────── */
const METHOD_COL = {
  GET: 'var(--blue-900)', POST: 'var(--green-800)', PUT: 'var(--orange-800)',
  DELETE: 'var(--red-800)', PATCH: 'var(--purple-800)',
};
function MethodChip({ method }) {
  return (
    <span style={{ flex: 'none', minWidth: 50, textAlign: 'center', height: 19, lineHeight: '19px', padding: '0 6px', borderRadius: 6, fontSize: 10, fontWeight: 800, letterSpacing: '.04em', fontFamily: 'var(--font-sans)', color: '#fff', background: METHOD_COL[method] || 'var(--gray-600)' }}>{method}</span>
  );
}
function StatusChip({ status }) {
  const ok = status < 400;
  const col = status >= 500 ? 'var(--red-900)' : status >= 400 ? 'var(--orange-900)' : 'var(--green-900)';
  return (
    <span style={{ flex: 'none', display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 12, fontWeight: 700, fontFamily: 'var(--font-code)', color: col }}>
      <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'currentColor' }} />{status}
    </span>
  );
}

function urlParts(url) {
  try { const u = new URL(url); return { host: u.host, path: u.pathname, query: u.search }; }
  catch (e) { const m = String(url).match(/^https?:\/\/([^/]+)(\/[^?]*)?(\?.*)?$/); return m ? { host: m[1], path: m[2] || '', query: m[3] || '' } : { host: '', path: String(url), query: '' }; }
}
function shortTime(ts) {
  const d = new Date(ts);
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
}

function NetRow({ req, selected, onSelect }) {
  const [h, setH] = React.useState(false);
  const { path, query } = urlParts(req.url);
  return (
    <button onClick={() => onSelect(req.id)} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 9, width: '100%', padding: '8px 12px', border: 'none', borderBottom: '1px solid var(--border-default)', cursor: 'pointer', textAlign: 'left',
        background: selected ? 'color-mix(in srgb, var(--accent) 12%, transparent)' : h ? 'var(--gray-75)' : 'transparent', transition: 'background .1s' }}>
      <MethodChip method={req.method} />
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'block', fontSize: 12.5, fontWeight: 600, fontFamily: 'var(--font-code)', color: req.error ? 'var(--negative)' : 'var(--fg-heading)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{path}</span>
        <span style={{ display: 'block', fontSize: 11, color: 'var(--fg-subdued)', fontFamily: 'var(--font-code)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{query || '—'}</span>
      </span>
      <span style={{ flex: 'none', textAlign: 'right' }}>
        <StatusChip status={req.status} />
        <span style={{ display: 'block', fontSize: 10.5, color: 'var(--fg-disabled)', fontFamily: 'var(--font-code)', marginTop: 1 }}>{req.ms}ms</span>
      </span>
    </button>
  );
}

function KVBlock({ title, obj }) {
  if (!obj) return null;
  return (
    <div style={{ marginBottom: 14 }}>
      <div style={{ fontSize: 10.5, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.06em', color: 'var(--fg-subdued)', marginBottom: 6 }}>{title}</div>
      <div style={{ background: 'var(--bg-base)', border: '1px solid var(--border-default)', borderRadius: 9, padding: '8px 11px', fontFamily: 'var(--font-code)', fontSize: 12 }}>
        {Object.keys(obj).map((k, i) => {
          const redacted = /redacted|stripped/i.test(String(obj[k]));
          return (
            <div key={k} style={{ display: 'flex', gap: 10, padding: '3px 0', borderTop: i ? '1px solid var(--border-default)' : 'none', alignItems: 'baseline' }}>
              <span style={{ color: JSON_COL.key, flex: 'none', minWidth: 96 }}>{k}</span>
              <span style={{ color: redacted ? 'var(--fg-disabled)' : 'var(--fg-body)', wordBreak: 'break-word', flex: 1, minWidth: 0, fontStyle: redacted ? 'italic' : 'normal' }}>{String(obj[k])}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function NetDetail({ req, isX }) {
  if (!req) {
    return (
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', color: 'var(--fg-subdued)', padding: 24, textAlign: 'center' }}>
        <span style={{ display: 'inline-flex', width: 30, height: 30, color: 'var(--fg-disabled)', marginBottom: 10 }}><Glyph name="code" size={30} /></span>
        <div style={{ fontSize: 13.5 }}>{isX ? 'Select a request to inspect it' : '选择一个请求查看详情'}</div>
      </div>
    );
  }
  const { host, path, query } = urlParts(req.url);
  return (
    <div className="col-scroll" style={{ flex: 1, overflow: 'auto', padding: '14px 16px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
        <MethodChip method={req.method} /><StatusChip status={req.status} />
        <span style={{ marginLeft: 'auto', fontSize: 11.5, color: 'var(--fg-disabled)', fontFamily: 'var(--font-code)' }}>{req.ms}ms · {shortTime(req.ts)}</span>
      </div>
      <div style={{ background: 'var(--bg-base)', border: '1px solid var(--border-default)', borderRadius: 9, padding: '9px 11px', marginBottom: 14, fontFamily: 'var(--font-code)', fontSize: 12, lineHeight: 1.5, wordBreak: 'break-all' }}>
        <span style={{ color: 'var(--fg-subdued)' }}>{host}</span>
        <span style={{ color: 'var(--fg-heading)', fontWeight: 700 }}>{path}</span>
        <span style={{ color: 'var(--accent)' }}>{query}</span>
      </div>
      <KVBlock title={isX ? 'Request headers' : '请求头'} obj={req.reqHeaders} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, margin: '0 0 12px', fontSize: 11.5, color: 'var(--fg-subdued)' }}>
        <span style={{ display: 'inline-flex', width: 14, height: 14, color: 'var(--positive)' }}><Glyph name="lock" size={14} /></span>
        {isX ? 'Cookies and tokens are stripped before logging.' : 'Cookie 与令牌已在记录前脱敏。'}
      </div>
      {req.reqBody != null && (
        <div style={{ marginBottom: 14 }}>
          <div style={{ fontSize: 10.5, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.06em', color: 'var(--fg-subdued)', marginBottom: 6 }}>{isX ? 'Request payload' : '提交数据'}</div>
          <div style={{ background: 'var(--bg-base)', border: '1px solid var(--border-default)', borderRadius: 9, padding: '10px 12px' }}><JsonView data={req.reqBody} /></div>
        </div>
      )}
      {req.resBody != null && (
        <div>
          <div style={{ fontSize: 10.5, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.06em', color: 'var(--fg-subdued)', marginBottom: 6 }}>{isX ? 'Response' : '响应'}</div>
          <div style={{ background: 'var(--bg-base)', border: '1px solid var(--border-default)', borderRadius: 9, padding: '10px 12px' }}><JsonView data={req.resBody} /></div>
        </div>
      )}
    </div>
  );
}

function NetworkTab({ bus, isX }) {
  const [sel, setSel] = React.useState(null);
  const reqs = bus.reqs;
  const cur = reqs.find(r => r.id === sel) || null;
  return (
    <div style={{ flex: 1, minHeight: 0, display: 'flex' }}>
      <div style={{ width: 318, flex: 'none', borderRight: '1px solid var(--border-default)', display: 'flex', flexDirection: 'column', minHeight: 0 }}>
        <div style={{ height: 36, flex: 'none', display: 'flex', alignItems: 'center', gap: 8, padding: '0 12px', borderBottom: '1px solid var(--border-default)', background: 'var(--bg-layer-1)' }}>
          <span style={{ fontSize: 11.5, fontWeight: 700, color: 'var(--fg-subdued)' }}>{reqs.length} {isX ? (reqs.length === 1 ? 'request' : 'requests') : '个请求'}</span>
          <button onClick={() => { bus.clear(); setSel(null); }} disabled={!reqs.length}
            style={{ marginLeft: 'auto', height: 24, padding: '0 9px', borderRadius: 7, border: '1px solid var(--border-default)', cursor: reqs.length ? 'pointer' : 'default', background: 'var(--bg-base)', color: reqs.length ? 'var(--fg-body)' : 'var(--fg-disabled)', fontSize: 12, fontWeight: 600, fontFamily: 'var(--font-sans)', display: 'inline-flex', alignItems: 'center', gap: 5 }}>
            <span style={{ display: 'inline-flex', width: 13, height: 13 }}><Glyph name="trash" size={13} /></span>{isX ? 'Clear' : '清空'}
          </button>
        </div>
        <div className="col-scroll" style={{ flex: 1, overflow: 'auto', minHeight: 0 }}>
          {reqs.length ? reqs.map(r => <NetRow key={r.id} req={r} selected={r.id === sel} onSelect={setSel} />) : (
            <div style={{ padding: '48px 22px', textAlign: 'center', color: 'var(--fg-subdued)' }}>
              <div style={{ fontSize: 14, fontWeight: 700, color: 'var(--fg-heading)', marginBottom: 5 }}>{isX ? 'No requests yet' : '暂无请求'}</div>
              <div style={{ fontSize: 12.5, lineHeight: 1.5 }}>{isX ? 'Refresh a column, like a post, or compose — calls show up here.' : '刷新分栏、点赞或发帖，请求会显示在这里。'}</div>
            </div>
          )}
        </div>
      </div>
      <NetDetail req={cur} isX={isX} />
    </div>
  );
}

function DataTab({ sources, isX }) {
  const [sel, setSel] = React.useState(sources[0] ? sources[0].id : null);
  const cur = sources.find(s => s.id === sel) || sources[0];
  const data = cur ? cur.get() : null;
  return (
    <div style={{ flex: 1, minHeight: 0, display: 'flex' }}>
      <div style={{ width: 230, flex: 'none', borderRight: '1px solid var(--border-default)', display: 'flex', flexDirection: 'column', minHeight: 0 }}>
        <div style={{ height: 36, flex: 'none', display: 'flex', alignItems: 'center', padding: '0 12px', borderBottom: '1px solid var(--border-default)', background: 'var(--bg-layer-1)', fontSize: 11.5, fontWeight: 700, color: 'var(--fg-subdued)' }}>{isX ? 'Open columns' : '当前分栏'}</div>
        <div className="col-scroll" style={{ flex: 1, overflow: 'auto', minHeight: 0, padding: 6 }}>
          {sources.map((s, i) => {
            const on = (cur && s.id === cur.id);
            return (
              <button key={s.id} onClick={() => setSel(s.id)}
                style={{ display: 'flex', alignItems: 'center', gap: 9, width: '100%', padding: '8px 9px', borderRadius: 9, border: 'none', cursor: 'pointer', textAlign: 'left', background: on ? 'var(--gray-100)' : 'transparent' }}
                onMouseEnter={e => { if (!on) e.currentTarget.style.background = 'var(--gray-75)'; }} onMouseLeave={e => { if (!on) e.currentTarget.style.background = 'transparent'; }}>
                <span style={{ display: 'inline-flex', width: 17, height: 17, color: 'var(--fg-subdued)', flex: 'none' }}><Glyph name={s.icon} size={17} /></span>
                <span style={{ flex: 1, minWidth: 0 }}>
                  <span style={{ display: 'block', fontSize: 13, fontWeight: 700, color: 'var(--fg-heading)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{s.label}</span>
                  <span style={{ display: 'block', fontSize: 11, color: 'var(--fg-subdued)' }}>{s.sub} · {s.count} {isX ? 'items' : '条'}</span>
                </span>
                <span style={{ flex: 'none' }}><PlatformBadge platform={s.platform} size={13} /></span>
              </button>
            );
          })}
        </div>
        <div style={{ flex: 'none', padding: 10, borderTop: '1px solid var(--border-default)' }}>
          {data && <CopyJsonBtn data={data} isX={isX} />}
        </div>
      </div>
      <div className="col-scroll" style={{ flex: 1, overflow: 'auto', padding: '14px 16px', background: 'var(--bg-layer-1)' }}>
        {data ? <JsonView data={data} /> : <div style={{ color: 'var(--fg-subdued)', fontSize: 13.5, padding: 20 }}>{isX ? 'No data' : '暂无数据'}</div>}
      </div>
    </div>
  );
}

function DebugInspector({ bus, tab, sources, isX, onClose }) {
  const [active, setActive] = React.useState(tab || 'network');
  const Tab = ({ id, label, count }) => {
    const on = active === id;
    return (
      <button onClick={() => setActive(id)}
        style={{ height: 30, padding: '0 14px', borderRadius: 9999, border: 'none', cursor: 'pointer', fontFamily: 'var(--font-sans)', fontSize: 13, fontWeight: 700,
          background: on ? 'var(--bg-elevated)' : 'transparent', color: on ? 'var(--fg-heading)' : 'var(--fg-subdued)', boxShadow: on ? 'var(--shadow-emphasized)' : 'none', display: 'inline-flex', alignItems: 'center', gap: 6 }}>
        {label}{count != null && <span style={{ fontSize: 11, fontWeight: 700, color: on ? 'var(--accent)' : 'var(--fg-disabled)' }}>{count}</span>}
      </button>
    );
  };
  return (
    <DebugSheet width={860} height="min(620px, 88%)" onClose={onClose}>
      <div style={{ height: 52, flex: 'none', display: 'flex', alignItems: 'center', gap: 14, padding: '0 16px', borderBottom: '1px solid var(--border-default)' }}>
        <TrafficClose onClose={onClose} isX={isX} />
        <div style={{ fontSize: 14.5, fontWeight: 800, color: 'var(--fg-heading)', letterSpacing: '-.01em' }}>{isX ? 'Inspector' : '调试检查器'}</div>
        <div style={{ marginLeft: 8, display: 'inline-flex', background: 'var(--gray-100)', borderRadius: 9999, padding: 2, gap: 2 }}>
          <Tab id="network" label={isX ? 'Network' : '网络'} count={bus.reqs.length} />
          <Tab id="data" label={isX ? 'Data' : '数据'} count={sources.length} />
        </div>
        <div style={{ flex: 1 }} />
        <button onClick={onClose} onMouseEnter={e => e.currentTarget.style.background = 'var(--gray-100)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
          style={{ height: 30, padding: '0 14px', borderRadius: 8, border: 'none', cursor: 'pointer', background: 'transparent', color: 'var(--fg-subdued)', fontFamily: 'var(--font-sans)', fontSize: 13.5, fontWeight: 600, transition: 'background .12s' }}>{isX ? 'Done' : '完成'}</button>
      </div>
      {active === 'network' ? <NetworkTab bus={bus} isX={isX} /> : <DataTab sources={sources} isX={isX} />}
    </DebugSheet>
  );
}

/* The overlay layer the App renders. Reads the current modal off the bus. */
function DebugLayer({ bus, sources, isX }) {
  const m = bus.modal;
  if (!m) return null;
  if (m.kind === 'json') return <JsonModal title={m.title} subtitle={m.subtitle} data={m.data} isX={isX} onClose={() => bus.close()} />;
  if (m.kind === 'inspector') return <DebugInspector bus={bus} tab={m.tab} sources={sources} isX={isX} onClose={() => bus.close()} />;
  return null;
}

Object.assign(window, { useDebug, JsonView, JsonModal, DebugInspector, DebugLayer, CopyJsonBtn });

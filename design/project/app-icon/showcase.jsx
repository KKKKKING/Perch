/* Presentation scaffold: shows each icon concept the way you'd actually judge
   an app icon — a hero render with a real dock drop-shadow, a size ramp down
   to the menu-bar glyph, and a dark-desktop check. */

function IconTile({ Comp, size, shadow = true }) {
  const uid = React.useId().replace(/:/g, '');
  return (
    <div style={{ width: size, height: size, flex: 'none',
      filter: shadow ? 'drop-shadow(0 ' + Math.max(2, size * 0.05) + 'px ' + Math.max(5, size * 0.11) + 'px rgba(20,18,30,.32))' : 'none' }}>
      <Comp uid={uid + size} />
    </div>
  );
}

function Showcase({ Comp, name, blurb }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
      {/* hero on a light desktop swatch */}
      <div style={{ borderRadius: 16, padding: '34px 24px 30px', display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: 'radial-gradient(120% 130% at 30% 0%, #eef1f7, #d8dfec 78%)', border: '1px solid var(--gray-200)' }}>
        <IconTile Comp={Comp} size={176} />
      </div>

      {/* title */}
      <div style={{ padding: '0 2px' }}>
        <div style={{ fontFamily: 'var(--font-serif)', fontSize: 21, fontWeight: 700, color: 'var(--fg-heading)', letterSpacing: '-.01em' }}>{name}</div>
        <div style={{ fontFamily: 'var(--font-sans)', fontSize: 13.5, lineHeight: 1.5, color: 'var(--fg-subdued)', marginTop: 4, textWrap: 'pretty' }}>{blurb}</div>
      </div>

      {/* size ramp + dark check */}
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 20, borderRadius: 14, padding: '20px 22px',
        background: 'var(--gray-75)', border: '1px solid var(--gray-200)' }}>
        {[128, 64, 32, 16].map(s => (
          <div key={s} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 9 }}>
            <IconTile Comp={Comp} size={s} shadow={s >= 32} />
            <span style={{ fontFamily: 'var(--font-code)', fontSize: 10.5, color: 'var(--fg-subdued)' }}>{s}</span>
          </div>
        ))}
        {/* dark desktop check */}
        <div style={{ marginLeft: 'auto', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 9 }}>
          <div style={{ borderRadius: 14, padding: 16, background: 'radial-gradient(120% 130% at 30% 0%, #2a2730, #131216 70%)' }}>
            <IconTile Comp={Comp} size={72} />
          </div>
          <span style={{ fontFamily: 'var(--font-code)', fontSize: 10.5, color: 'var(--fg-subdued)' }}>dark</span>
        </div>
      </div>
    </div>
  );
}

window.Showcase = Showcase;

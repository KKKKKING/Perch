/* ── Timeline feed store: gap detection + merging ───────────────────────────
   Models a server-side feed per column signature. Every post carries an
   integer `_seq` (higher = newer). A moving `frontier` marks the newest
   post that exists on the "server". A fetch returns a bounded PAGE of posts
   — so if more than one page of posts arrived since the loaded view's top,
   the page can't reach the old top and a GAP remains between the two.

   The loaded VIEW is an ordered (newest→oldest) array whose entries are
   either post objects (with `_seq`) or gap markers:
       { _gap: true, id, aboveSeq, belowSeq }
   `aboveSeq` = lowest seq of the segment ABOVE the gap (older edge of the
   newer block); `belowSeq` = highest seq of the segment BELOW it. The
   missing range is (belowSeq, aboveSeq) exclusive.

   Merge rules (this is the whole feature):
   • Refresh → fetchLatest(). If the page overlaps / is contiguous with the
     current top → merge seamlessly, no gap. If it doesn't reach the top →
     insert a gap between the new block and the old view.
   • Tap a gap → fetchBelow(aboveSeq), loading DOWN from the post above it.
     If that page reaches the segment below → merge, gap removed. Otherwise
     the gap shrinks and moves down to its new correct position. */

(function () {
  // Fresh-arrival copy, on-brand for the app (design / native Mac / photography).
  const FRESH_X = [
    'just pushed the gap-detection logic for the timeline. if a refresh can\u2019t reach your old top, you get a tappable break instead of silently dropping posts.',
    'unpopular opinion: a perfectly seamless infinite feed is a feature for the platform, not for you. a visible \u201cyou missed 40 posts\u201d break respects your time more.',
    'tiny detail i love in good readers: the broken-timeline marker. it admits the feed has holes instead of pretending it caught everything.',
    'spent an hour tuning the page size. too small and you get gaps constantly; too big and the fetch is slow. 20 feels right for a calm column.',
    'reminder that \u201cmark all as read\u201d and \u201cload the gap\u201d are different verbs and good clients keep them separate.',
    'the nicest thing about column-based readers is each column keeps its own scroll + its own unread math. they don\u2019t fight each other.',
    'shipped a thing: hover a post for half a second and the toolbar fades in. no layout shift, just opacity. small moves.',
    'rebuilt the refresh control so it spins in place instead of yanking the list. motion should report status, not punish you.',
    'a hairline and a one-step-darker hover still beats a drop shadow 90% of the time. shadows are for things that actually float.',
    'three columns, two accounts, one keyboard. that\u2019s the whole pitch. everything else is restraint.',
    'note to self: never auto-scroll the user. surface a count, let them tap. the timeline is theirs, not yours.',
    'dark mode isn\u2019t \u201cinvert everything\u201d. it\u2019s a separate palette where the grays lift and the accent gets a touch brighter.',
  ];
  const FRESH_W = [
    '\u521a\u628a\u65f6\u95f4\u7ebf\u7684\u201c\u65ad\u70b9\u201d\u903b\u8f91\u505a\u4e86\uff1a\u5237\u65b0\u65f6\u5982\u679c\u63a5\u4e0d\u4e0a\u4e0a\u4e00\u6b21\u7684\u4f4d\u7f6e\uff0c\u5c31\u7559\u4e2a\u53ef\u70b9\u51fb\u7684\u7f3a\u53e3\uff0c\u800c\u4e0d\u662f\u9ed8\u9ed8\u4e22\u6389\u4e2d\u95f4\u7684\u5185\u5bb9\u3002',
    '\u4e00\u76f4\u89c9\u5f97\uff1a\u65e0\u7f1d\u7684\u65e0\u9650\u4fe1\u606f\u6d41\u662f\u5e73\u53f0\u7684\u529f\u80fd\uff0c\u4e0d\u662f\u4f60\u7684\u3002\u4e00\u4e2a\u660e\u786e\u7684\u201c\u4f60\u9519\u8fc7\u4e86 40 \u6761\u201d\u7684\u65ad\u70b9\uff0c\u53cd\u800c\u66f4\u5c0a\u91cd\u4f7f\u7528\u8005\u3002',
    '\u597d\u7684\u9605\u8bfb\u5668\u90fd\u6709\u4e2a\u7ec6\u8282\uff1a\u65f6\u95f4\u7ebf\u7684\u65ad\u70b9\u6807\u8bb0\u3002\u5b83\u8001\u5b9e\u627f\u8ba4\u4fe1\u606f\u6d41\u6709\u7f3a\u53e3\uff0c\u800c\u4e0d\u662f\u88c5\u4f5c\u90fd\u62ec\u5168\u4e86\u3002',
    '\u8c03\u4e86\u4e00\u4e2a\u5c0f\u65f6\u7684\u5206\u9875\u5927\u5c0f\u3002\u592a\u5c0f\u4f1a\u4e00\u76f4\u51fa\u73b0\u65ad\u70b9\uff0c\u592a\u5927\u52a0\u8f7d\u53c8\u6162\u3002\u4e00\u9875 20 \u6761\u521a\u521a\u597d\u3002',
    '\u201c\u5168\u90e8\u6807\u4e3a\u5df2\u8bfb\u201d\u548c\u201c\u52a0\u8f7d\u65ad\u70b9\u201d\u662f\u4e24\u4e2a\u52a8\u4f5c\uff0c\u597d\u7684\u5ba2\u6237\u7aef\u4f1a\u628a\u5b83\u4eec\u5206\u5f00\u3002',
    '\u591a\u5217\u9605\u8bfb\u5668\u6700\u8212\u670d\u7684\u4e00\u70b9\uff1a\u6bcf\u4e00\u5217\u90fd\u6709\u81ea\u5df1\u7684\u6eda\u52a8\u4f4d\u7f6e\u548c\u672a\u8bfb\u8ba1\u6570\uff0c\u4e92\u4e0d\u5e72\u6270\u3002',
    '\u4e0a\u7ec4\u56fe\uff1a\u6e05\u6668\u516d\u70b9\u7684\u5929\u53f0\uff0c\u4e91\u538b\u5f97\u5f88\u4f4e\u3002\u80f6\u7247\u62cd\u51fa\u6765\u7684\u7070\u84dd\u8272\u7279\u522b\u8010\u770b\u3002',
    '\u628a\u5237\u65b0\u6309\u94ae\u91cd\u505a\u4e86\uff1a\u539f\u5730\u65cb\u8f6c\uff0c\u4e0d\u518d\u731b\u5730\u628a\u5217\u8868\u5f80\u4e0a\u62fd\u3002\u52a8\u753b\u662f\u6c47\u62a5\u72b6\u6001\u7684\uff0c\u4e0d\u662f\u60e9\u7f5a\u4f60\u7684\u3002',
    '\u4e00\u6839 1px \u7684\u63cf\u8fb9\u52a0\u4e0a\u60ac\u505c\u65f6\u6df1\u4e00\u6863\u7684\u5e95\u8272\uff0c\u5c31\u6709\u4e86\u516b\u6210\u201c\u88ab\u8bbe\u8ba1\u8fc7\u201d\u7684\u611f\u89c9\u3002',
    '\u4e09\u5217\u3001\u4e24\u4e2a\u8d26\u53f7\u3001\u4e00\u5957\u5feb\u6377\u952e\u3002\u6574\u4e2a\u601d\u8def\u5c31\u8fd9\u4e48\u591a\uff0c\u5176\u4f59\u7684\u90fd\u662f\u514b\u5236\u3002',
    '\u63d0\u9192\u81ea\u5df1\uff1a\u6c38\u8fdc\u4e0d\u8981\u66ff\u7528\u6237\u81ea\u52a8\u6eda\u5c4f\u3002\u663e\u793a\u4e2a\u8ba1\u6570\uff0c\u8ba9\u4ed6\u4eec\u81ea\u5df1\u70b9\u3002\u65f6\u95f4\u7ebf\u662f\u4ed6\u4eec\u7684\u3002',
    '\u6df1\u8272\u6a21\u5f0f\u4e0d\u662f\u201c\u628a\u4ec0\u4e48\u90fd\u53cd\u8fc7\u6765\u201d\uff0c\u800c\u662f\u4e00\u5957\u5355\u72ec\u8c03\u8fc7\u7684\u8c03\u8272\uff1a\u7070\u5ea6\u63d0\u4e9b\uff0c\u4e3b\u8272\u4eae\u4e00\u70b9\u3002',
  ];
  const TIMES_X = ['now', '1m', '2m', '4m', '6m', '9m', '12m'];
  const TIMES_W = ['\u521a\u521a', '1\u5206\u949f\u524d', '3\u5206\u949f\u524d', '5\u5206\u949f\u524d', '8\u5206\u949f\u524d', '12\u5206\u949f\u524d'];

  function rng(seedStr) {
    let s = 2166136261 >>> 0;
    for (const c of String(seedStr)) { s ^= c.charCodeAt(0); s = Math.imul(s, 16777619) >>> 0; }
    return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; };
  }
  const pickN = (arr, r) => arr[Math.floor(r() * arr.length)];

  function gradList() {
    const G = window.G || {};
    return Object.values(G).filter(Boolean);
  }

  // Generate one synthetic post for a feed, at sequence `seq`.
  function genPost(store, seq) {
    const r = store.rand;
    const plat = store.platform;
    const all = Object.values(window.P || {}).filter(p => p.platform === plat);
    let people = all;
    if (store.feed === 'following' && window.FOLLOWED && window.FOLLOWED[plat]) {
      const set = window.FOLLOWED[plat];
      const f = all.filter(p => set.includes(p.handle));
      if (f.length) people = f;
    }
    const author = pickN(people, r) || all[0];
    const pool = plat === 'x' ? FRESH_X : FRESH_W;
    const text = pool[Math.floor(r() * pool.length)];
    const stats = plat === 'x'
      ? { replies: Math.floor(r() * 30), reposts: Math.floor(r() * 80), likes: Math.floor(r() * 600), views: (1 + Math.floor(r() * 60)) + 'K' }
      : { replies: Math.floor(r() * 60), reposts: Math.floor(r() * 120), likes: Math.floor(r() * 2000) };
    const post = {
      id: store.idPrefix + '_g' + seq,
      author, text, _seq: seq,
      time: plat === 'x' ? pickN(TIMES_X, r) : pickN(TIMES_W, r),
      stats, liked: false, reposted: false, bookmarked: false, _generated: true,
    };
    const grads = gradList();
    if (grads.length && r() < 0.26) {
      const n = 1 + Math.floor(r() * 2);
      post.media = { type: 'images', items: Array.from({ length: n }, () => ({ grad: pickN(grads, r) })) };
    }
    return post;
  }

  const stores = {};

  const FeedStore = {
    // Create (once) the server feed for a column signature. `basePosts` is the
    // existing static timeline for that column (newest-first). It becomes the
    // initially-loaded block; generated posts arrive newer (via publish) and
    // older (below) it.
    ensure(sig, platform, basePosts, opts) {
      if (stores[sig]) return stores[sig];
      const BASE = 1000000;
      const bySeq = new Map();
      const base = (basePosts || []).map((p, i) => {
        const seq = BASE - i;
        const q = { ...p, _seq: seq };
        bySeq.set(seq, q);
        return q;
      });
      const st = {
        sig, platform, feed: (opts && opts.feed) || 'foryou',
        idPrefix: sig.replace(/[^a-z0-9]/gi, '').slice(0, 18) || 'feed',
        bySeq, BASE, baseLow: BASE - base.length + 1,
        frontier: BASE, base,
        rand: rng(sig + '|gen'),
      };
      stores[sig] = st;
      // seed any already-composed (user) posts on top, oldest→newest so the
      // newest ends up with the highest seq.
      const inj = (opts && opts.injected) || [];
      for (let i = inj.length - 1; i >= 0; i--) this.publishPost(sig, inj[i]);
      return st;
    },
    has(sig) { return !!stores[sig]; },
    frontier(sig) { const s = stores[sig]; return s ? s.frontier : 0; },

    // Drop a feed's server-side cache entirely. Next ensure() rebuilds it from
    // the source timeline (frontier reset to base) — i.e. "empty cache".
    reset(sig) { delete stores[sig]; },

    // The initial loaded view = the current server snapshot, newest→oldest,
    // with no gaps (a fresh column is caught up).
    initialView(sig) {
      const s = stores[sig]; if (!s) return [];
      const out = [];
      for (let seq = s.frontier; seq >= s.baseLow; seq--) { const p = s.bySeq.get(seq); if (p) out.push(p); }
      return out;
    },

    // Publish `n` brand-new posts to the server (advances the frontier). These
    // are NOT auto-loaded — they wait until a fetch pulls them in.
    publish(sig, n) {
      const s = stores[sig]; if (!s) return 0;
      for (let i = 0; i < n; i++) { const seq = s.frontier + 1; s.bySeq.set(seq, genPost(s, seq)); s.frontier = seq; }
      return s.frontier;
    },

    // Publish a specific post (e.g. the user's own compose) as the newest.
    // Returns the seq-stamped copy stored on the server.
    publishPost(sig, post) {
      const s = stores[sig]; if (!s) return null;
      const seq = s.frontier + 1; const q = { ...post, _seq: seq };
      s.bySeq.set(seq, q); s.frontier = seq; return q;
    },

    // Newest page available on the server (top `pageSize`, newest-first).
    fetchLatest(sig, pageSize) {
      const s = stores[sig]; if (!s) return [];
      const out = [];
      for (let seq = s.frontier; seq > s.frontier - pageSize && seq >= s.baseLow; seq--) {
        const p = s.bySeq.get(seq); if (p) out.push(p);
      }
      return out;
    },

    // A page strictly BELOW `beforeSeq` (newest-first) — used to fill a gap by
    // loading down from the post above it.
    fetchBelow(sig, beforeSeq, pageSize) {
      const s = stores[sig]; if (!s) return [];
      const out = [];
      for (let seq = beforeSeq - 1; seq > beforeSeq - 1 - pageSize && seq >= s.baseLow; seq--) {
        const p = s.bySeq.get(seq); if (p) out.push(p);
      }
      return out;
    },

    findById(id) {
      for (const k in stores) { for (const p of stores[k].bySeq.values()) if (p.id === id) return p; }
      return null;
    },

    // Distinct authors of the posts WAITING above the loaded view's top
    // (newest-first), capped at `max`. Powers the home column's "new posts"
    // pill, which previews who you've missed rather than just a bare count.
    waitingAuthors(sig, view, max) {
      const s = stores[sig]; if (!s) return [];
      const top = this.topSeq(view || []);
      const ceil = (top == null) ? s.frontier : top;
      const seen = new Set();
      const out = [];
      for (let seq = s.frontier; seq > ceil; seq--) {
        const p = s.bySeq.get(seq);
        if (!p || !p.author) continue;
        const key = p.author.handle || p.author.name;
        if (seen.has(key)) continue;
        seen.add(key);
        out.push(p.author);
        if (max && out.length >= max) break;
      }
      return out;
    },

    // ── View helpers ──────────────────────────────────────────────
    topSeq(view) { for (const it of view) if (it && !it._gap) return it._seq; return null; },
    gapSize(gap) { return Math.max(0, (gap.aboveSeq - gap.belowSeq) - 1); },

    // Merge a freshly-fetched newest page into the view.
    // Returns { view, gap: bool, added: number }.
    applyLatest(view, page) {
      if (!page.length) return { view, gap: false, added: 0 };
      const curTop = this.topSeq(view);
      if (curTop == null) return { view: page.slice(), gap: false, added: page.length };
      const fresh = page.filter(p => p._seq > curTop);   // dedupe what we already have
      if (!fresh.length) return { view, gap: false, added: 0 };
      const pageLow = Math.min.apply(null, fresh.map(p => p._seq));
      if (pageLow <= curTop + 1) {
        // contiguous / overlapping with old top → no gap
        return { view: fresh.concat(view), gap: false, added: fresh.length };
      }
      // a hole remains between the new block and the old top
      const gap = { _gap: true, id: 'gap_' + curTop + '_' + Date.now(), aboveSeq: pageLow, belowSeq: curTop };
      return { view: fresh.concat([gap], view), gap: true, added: fresh.length };
    },

    // Fill one gap with a page fetched from below its upper edge.
    // Returns { view, resolved: bool, added: number }.
    fillGap(view, gapId, page) {
      const gi = view.findIndex(it => it && it._gap && it.id === gapId);
      if (gi === -1) return { view, resolved: true, added: 0 };
      const gap = view[gi];
      const fill = page.filter(p => p._seq > gap.belowSeq && p._seq < gap.aboveSeq);
      const pageLow = page.length ? Math.min.apply(null, page.map(p => p._seq)) : gap.belowSeq + 1;
      const before = view.slice(0, gi);
      const after = view.slice(gi + 1);
      if (pageLow <= gap.belowSeq + 1) {
        // reached the lower segment → no more gap here
        return { view: before.concat(fill, after), resolved: true, added: fill.length };
      }
      // still a hole — gap shrinks and moves down below the filled posts
      const newGap = { ...gap, aboveSeq: pageLow };
      return { view: before.concat(fill, [newGap], after), resolved: false, added: fill.length };
    },
  };

  window.FeedStore = FeedStore;
})();

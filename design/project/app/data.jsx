/* Mock data: accounts (X + Weibo, multi-account) and platform timelines. */

const ACCOUNTS = [
  { id: 'ax1', name: 'Alex Rivers', handle: 'alexrivers', platform: 'x', color: 'var(--indigo-700)', verified: true, primary: true, followers: '24.8K', following: '892', unread: 3 },
  { id: 'ax2', name: 'Riverside Studio', handle: 'riverside.co', platform: 'x', color: 'var(--seafoam-700)', verified: false, followers: '5,140', following: '210', unread: 1 },
  { id: 'aw1', name: '林深时见鹿', handle: 'deeplin', platform: 'weibo', color: 'var(--magenta-700)', verified: true, primary: true, followers: '18.2万', following: '563', unread: 12 },
  { id: 'aw2', name: '胶片日记', handle: 'filmdiary', platform: 'weibo', color: 'var(--orange-700)', verified: false, followers: '3.6万', following: '128', unread: 0 },
];

// seed unread-mention counts per account (overridable in app state)
const UNREAD_SEED = ACCOUNTS.reduce((m, a) => { m[a.id] = a.unread || 0; return m; }, {});

// People who appear as post authors
const P = {
  jules:   { name: 'Jules Tan', handle: 'julesdesigns', color: 'var(--purple-700)', verified: true, platform: 'x' },
  marco:   { name: 'Marco Vidal', handle: 'marcobuilds', color: 'var(--cyan-800)', verified: false, platform: 'x' },
  lena:    { name: 'Lena Wolfe', handle: 'lenawolfe', color: 'var(--magenta-800)', verified: true, platform: 'x' },
  devto:   { name: 'The Type Files', handle: 'typefiles', color: 'var(--orange-700)', verified: false, platform: 'x' },
  sam:     { name: 'Sam Okafor', handle: 'samok', color: 'var(--green-800)', verified: false, platform: 'x' },
  nora:    { name: 'Nora Beck', handle: 'norabeck', color: 'var(--blue-900)', verified: true, platform: 'x' },
  kit:     { name: 'Kit Andersen', handle: 'kituxd', color: 'var(--celery-800)', verified: false, platform: 'x' },
  // weibo
  qingfeng:{ name: '清风不识字', handle: 'qingfeng', color: 'var(--turquoise-800)', verified: false, platform: 'weibo' },
  sheying: { name: '城市摄影手记', handle: 'cityshot', color: 'var(--indigo-700)', verified: true, platform: 'weibo' },
  meishi:  { name: '深夜放毒', handle: 'latenightfood', color: 'var(--red-800)', verified: false, platform: 'weibo' },
  keji:    { name: '科技每日推送', handle: 'techdaily', color: 'var(--blue-900)', verified: true, platform: 'weibo' },
  lvxing:  { name: '在路上的阿野', handle: 'ayeontheroad', color: 'var(--green-700)', verified: false, platform: 'weibo' },
};

const G = {
  dusk:   ['#7c5cff', '#ff7eb6'],
  ocean:  ['#1d95e7', '#10cfa9'],
  ember:  ['#fc7d00', '#d92361'],
  forest: ['#0ba45d', '#a3c400'],
  mono:   ['#505050', '#131313'],
  candy:  ['#ff67cc', '#ffa213'],
  steel:  ['#5d89ff', '#27cad8'],
  plum:   ['#9a47e2', '#4b75ff'],
};

const X_TIMELINE = [
  {
    id: 'xt1', thread: 'th2', author: P.sam, time: '2h',
    text: 'shipping a native Mac app in 2026 is a series of small refusals. a thread on everything we said no to 🧵',
    stats: { replies: 34, reposts: 120, likes: 1480, views: '96K' },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'xt2', thread: 'th2', author: P.sam, time: '2h',
    text: 'no to the hamburger menu. a Mac app gets a real sidebar and a menu bar. if your whole nav collapses into one button, you built a phone in a window.',
    stats: { replies: 9, reposts: 22, likes: 510, views: '44K' },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'xt3', thread: 'th2', author: P.sam, time: '2h', moreReplies: true,
    text: 'no to reinventing scroll, focus rings, and right-click. the system tuned those over decades. you earn your place on the dock by respecting the platform, not fighting it.',
    stats: { replies: 17, reposts: 41, likes: 720, views: '58K' },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'xc1', thread: 'th1', author: P.lena, time: '1h',
    text: 'naming color tokens by role instead of value is the highest-leverage call a design system makes. “accent-pressed” survives a rebrand. “blue-600” does not.',
    stats: { replies: 28, reposts: 96, likes: 1840, views: '102K' },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'xc2', thread: 'th1', author: P.marco, time: '52m', moreReplies: true,
    text: 'replying to @lenawolfe — learned this mid-rebrand. renaming 400 “blue-600”s by hand is a special kind of penance. never again.',
    stats: { replies: 6, reposts: 14, likes: 380, views: '41K' },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'x0', author: P.sam, time: '6m',
    text: 'process reel from the compose redesign — the floating sheet, the character ring, the scoped account picker. a couple of stills after the clip. swipe through →',
    media: { type: 'gallery', items: [
      { kind: 'video', grad: G.ocean, dur: '0:32' },
      { kind: 'image', grad: G.steel, alt: 'The compose sheet floating over a dimmed timeline, character ring filled to about 80%.' },
      { kind: 'image', grad: G.dusk, alt: 'Account picker open inside the compose sheet, two avatars stacked with the active one ringed in blue.' },
    ] },
    stats: { replies: 17, reposts: 64, likes: 712, views: '38K' },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'xrv', author: P.kit, time: '9m',
    text: 'this 30-second teardown of native vs web-view text rendering should be required watching. watch the subpixel hinting at the very end — you can’t fake that in a browser.',
    media: { type: 'video', dur: '0:30', grad: G.steel, source: { name: 'The Type Files', handle: 'typefiles', color: 'var(--orange-700)', verified: false, platform: 'x' } },
    stats: { replies: 24, reposts: 138, likes: 1620, views: '214K' },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'x1', author: P.jules, time: '12m', pinned: false,
    text: 'spent the morning rebuilding our color tokens from scratch. the trick nobody tells you: name them by role, not by value. “accent-pressed” survives a rebrand. “blue-600” does not.',
    media: { type: 'images', items: [{ grad: G.dusk, alt: 'A grid of color swatches relabeled by role — accent, surface, pressed — instead of by hue value.' }, { grad: G.steel }] },
    stats: { replies: 48, reposts: 132, likes: 1240, views: '88K' },
    liked: true, reposted: false, bookmarked: false,
  },
  {
    id: 'x2', author: P.marco, time: '34m', repostedBy: 'Alex Rivers',
    text: 'shipping a Mac app in 2026 means earning your place on the dock. fixed sidebars, real keyboard shortcuts, no web-view shells. people can tell.',
    stats: { replies: 21, reposts: 87, likes: 642, views: '41K' },
    liked: false, reposted: true, bookmarked: true,
  },
  {
    id: 'x3', author: P.lena, time: '1h',
    text: 'new case study is live — how we redesigned a multi-column timeline reader without the columns feeling like spreadsheets. link below 👇 (no, not really, no emoji in the actual product)',
    media: { type: 'link', title: 'Designing calm density — Riverside', desc: 'A multi-column reader that stays quiet while showing more. Notes on rhythm, hairlines, and restraint.', domain: 'riverside.co', grad: G.forest },
    stats: { replies: 12, reposts: 54, likes: 398, views: '22K' },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'x4', author: P.nora, time: '2h',
    text: 'hot take: pill-shaped buttons aged better than every gradient we shipped in 2021.',
    quote: { author: P.devto, time: '5h', text: 'the rounded-everything era is a direct response to a decade of sharp, dense enterprise UI. softness reads as “approachable”.', media: { type: 'images', items: [{ grad: G.candy }] } },
    stats: { replies: 64, reposts: 210, likes: 2980, views: '154K' },
    liked: true, reposted: false, bookmarked: true,
  },
  {
    id: 'x5', author: P.sam, time: '3h',
    text: 'recorded a 40-second teardown of the new compose flow. floating sheet, scoped to one account, character ring instead of a number. feels right.',
    media: { type: 'video', dur: '0:41', grad: G.ocean },
    stats: { replies: 9, reposts: 33, likes: 287, views: '19K' },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'x6', author: P.kit, time: '4h',
    text: 'reminder that the best dark mode isn’t “invert everything”. it’s a separate, hand-tuned palette where your grays lift and your accent gets a touch brighter to hold up against the canvas.',
    stats: { replies: 7, reposts: 41, likes: 510, views: '33K' },
    liked: true, reposted: false, bookmarked: false,
  },
  {
    id: 'x7', author: P.jules, time: '6h',
    text: 'three photos from the studio wall. mood for the next release ↓',
    media: { type: 'images', items: [{ grad: G.plum, alt: 'Studio wall covered in printed mood boards, mostly violet and plum tones.' }, { grad: G.ember }, { grad: G.steel }, { grad: G.dusk }] },
    stats: { replies: 4, reposts: 18, likes: 224, views: '12K' },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'x8', author: P.marco, time: '8h',
    text: 'every productivity app eventually adds multiple accounts, then multiple columns, then a unified inbox. the question is whether you design for it on day one or bolt it on at version 4.',
    stats: { replies: 31, reposts: 76, likes: 880, views: '57K' },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'x9', author: P.lena, time: '11h',
    text: 'a hairline border and a one-step-darker hover will get you 80% of a “designed” feel. shadows are for things that actually float.',
    stats: { replies: 5, reposts: 29, likes: 471, views: '28K' },
    liked: false, reposted: false, bookmarked: true,
  },
];

const X_MENTIONS = [
  { id: 'm1', author: P.sam, time: '18m', text: '@alexrivers this is exactly the reader I’ve been wanting on the Mac. any chance of a TestFlight?', stats: { replies: 2, reposts: 1, likes: 14, views: '1.2K' }, liked: false, reposted: false, bookmarked: false },
  { id: 'm2', author: P.kit, time: '1h', text: 'replying to @alexrivers — the character ring in compose is such a nice touch, way calmer than a countdown number.', stats: { replies: 0, reposts: 3, likes: 52, views: '3.4K' }, liked: true, reposted: false, bookmarked: false },
  { id: 'm3', author: P.nora, time: '3h', text: '@alexrivers @riverside.co following both now. the column rhythm is *chef’s kiss*. how wide are they, 360?', stats: { replies: 1, reposts: 0, likes: 9, views: '890' }, liked: false, reposted: false, bookmarked: false },
];

const WEIBO_TIMELINE = [
  {
    id: 'wt1', thread: 'wth1', author: P.sheying, time: '30分钟前',
    text: '聊聊为什么还在坚持拍胶片。不是情怀——是它逼你慢下来。一卷只有 36 张，每一张都得想清楚再按。',
    stats: { replies: 42, reposts: 138, likes: 4120 },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'wt2', thread: 'wth1', author: P.sheying, time: '30分钟前',
    text: '数码最大的问题不是画质，是“反正能删”。一旦按下没有成本，人就不再认真观察了。',
    stats: { replies: 11, reposts: 26, likes: 980 },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'wt3', thread: 'wth1', author: P.sheying, time: '29分钟前', moreReplies: true,
    text: '所以给自己定了规矩：出门只带一卷，拍完就收。剩下的时间用眼睛看，不靠取景器。',
    stats: { replies: 19, reposts: 44, likes: 1360 },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'wc1', thread: 'wth2', author: P.meishi, time: '1小时前',
    text: '深夜放毒第 215 期：楼下新开的潮汕砂锅粥，蟹肉给得毫不手软。配一碟普宁豆酱，鲜到挑眉。慎点。',
    media: { type: 'images', items: [{ grad: G.ember }, { grad: G.candy }] },
    stats: { replies: 96, reposts: 241, likes: 6200 },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'wc2', thread: 'wth2', author: P.qingfeng, time: '48分钟前', moreReplies: true,
    text: '回复 @深夜放毒：这条真不该在半夜刷到，已经饿到睡不着，明天必须去打卡。',
    stats: { replies: 4, reposts: 9, likes: 210 },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'w0', author: P.lvxing, time: '5分钟前',
    text: '垭口下撤的一段路，随手拍了点视频和照片。海拔降了八百米，植被一下子就回来了。左右滑动看看 →',
    media: { type: 'gallery', items: [
      { kind: 'video', grad: G.forest, dur: '0:46' },
      { kind: 'image', grad: G.ocean, alt: '下撤途中的山脊线，云层在垭口下方缓慢流动。' },
      { kind: 'image', grad: G.mono },
      { kind: 'image', grad: G.steel, alt: '海拔降低后重新出现的高山草甸，绿意成片。' },
    ] },
    stats: { replies: 58, reposts: 176, likes: 3920 },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'wrv', author: P.qingfeng, time: '15分钟前',
    text: '转一段很值得看的视频：为什么原生客户端的文字渲染比网页套壳清晰。注意结尾那段次像素渲染——浏览器里做不出来。',
    media: { type: 'video', dur: '0:34', grad: G.steel, source: { name: '城市摄影手记', handle: 'cityshot', color: 'var(--indigo-700)', verified: true, platform: 'weibo' } },
    stats: { replies: 31, reposts: 142, likes: 2680 },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'w1', author: P.sheying, time: '8分钟前',
    text: '清晨六点的城市天台，云层压得很低。这种灰蓝色只有在雨前才会出现，胶片拍出来格外耐看。',
    media: { type: 'images', items: [{ grad: G.steel, alt: '清晨六点的城市天台，灰蓝色的低云压在楼群上方。' }, { grad: G.ocean }, { grad: G.mono }] },
    stats: { replies: 86, reposts: 342, likes: 5120 },
    liked: true, reposted: false, bookmarked: false,
  },
  {
    id: 'w2', author: P.keji, time: '25分钟前', repostedBy: '林深时见鹿',
    text: '【桌面客户端的复兴】越来越多独立开发者重新做 Mac 原生应用：固定侧栏、多列时间线、完整键盘快捷键。网页套壳的时代正在过去。',
    media: { type: 'link', title: '原生的回归：2026 桌面应用观察', desc: '为什么多列阅读器又火了，以及它对信息密度的重新定义。', domain: 'techdaily.cn', grad: G.plum },
    stats: { replies: 41, reposts: 198, likes: 1680 },
    liked: false, reposted: true, bookmarked: true,
  },
  {
    id: 'w3', author: P.meishi, time: '1小时前',
    text: '深夜放毒第 214 期：楼下新开的潮汕砂锅粥，蟹肉给得毫不手软。配一碟普宁豆酱，鲜到挑眉。',
    media: { type: 'images', items: [{ grad: G.ember }, { grad: G.candy }] },
    stats: { replies: 153, reposts: 421, likes: 8930 },
    liked: false, reposted: false, bookmarked: true,
  },
  {
    id: 'w4', author: P.qingfeng, time: '2小时前',
    text: '转发这条，是因为这句话说得太对了——“克制”不是少做，而是知道哪一笔不必画。',
    quote: { author: P.sheying, time: '5小时前', text: '好照片和好设计是一回事：留白不是空，是给眼睛喘气的地方。', media: { type: 'images', items: [{ grad: G.forest }] } },
    stats: { replies: 22, reposts: 109, likes: 1340 },
    liked: true, reposted: false, bookmarked: false,
  },
  {
    id: 'w5', author: P.lvxing, time: '3小时前',
    text: '在路上第 90 天。今天翻过垭口，海拔 4200，信号断了整整六个小时，反而是这趟最安静的一段路。',
    media: { type: 'video', dur: '1:08', grad: G.ocean },
    stats: { replies: 67, reposts: 230, likes: 4410 },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'w6', author: P.keji, time: '5小时前',
    text: '小调研：你更喜欢哪种深色模式？\nA. 纯黑（OLED 省电）\nB. 深灰（更柔和、不刺眼）\n评论区告诉我。',
    stats: { replies: 312, reposts: 88, likes: 2210 },
    liked: false, reposted: false, bookmarked: false,
  },
  {
    id: 'w7', author: P.sheying, time: '昨天 22:14',
    text: '整理今年的胶片，挑出九张最满意的。色调几乎没修，全靠当天的光。',
    media: { type: 'images', items: [{ grad: G.dusk }, { grad: G.steel }, { grad: G.mono }, { grad: G.plum }] },
    stats: { replies: 45, reposts: 167, likes: 3380 },
    liked: false, reposted: false, bookmarked: false,
  },
];

const WEIBO_MENTIONS = [
  { id: 'wm1', author: P.qingfeng, time: '12分钟前', text: '@林深时见鹿 这套多列布局做得真舒服，看微博终于不用一直切来切去了。', stats: { replies: 3, reposts: 5, likes: 88 }, liked: false, reposted: false, bookmarked: false },
  { id: 'wm2', author: P.lvxing, time: '2小时前', text: '回复 @林深时见鹿：深灰模式那条我投 B，纯黑看久了眼睛疼。', stats: { replies: 1, reposts: 2, likes: 41 }, liked: true, reposted: false, bookmarked: false },
];

function timelineFor(platform, type) {
  if (platform === 'weibo') return (type === 'mentions' ? WEIBO_MENTIONS : WEIBO_TIMELINE);
  return (type === 'mentions' ? X_MENTIONS : X_TIMELINE);
}

/* Earlier posts in the same self/conversation thread as `post`, in order.
   Used by the detail screen to show the thread context above the focal post. */
function threadAncestors(post) {
  if (!post || !post.thread) return [];
  const lists = [X_TIMELINE, WEIBO_TIMELINE];
  for (const arr of lists) {
    const idx = arr.findIndex(p => p.id === post.id);
    if (idx === -1) continue;
    const out = [];
    for (let i = idx - 1; i >= 0 && arr[i].thread === post.thread; i--) out.unshift(arr[i]);
    return out;
  }
  return [];
}

/* ── Home feed filters ──────────────────────────────────────────
   The Home column shows one of several feeds, selected from a tab
   strip under the header. Each platform names them in its own voice. */
const HOME_FEEDS = {
  x: [
    { id: 'foryou',    label: 'For you' },
    { id: 'following', label: 'Following' },
  ],
  weibo: [
    { id: 'foryou',    label: '推荐' },
    { id: 'following', label: '关注' },
    { id: 'hot',       label: '热门' },
  ],
};

// Handles the signed-in user "follows" — used to scope the Following feed.
const FOLLOWED = {
  x:     ['julesdesigns', 'marcobuilds', 'lenawolfe', 'norabeck', 'samok'],
  weibo: ['cityshot', 'techdaily', 'ayeontheroad', 'qingfeng'],
};

/* Filter/sort a merged home timeline for the chosen feed.
   foryou → the full algorithmic mix · following → only people you follow
   (plus your own posts) in time order · hot → most-liked first. */
function applyHomeFeed(posts, platform, feed) {
  if (!feed || feed === 'foryou') return posts;
  if (feed === 'hot') return [...posts].sort((a, b) => ((b.stats && b.stats.likes) || 0) - ((a.stats && a.stats.likes) || 0));
  if (feed === 'following') {
    const set = FOLLOWED[platform] || [];
    return posts.filter(p => p.author && (set.includes(p.author.handle) || ACCOUNTS.some(a => a.handle === p.author.handle)));
  }
  return posts;
}

/* Normalize any post's media into a flat list of viewer slides.
   Each slide: { kind: 'image' | 'video', grad: [c1, c2], dur? }. */
const FALLBACK_GRAD = ['#3a3a44', '#16151b'];
function mediaSlides(media) {
  if (!media) return [];
  if (media.type === 'video') return [{ kind: 'video', grad: media.grad || FALLBACK_GRAD, dur: media.dur || '0:30', alt: media.alt }];
  if (media.type === 'images') return (media.items || []).map(it => ({ kind: it.video ? 'video' : 'image', grad: it.grad || FALLBACK_GRAD, url: it.url, dur: it.dur || '0:24', alt: it.alt }));
  if (media.type === 'gallery') return (media.items || []).map(it => ({ kind: it.kind || 'image', grad: it.grad || FALLBACK_GRAD, url: it.url, dur: it.dur || '0:24', alt: it.alt }));
  return [];
}

/* ── Profiles ───────────────────────────────────────────────── */
// Per-handle bio/meta. Accounts carry their own followers/following.
const PROFILE_META = {
  // X people
  julesdesigns:  { bio: 'Design lead. Building calm, dense interfaces. Tokens, type, and a lot of restraint.', location: 'Brooklyn, NY', joined: 'Joined June 2016', followers: '48.2K', following: '612' },
  marcobuilds:   { bio: 'Indie Mac developer. Shipping native apps that earn their place on the dock.', location: 'Lisbon', joined: 'Joined Jan 2018', followers: '12.9K', following: '341' },
  lenawolfe:     { bio: 'Product designer & writer. Case studies on craft at riverside.co.', location: 'San Francisco', joined: 'Joined Sept 2014', followers: '73.5K', following: '489' },
  typefiles:     { bio: 'Notes on typography, one specimen at a time.', location: 'The internet', joined: 'Joined Feb 2020', followers: '9,140', following: '52' },
  samok:         { bio: 'Designer. Teardown videos and small interaction studies.', location: 'London', joined: 'Joined Aug 2019', followers: '21.3K', following: '780' },
  norabeck:      { bio: 'Design systems at a place you’ve heard of. Opinions are pill-shaped.', location: 'Berlin', joined: 'Joined Apr 2013', followers: '104K', following: '395' },
  kituxd:        { bio: 'UX. Dark-mode enthusiast. Hand-tuning grays since forever.', location: 'Toronto', joined: 'Joined Nov 2017', followers: '15.6K', following: '612' },
  // X accounts (own)
  alexrivers:    { bio: 'Building Perch — a calm multi-column reader for the Mac. Design + code.', location: 'San Francisco', joined: 'Joined May 2015' },
  'riverside.co':{ bio: 'Riverside Studio. We design quiet, dense software.', location: 'Remote', joined: 'Joined Jan 2020' },
  // Weibo people
  qingfeng:      { bio: '读书、写字、看云。慢一点也没关系。', location: '杭州', joined: '2015年3月加入', followers: '6.2万', following: '318' },
  cityshot:      { bio: '城市摄影师 / 胶片爱好者。用光记录日常。', location: '上海', joined: '2014年9月加入', followers: '42.7万', following: '196' },
  latenightfood: { bio: '深夜放毒博主，专治嘴馋。每晚一道，慎点。', location: '广州', joined: '2017年6月加入', followers: '88.3万', following: '412' },
  techdaily:     { bio: '每日科技推送，聊产品、设计与效率工具。', location: '北京', joined: '2013年5月加入', followers: '156万', following: '289' },
  ayeontheroad:  { bio: '在路上。徒步、骑行、慢慢走。已经第 90 天。', location: '川西', joined: '2019年7月加入', followers: '9.8万', following: '520' },
  // Weibo accounts (own)
  deeplin:       { bio: '林深时见鹿，海蓝时见鲸。记录生活里的小确幸。', location: '成都', joined: '2016年8月加入' },
  filmdiary:     { bio: '胶片日记 · 用底片写日记。', location: '南京', joined: '2018年4月加入' },
};

const PBANNERS = [G.dusk, G.ocean, G.ember, G.forest, G.steel, G.plum, G.candy, G.mono];

function profileFor(person) {
  const meta = PROFILE_META[person.handle] || {};
  const isX = person.platform === 'x';
  const seed = [...(person.handle || person.name || 'x')].reduce((s, c) => s + c.charCodeAt(0), 0);
  const g = PBANNERS[seed % PBANNERS.length];
  return {
    bio: meta.bio || (isX ? 'Here for the timeline.' : '这个人很神秘，什么都没留下。'),
    location: meta.location || (isX ? 'Earth' : '地球'),
    joined: meta.joined || (isX ? 'Joined 2021' : '2021年加入'),
    followers: person.followers || meta.followers || (isX ? '1,024' : '1.0万'),
    following: person.following || meta.following || (isX ? '286' : '286'),
    banner: `linear-gradient(120deg, ${g[0]}, ${g[1]})`,
  };
}

// Resolve a @mention/handle to a known person, an account, or a synthesized stub.
function personByHandle(handle) {
  if (!handle) return null;
  const h = String(handle).trim();
  for (const k in P) if (P[k].handle === h || P[k].name === h) return P[k];
  for (const a of ACCOUNTS) if (a.handle === h || a.name === h) return a;
  const isCJK = /[\u4e00-\u9fff]/.test(h);
  const colors = ['var(--indigo-700)', 'var(--seafoam-700)', 'var(--purple-700)', 'var(--cyan-800)', 'var(--green-700)', 'var(--orange-700)', 'var(--magenta-700)'];
  const seed = [...h].reduce((s, c) => s + c.charCodeAt(0), 0);
  return { name: h, handle: h, platform: isCJK ? 'weibo' : 'x', color: colors[seed % colors.length], verified: false };
}

/* ── Replies / comments ─────────────────────────────────────── */
const X_REPLY_POOL = [
  'this is such a clean breakdown. saving it.',
  'completely agree — naming by role changed how our whole team works.',
  'the Mac-native details really do show. love it here.',
  'okay the character ring is genuinely a great idea, stealing it.',
  'been waiting for a reader that respects density without the clutter.',
  'hairlines + a one-step-darker hover is basically the whole game tbh.',
  'this matches my experience shipping our last redesign exactly.',
  'bookmarked. going to send this to the rest of the team.',
];
const W_REPLY_POOL = [
  '说得太好了，留白真的是门学问。',
  '这组色调绝了，求个预设分享一下。',
  '终于有人把多列说明白了，先码住。',
  '深灰党表示同意，纯黑看久了真的累。',
  '蹲一个内测名额，太想用了。',
  '克制不是少做，这句话点醒我了。',
  '原生客户端确实有它不可替代的地方。',
  '转发了，这观点值得更多人看到。',
];

function repliesFor(post) {
  // keep the synthesized reply list consistent with the post's reply count:
  // a leaf with zero replies renders none, so navigating into it is honest.
  if (post && post.stats && post.stats.replies === 0) return [];
  const isX = post.author.platform === 'x';
  const pool = isX ? X_REPLY_POOL : W_REPLY_POOL;
  const people = Object.values(P).filter(p => p.platform === (isX ? 'x' : 'weibo') && p.handle !== post.author.handle);
  const seed = [...String(post.id)].reduce((s, c) => s + c.charCodeAt(0), 0);
  const n = 2 + (seed % 3); // 2–4
  const times = isX ? ['2m', '9m', '21m', '48m', '1h', '2h'] : ['3分钟前', '12分钟前', '27分钟前', '1小时前', '2小时前'];
  const out = [];
  for (let i = 0; i < n; i++) {
    const person = people[(seed + i) % people.length];
    out.push({
      id: post.id + '-r' + i, author: person, time: times[(seed + i) % times.length],
      text: pool[(seed * 7 + i * 3) % pool.length],
      stats: { likes: (seed + i * 13) % 38, replies: (seed + i) % 3 }, liked: false,
    });
  }
  return out;
}

/* ── Notifications / 消息 ─────────────────────────────────────────
   The bell column is a real notification center, not just @mentions.
   Six kinds: like · repost · follow (aggregated, avatar stacks) and
   reply · mention · quote (full engagement cards). Likes/reposts/replies
   point at one of YOUR posts (the target); mentions/quotes are the
   other person's post that names you. Every referenced post is indexed
   so tapping a row can open it in the detail thread. */

// "You" — the post author shown on your own posts that got engagement.
const SELF = {
  x:     { name: 'Alex Rivers', handle: 'alexrivers', color: 'var(--indigo-700)', verified: true, platform: 'x' },
  weibo: { name: '林深时见鹿', handle: 'deeplin', color: 'var(--magenta-700)', verified: true, platform: 'weibo' },
};

// Actor pools for avatar stacks. [name, handle, color, verified]
const mkPeople = (plat, rows) => rows.map(([name, handle, color, v]) => ({ name, handle, color, verified: !!v, platform: plat }));
const ACTORS = {
  x: mkPeople('x', [
    ['darrell', 'darrell_b', 'var(--cyan-800)', false], ['Mira Sato', 'mirasato', 'var(--purple-700)', true],
    ['Owen Pratt', 'owenp', 'var(--green-800)', false], ['Yuki', 'yukidev', 'var(--indigo-700)', false],
    ['Priya Nair', 'priyabuilds', 'var(--magenta-800)', true], ['ck1521', 'ck1521', 'var(--blue-900)', false],
    ['Tomas', 'tomasr', 'var(--seafoam-700)', false], ['Hana Lin', 'hanalin', 'var(--orange-700)', false],
    ['Dev Mehta', 'devmehta', 'var(--turquoise-800)', true], ['Sol', 'solllin', 'var(--celery-800)', true],
    ['Greta', 'gretacodes', 'var(--pink-700)', false], ['Aria', 'ariaui', 'var(--red-800)', false],
    ['Nils', 'nilsw', 'var(--brown-700)', false], ['Jess Park', 'jesspark', 'var(--cyan-700)', true],
    ['Mason', 'masonk', 'var(--indigo-800)', false], ['Iris', 'irisdesign', 'var(--purple-800)', false],
    ['Felix', 'felixq', 'var(--green-700)', false], ['Noor', 'noora', 'var(--magenta-700)', false],
  ]),
  weibo: mkPeople('weibo', [
    ['陈宏彬', 'chenhb', 'var(--cyan-800)', false], ['朱豆腐', 'zhudofu', 'var(--magenta-800)', false],
    ['念想', 'nianxiang', 'var(--purple-700)', false], ['DylanC左樹', 'dylanc', 'var(--indigo-700)', true],
    ['宇宙功德X', 'cosmic', 'var(--seafoam-700)', false], ['红桃DK', 'hongtao', 'var(--red-800)', false],
    ['无边之海', 'wbzh', 'var(--blue-900)', false], ['Solioxx1', 'solioxx', 'var(--turquoise-800)', false],
    ['忽然圆形客', 'huran', 'var(--orange-700)', false], ['冯不语', 'fengbuyu', 'var(--green-800)', false],
    ['凯', 'kaikai', 'var(--celery-800)', false], ['Vontean', 'vontean', 'var(--pink-700)', false],
    ['星辰影泓涧', 'xingchen', 'var(--purple-800)', false], ['图灵小编', 'turing', 'var(--green-700)', true],
    ['深海鱼', 'shenhaiyu', 'var(--cyan-700)', false], ['江白', 'jiangbai', 'var(--brown-700)', false],
    ['阿野在路上', 'aye2', 'var(--indigo-800)', false], ['麦麦', 'maimai', 'var(--magenta-700)', false],
  ]),
};
const pick = (plat, n, off = 0) => { const a = ACTORS[plat]; return Array.from({ length: n }, (_, i) => a[(off + i) % a.length]); };

// Your posts that received engagement (the "targets"). Indexed for detail nav.
const MY_POSTS = {
  x: [
    { id: 'mp_x1', author: SELF.x, time: '2h', text: 'shipped the compose redesign tonight — floating sheet, character ring instead of a countdown, account picker scoped to one identity. the whole thing feels calmer.', media: { type: 'images', items: [{ grad: G.steel, alt: 'The redesigned compose sheet floating over a dimmed multi-column timeline.' }, { grad: G.dusk }] }, stats: { replies: 41, reposts: 88, likes: 1240, views: '92K' }, liked: false, reposted: false, bookmarked: false },
    { id: 'mp_x2', author: SELF.x, time: '6h', text: 'a hairline border and a one-step-darker hover will get you 80% of a “designed” feel. shadows are for things that actually float.', stats: { replies: 12, reposts: 54, likes: 980, views: '61K' }, liked: false, reposted: false, bookmarked: false },
    { id: 'mp_x3', author: SELF.x, time: '1d', text: 'recorded a 40-second teardown of the multi-column reader. no web-view shell, real keyboard shortcuts, columns that don’t feel like spreadsheets.', media: { type: 'video', dur: '0:41', grad: G.ocean }, stats: { replies: 9, reposts: 33, likes: 612, views: '40K' }, liked: false, reposted: false, bookmarked: false },
  ],
  weibo: [
    { id: 'mp_w1', author: SELF.weibo, time: '3小时前', text: '把消息中心重做了一遍——点赞、转发、关注聚合成一行，评论和@单独成卡片。终于不用在一堆通知里翻来翻去了。', media: { type: 'images', items: [{ grad: G.plum, alt: '重做后的消息中心，点赞与关注被聚合为带头像堆叠的单行。' }, { grad: G.steel }] }, stats: { replies: 58, reposts: 176, likes: 3920 }, liked: false, reposted: false, bookmarked: false },
    { id: 'mp_w2', author: SELF.weibo, time: '7小时前', text: '克制不是少做，而是知道哪一笔不必画。一根 1px 的描边加上悬停时深一档的底色，就有了八成“被设计过”的感觉。', stats: { replies: 22, reposts: 109, likes: 1680 }, liked: false, reposted: false, bookmarked: false },
    { id: 'mp_w3', author: SELF.weibo, time: '昨天 21:30', text: '录了一段多列阅读器的演示。固定侧栏、完整快捷键、列与列之间留出呼吸的间距，不再像表格。', media: { type: 'video', dur: '1:02', grad: G.forest }, stats: { replies: 45, reposts: 167, likes: 2380 }, liked: false, reposted: false, bookmarked: false },
  ],
};

// Standalone posts BY others that mention or quote you (navigable).
const MENTION_POSTS = {
  x: {
    mn_x1: { id: 'mn_x1', author: ACTORS.x[4], time: '3m', text: 'replying to @alexrivers — the character ring in compose is such a nice touch, way calmer than a countdown number. how’d you tune the easing?', stats: { replies: 1, reposts: 3, likes: 52, views: '3.4K' }, liked: false, reposted: false, bookmarked: false },
    mn_x2: { id: 'mn_x2', author: ACTORS.x[8], time: '24m', text: 'this is the multi-column Mac reader I’ve wanted for years. @alexrivers any chance of a TestFlight? happy to file bugs.', media: { type: 'images', items: [{ grad: G.candy, alt: 'A screenshot of the reader running on a laptop, three columns visible.' }] }, stats: { replies: 2, reposts: 1, likes: 14, views: '1.2K' }, liked: false, reposted: false, bookmarked: false },
    mn_x3: { id: 'mn_x3', author: ACTORS.x[1], time: '11m', text: 'pill-shaped buttons aged better than every gradient we shipped in 2021, and @alexrivers’ new compose sheet is exhibit A.', quote: { author: SELF.x, time: '6h', text: 'a hairline border and a one-step-darker hover will get you 80% of a “designed” feel. shadows are for things that actually float.' }, stats: { replies: 6, reposts: 12, likes: 210, views: '18K' }, liked: false, reposted: false, bookmarked: false },
  },
  weibo: {
    mn_w1: { id: 'mn_w1', author: ACTORS.weibo[6], time: '17分钟前', text: '@林深时见鹿 这套消息中心做得真舒服，点赞聚合成一行的处理太对了。国内的客户端要是都这么克制就好了。', stats: { replies: 3, reposts: 5, likes: 88 }, liked: false, reposted: false, bookmarked: false },
    mn_w2: { id: 'mn_w2', author: ACTORS.weibo[5], time: '11分钟前', text: '老师这个多列阅读器在哪能下载？@林深时见鹿 求个内测名额，太想用了。', media: { type: 'images', items: [{ grad: G.ember, alt: '多列阅读器运行截图，三列时间线并排。' }, { grad: G.mono }] }, stats: { replies: 1, reposts: 2, likes: 41 }, liked: false, reposted: false, bookmarked: false },
    mn_w3: { id: 'mn_w3', author: ACTORS.weibo[3], time: '9分钟前', text: '转发这条，说得太对了。"克制不是少做"——这句话值得做设计的都看看。@林深时见鹿', quote: { author: SELF.weibo, time: '7小时前', text: '克制不是少做，而是知道哪一笔不必画。一根 1px 的描边加上悬停时深一档的底色，就有了八成“被设计过”的感觉。' }, stats: { replies: 5, reposts: 18, likes: 130 }, liked: false, reposted: false, bookmarked: false },
  },
};

const X_NOTIFS = [
  { id: 'nx1', kind: 'like', actors: pick('x', 9, 0), count: 37, time: '55s', unread: true, postId: 'mp_x1' },
  { id: 'nx2', kind: 'reply', actor: ACTORS.x[2], time: '1m', unread: true, postId: 'mp_x1', text: '@alexrivers this is exactly the reader I’ve been wanting on the Mac. the column rhythm is *chef’s kiss*.' },
  { id: 'nx3', kind: 'mention', time: '3m', unread: true, postId: 'mn_x1' },
  { id: 'nx4', kind: 'like', actors: pick('x', 10, 5), count: 22, time: '2m', unread: false, postId: 'mp_x2' },
  { id: 'nx5', kind: 'repost', actors: pick('x', 3, 3), count: 3, time: '4m', unread: false, postId: 'mp_x1' },
  { id: 'nx6', kind: 'follow', actors: pick('x', 6, 1), count: 6, time: '10m', unread: false },
  { id: 'nx7', kind: 'quote', time: '11m', unread: false, postId: 'mn_x3' },
  { id: 'nx8', kind: 'like', actors: pick('x', 8, 9), count: 13, time: '14m', unread: false, postId: 'mp_x3' },
  { id: 'nx9', kind: 'mention', time: '24m', unread: false, postId: 'mn_x2' },
  { id: 'nx10', kind: 'follow', actor: ACTORS.x[12], time: '40m', unread: false, single: true, bio: 'Design systems & native Mac apps. Opinions are pill-shaped.' },
  { id: 'nx11', kind: 'reply', actor: ACTORS.x[7], time: '1h', unread: false, postId: 'mp_x2', text: 'been saying this for years. hairlines do so much heavy lifting and nobody notices, which is the point.' },
  { id: 'nx12', kind: 'repost', actors: pick('x', 2, 10), count: 2, time: '1h', unread: false, postId: 'mp_x3' },
];

const WEIBO_NOTIFS = [
  { id: 'nw1', kind: 'like', actors: pick('weibo', 9, 0), count: 36, time: '1分钟前', unread: true, postId: 'mp_w1' },
  { id: 'nw2', kind: 'reply', actor: ACTORS.weibo[6], time: '6分钟前', unread: true, postId: 'mp_w1', text: '国内的客户端能不能也学学这个聚合，每次看消息都被一堆点赞淹没。' },
  { id: 'nw3', kind: 'mention', time: '17分钟前', unread: true, postId: 'mn_w1' },
  { id: 'nw4', kind: 'follow', actors: pick('weibo', 5, 2), count: 5, time: '10分钟前', unread: false },
  { id: 'nw5', kind: 'repost', actors: pick('weibo', 3, 4), count: 3, time: '4分钟前', unread: false, postId: 'mp_w1' },
  { id: 'nw6', kind: 'quote', time: '9分钟前', unread: false, postId: 'mn_w3' },
  { id: 'nw7', kind: 'like', actors: pick('weibo', 10, 6), count: 21, time: '2分钟前', unread: false, postId: 'mp_w2' },
  { id: 'nw8', kind: 'mention', time: '11分钟前', unread: false, postId: 'mn_w2' },
  { id: 'nw9', kind: 'reply', actor: ACTORS.weibo[9], time: '17分钟前', unread: false, postId: 'mp_w2', text: '这句话点醒我了，留白真的是给眼睛喘气的地方。转发收藏了。' },
  { id: 'nw10', kind: 'follow', actor: ACTORS.weibo[13], time: '23分钟前', unread: false, single: true, bio: '图灵社区 · 聊产品、设计与效率工具。' },
  { id: 'nw11', kind: 'like', actors: pick('weibo', 8, 10), count: 12, time: '14分钟前', unread: false, postId: 'mp_w3' },
  { id: 'nw12', kind: 'repost', actors: pick('weibo', 2, 11), count: 2, time: '1小时前', unread: false, postId: 'mp_w3' },
];

// Index every referenced post so the detail thread can resolve a tapped row.
const NOTIF_POST_INDEX = {};
['x', 'weibo'].forEach(plat => {
  MY_POSTS[plat].forEach(p => { NOTIF_POST_INDEX[p.id] = p; });
  Object.values(MENTION_POSTS[plat]).forEach(p => { NOTIF_POST_INDEX[p.id] = p; });
});
function notifPostById(id) { return NOTIF_POST_INDEX[id] || null; }
function notificationsFor(platform) {
  const list = platform === 'weibo' ? WEIBO_NOTIFS : X_NOTIFS;
  return list.map(n => ({ ...n, post: n.postId ? NOTIF_POST_INDEX[n.postId] : null }));
}

Object.assign(window, { ACCOUNTS, UNREAD_SEED, timelineFor, threadAncestors, mediaSlides, profileFor, personByHandle, repliesFor, HOME_FEEDS, applyHomeFeed, notificationsFor, notifPostById, SELF, P, G, FOLLOWED });

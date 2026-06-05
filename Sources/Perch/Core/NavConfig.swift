import Foundation

/// Configurable left-rail navigation — port of design/project/app/navconfig.jsx.
/// A single `{ bar, menu }` config drives both the rail's primary icons and its
/// ⋯ overflow menu; the user edits it by drag-and-drop in the Configure dialog.

struct NavItemMeta {
    let glyph: String
    let labelX: String   // English
    let labelW: String   // Chinese
}

let NAV_ITEMS: [String: NavItemMeta] = [
    "home":      NavItemMeta(glyph: "home",             labelX: "Home",          labelW: "主页"),
    "mentions":  NavItemMeta(glyph: "bell",             labelX: "Notifications", labelW: "消息"),
    "search":    NavItemMeta(glyph: "search",           labelX: "Search",        labelW: "搜索"),
    "profile":   NavItemMeta(glyph: "user",             labelX: "Profile",       labelW: "我的"),
    "bookmarks": NavItemMeta(glyph: "bookmark-outline", labelX: "Bookmarks",     labelW: "收藏"),
    "likes":     NavItemMeta(glyph: "heart-outline",    labelX: "Likes",         labelW: "赞过"),
    "lists":     NavItemMeta(glyph: "list",             labelX: "Lists",         labelW: "列表"),
]

/// Stable ordering for the "append any newly-introduced destination" heal step.
/// (Swift dictionaries are unordered; the JS relies on `Object.keys` insertion order.)
let NAV_ORDER = ["home", "mentions", "search", "profile", "bookmarks", "likes", "lists"]

struct NavConfig: Codable, Equatable {
    var bar: [String]
    var menu: [String]

    static let DEFAULT = NavConfig(bar: ["home", "mentions", "search", "profile", "bookmarks"],
                                   menu: ["likes", "lists"])

    /// Address a list by key so the drag/drop `doDrop` port reads cleanly.
    subscript(_ list: String) -> [String] {
        get { list == "bar" ? bar : menu }
        set { if list == "bar" { bar = newValue } else { menu = newValue } }
    }
}

/// Heal a persisted config: dedup, drop unknown ids, append any newly-introduced
/// destinations to the overflow menu so nothing silently disappears — then enforce
/// the Perch constraint that the sidebar always keeps at least one item.
func normalizeNav(_ n: NavConfig?) -> NavConfig {
    var cfg = NavConfig(bar: [], menu: [])
    var seen = Set<String>()
    func take(_ arr: [String], _ dst: String) {
        for id in arr where NAV_ITEMS[id] != nil && !seen.contains(id) {
            seen.insert(id)
            cfg[dst].append(id)
        }
    }
    take(n?.bar ?? [], "bar")
    take(n?.menu ?? [], "menu")
    for id in NAV_ORDER where !seen.contains(id) { cfg.menu.append(id) }
    // ≥1-bar backstop (the prototype does not enforce this).
    if cfg.bar.isEmpty, !cfg.menu.isEmpty { cfg.bar.append(cfg.menu.removeFirst()) }
    return cfg
}

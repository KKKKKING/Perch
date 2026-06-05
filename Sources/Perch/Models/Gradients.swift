import AppKit

/// The brand gradient palette used for media tiles, banners, and avatar fallbacks
/// when no real image is available.
enum Gradients {
    static let dusk = Gradient("#7c5cff", "#ff7eb6")
    static let ocean = Gradient("#1d95e7", "#10cfa9")
    static let ember = Gradient("#fc7d00", "#d92361")
    static let forest = Gradient("#0ba45d", "#a3c400")
    static let mono = Gradient("#505050", "#131313")
    static let candy = Gradient("#ff67cc", "#ffa213")
    static let steel = Gradient("#5d89ff", "#27cad8")
    static let plum = Gradient("#9a47e2", "#4b75ff")

    static let pool: [Gradient] = [dusk, ocean, ember, forest, steel, plum, candy, mono]

    /// Stable gradient pick for a string seed (e.g. a handle).
    static func forSeed(_ s: String) -> Gradient {
        var sum = 0
        for u in s.utf16 { sum = (sum &* 31 &+ Int(u)) & 0x7fffffff }
        return pool[sum % pool.count]
    }
}

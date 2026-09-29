import Foundation

/// The doomscroll comparisons from docs/DESIGN.md section 6. Pure math, rotated by index.
enum Comparisons {
    static let wordsPerToken = 0.75
    static let tokensPerSession = 1_500_000

    static let count = 4

    /// One comparison sentence for a token total. `index` picks which one; it wraps.
    static func sentence(tokens: Int, index: Int) -> String {
        let words = Double(tokens) * wordsPerToken
        // A phone feed: 8 words per line, 24 lines per 160 inches of scrolling.
        let meters = words / 8 * 24 / 160 * 0.0254
        let dist = meters >= 1000 ? "\(round1(meters / 1000)) km" : "\(Int(meters.rounded())) m"
        let tweets = words / 25
        let tweetText: String = tweets >= 1_000_000
            ? "\(round1(tweets / 1_000_000)) million"
            : "\(Int((tweets / 1000).rounded())) thousand"
        let list = [
            "On a phone, that's about \(dist) of doomscrolling.",
            "Stacked up, that feed would be \(round1(meters / 330)) Eiffel Towers tall.",
            "Doomscrolled at reading speed, that's \(round1(words / 250 / 60 / 24)) days without putting the phone down.",
            "That's roughly \(tweetText) tweets' worth of scrolling.",
        ]
        let i = ((index % list.count) + list.count) % list.count
        return list[i]
    }

    /// Round to one decimal below 10, whole numbers above, and print without a trailing `.0`.
    static func round1(_ x: Double) -> String {
        let v = x >= 10 ? x.rounded() : (x * 10).rounded() / 10
        if v == v.rounded() { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }
}

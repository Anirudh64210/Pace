import SwiftUI

/// A plain bar: track plus a used portion, and optionally a tick for an even pace.
struct UsageBar: View {
    var used: Double          // 0...100
    var height: CGFloat = 4
    var fill: Color = Theme.barFill
    /// 0...100: a thin tick for where an even pace would be.
    var marker: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(0, w * CGFloat(min(100, max(0, used)) / 100)))
                    .animation(Theme.reduceMotion ? nil : .easeInOut(duration: 0.3), value: used)
            }
            .clipShape(Capsule())
            .overlay(alignment: .leading) {
                if let marker {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.text.opacity(0.9))
                        .frame(width: 2, height: height + 6)
                        .offset(x: max(0, min(w - 2, w * CGFloat(min(100, max(0, marker)) / 100) - 1)))
                        .accessibilityLabel("Even pace")
                }
            }
        }
        .frame(height: height)
    }
}

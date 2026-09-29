import XCTest

/// A repeating `withAnimation` (repeatForever / repeatCount) wraps every change
/// in its transaction, including the panel's first layout inside the menu bar
/// window. That made the whole panel slide in from the corner forever. Repeating
/// motion must use keyframeAnimator or phaseAnimator, which are scoped to one view.
final class AnimationSafetyTests: XCTestCase {
    func testNoRepeatingTransactionAnimations() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (i, line) in text.components(separatedBy: .newlines).enumerated() {
                let code = line.components(separatedBy: "//").first ?? ""
                XCTAssertFalse(code.contains(".repeatForever(") || code.contains(".repeatCount("),
                               "\(url.lastPathComponent):\(i + 1) uses a repeating transaction animation")
            }
        }
    }
}

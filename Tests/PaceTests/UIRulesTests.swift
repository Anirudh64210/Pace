import XCTest

/// Source-level rules for the UI, checked on every test run.
final class UIRulesTests: XCTestCase {
    var uiFiles: [URL] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Pace/UI")
        return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "swift" } ?? []
    }

    /// Every button has a hover label, or says on its own line why not.
    func testEveryButtonHasAHoverLabel() throws {
        XCTAssertFalse(uiFiles.isEmpty)
        for file in uiFiles {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard code.hasPrefix("Button(") || code.hasPrefix("Button {") || code.contains(" Button(") || code.contains(" Button {") else { continue }
                if code.hasPrefix("//") || code.contains("ButtonStyle") { continue }
                if line.contains("// definer:") { continue }
                let window = lines[i..<min(lines.count, i + 16)].joined(separator: "\n")
                XCTAssertTrue(window.contains(".definer("), "\(file.lastPathComponent):\(i + 1) has a button without a hover label")
            }
        }
    }

    /// Hover labels are two words at most.
    func testHoverLabelsAreShort() throws {
        let pattern = try NSRegularExpression(pattern: #"\.definer\("([^"]*)"\)"#)
        for file in uiFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            for m in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let label = (text as NSString).substring(with: m.range(at: 1))
                XCTAssertLessThanOrEqual(label.split(separator: " ").count, 2, "\(file.lastPathComponent): \"\(label)\"")
            }
        }
    }
}

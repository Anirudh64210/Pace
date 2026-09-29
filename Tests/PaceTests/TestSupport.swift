import XCTest

extension XCTestCase {
    /// A throwaway UserDefaults store that is deleted when the test ends, so test
    /// runs never leave preference files behind.
    func scratchDefaults() -> UserDefaults {
        let name = "pace.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: name)
            let plist = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(name).plist")
            try? FileManager.default.removeItem(at: plist)
        }
        return defaults
    }
}

extension XCTestCase {
    /// Waits until `condition` is true, checking every 20 ms. Timing on shared CI
    /// runners varies a lot, so tests wait for an outcome instead of a fixed delay.
    @MainActor
    func waitUntil(timeout: TimeInterval = 5, _ what: String = "condition",
                   file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { XCTFail("timed out waiting for \(what)", file: file, line: line); return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

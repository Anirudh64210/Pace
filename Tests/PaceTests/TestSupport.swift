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

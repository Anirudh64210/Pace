import Foundation

/// Launch-time cleanup that keeps credentials off disk.
enum Hygiene {
    /// Turns off Foundation's shared HTTP cache for the whole process, and removes
    /// any cache database an earlier build left behind. macOS archives requests
    /// (with their Authorization header) inside that database, so it must not exist.
    static func run() {
        tightenDataFolder()
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, directory: nil)
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let names = Set(["Pace", Bundle.main.bundleIdentifier ?? "org.pace-menubar.Pace", "org.pace-menubar.Pace"])
        for name in names {
            let dir = caches.appendingPathComponent(name, isDirectory: true)
            for file in ["Cache.db", "Cache.db-wal", "Cache.db-shm", "fsCachedData"] {
                try? fm.removeItem(at: dir.appendingPathComponent(file))
            }
        }
    }

    /// Pace's own folder and files are readable by you only. Older builds and
    /// older status line scripts created them with default permissions.
    static func tightenDataFolder() {
        let fm = FileManager.default
        let dir = StatusLineProvider.defaultDirectory
        guard fm.fileExists(atPath: dir.path) else { return }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
            let path = dir.appendingPathComponent(name).path
            guard (try? fm.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeRegular else { continue }
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }
}

import Foundation

/// Installs `pace-statusline.sh` into Claude Code's config folder and points its
/// `statusLine` setting at it, and removes it again.
///
/// Rules, because this edits a file the user owns:
/// - A settings file that cannot be read or parsed is never overwritten.
/// - A symlinked settings file (dotfile managers) is written through, not replaced.
///   A dangling symlink is an error, not an empty file.
/// - The new file is created with the old file's permissions, never wider.
/// - If Claude Code changes the file while Pace is writing, Pace stops.
/// - A backup of the previous settings is kept until Remove.
/// - An existing status line is kept in full: its command runs through the Pace
///   script, and Remove restores the original entry exactly.
enum StatusLineInstaller {
    /// Claude Code's config folder: `$CLAUDE_CONFIG_DIR` when set, else `~/.claude`.
    /// Overridable for tests.
    nonisolated(unsafe) static var claudeDirectory: URL = {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }()

    static var defaultClaudeDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    static var scriptURL: URL { claudeDirectory.appendingPathComponent("pace-statusline.sh") }
    static var chainURL: URL { claudeDirectory.appendingPathComponent("pace-statusline-chain") }
    static var previousURL: URL { claudeDirectory.appendingPathComponent("pace-statusline-previous.json") }
    static var settingsURL: URL { claudeDirectory.appendingPathComponent("settings.json") }
    static var backupURL: URL { claudeDirectory.appendingPathComponent("settings.json.pace-backup") }

    /// The command written into settings. `~/.claude/...` for the default folder.
    static var command: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = scriptURL.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    enum Status: Equatable {
        case installed
        case notInstalled
        case otherStatusLine(String)
    }

    enum InstallError: LocalizedError, Equatable {
        case unreadableSettings
        case danglingSymlink
        case changedWhileWriting

        var errorDescription: String? {
            switch self {
            case .unreadableSettings:
                return "Claude Code's settings.json could not be read as JSON, so Pace left it alone. Fix the file, or add the status line by hand (see the README)."
            case .danglingSymlink:
                return "Claude Code's settings.json is a link to a file that no longer exists, so Pace left it alone."
            case .changedWhileWriting:
                return "Claude Code changed its settings while Pace was writing. Nothing was changed. Try again."
            }
        }
    }

    static func status() -> Status {
        guard let settings = try? readSettings(),
              let line = settings["statusLine"] as? [String: Any],
              let cmd = line["command"] as? String else { return .notInstalled }
        if isPace(cmd) { return FileManager.default.fileExists(atPath: scriptURL.path) ? .installed : .notInstalled }
        return .otherStatusLine(cmd)
    }

    static func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let before = modificationDate()
        var settings = try readSettings()   // throws before anything is written

        let previous = settings["statusLine"] as? [String: Any]
        let previousCommand = previous?["command"] as? String
        let alreadyPace = previousCommand.map(isPace) == true

        if let previous, let previousCommand, !alreadyPace {
            try writePrivate(Data(previousCommand.utf8), to: chainURL)
            try writePrivate(JSONSerialization.data(withJSONObject: previous, options: [.sortedKeys]), to: previousURL)
        }

        try writeFile(Data((StatusLineScript.contents + "\n").utf8), to: scriptURL, mode: 0o755)

        // Back up the settings as they were before Pace, not a previous Pace install.
        if fm.fileExists(atPath: settingsURL.path), !alreadyPace {
            try? fm.removeItem(at: backupURL)
            try fm.copyItem(at: settingsURL.resolvingSymlinksInPath(), to: backupURL)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        }

        // Keep any other status line fields (padding and so on).
        var line = previous ?? [:]
        line["type"] = "command"
        line["command"] = command
        settings["statusLine"] = line
        try writeSettings(settings, expectedModification: before)
    }

    /// After an update, the installed script can be an older version. If Pace's
    /// status line is installed and the script differs from this build's, rewrite
    /// it. Touches only Pace's own script, never settings.json. Returns true if it
    /// was updated.
    @discardableResult
    static func refreshInstalledScript() -> Bool {
        guard status() == .installed else { return false }
        let current = Data((StatusLineScript.contents + "\n").utf8)
        guard let installed = try? Data(contentsOf: scriptURL), installed != current else { return false }
        return (try? writeFile(current, to: scriptURL, mode: 0o755)) != nil
    }

    /// Removes the Pace status line and restores the entry it replaced, exactly.
    static func uninstall() throws {
        let fm = FileManager.default
        let before = modificationDate()
        var settings = try readSettings()
        let current = (settings["statusLine"] as? [String: Any])?["command"] as? String
        if current.map(isPace) == true {
            if let data = try? Data(contentsOf: previousURL),
               let previous = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                settings["statusLine"] = previous
            } else if let command = try? String(contentsOf: chainURL, encoding: .utf8), !command.isEmpty {
                settings["statusLine"] = ["type": "command", "command": command]
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            try writeSettings(settings, expectedModification: before)
        }
        for url in [scriptURL, chainURL, previousURL, backupURL] { try? fm.removeItem(at: url) }
        // The saved numbers go too, so the panel does not keep showing them.
        if claudeDirectory.path == defaultClaudeDirectory.path {
            try? fm.removeItem(at: StatusLineProvider.defaultFile)
        }
    }

    // MARK: - Files

    /// Only Pace's own script, by exact path. A user's own command that happens to
    /// mention "pace-statusline" is not Pace.
    static func isPace(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expanded = trimmed
            .replacingOccurrences(of: "$HOME", with: home)
            .replacingOccurrences(of: "${HOME}", with: home)
        let resolved = (expanded as NSString).expandingTildeInPath
        return resolved == scriptURL.path
    }

    /// Missing file: empty settings. Unreadable, unparseable or dangling: an error.
    static func readSettings() throws -> [String: Any] {
        let fm = FileManager.default
        let path = settingsURL.path
        let isLink = (try? fm.destinationOfSymbolicLink(atPath: path)) != nil
        if !fm.fileExists(atPath: path) {
            if isLink { throw InstallError.danglingSymlink }
            return [:]
        }
        guard let data = try? Data(contentsOf: settingsURL) else { throw InstallError.unreadableSettings }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw InstallError.unreadableSettings
        }
        return obj
    }

    private static func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: settingsURL.resolvingSymlinksInPath().path))?[.modificationDate] as? Date
    }

    private static func writeSettings(_ settings: [String: Any], expectedModification: Date?) throws {
        let target = settingsURL.resolvingSymlinksInPath()
        let mode = ((try? FileManager.default.attributesOfItem(atPath: target.path))?[.posixPermissions] as? NSNumber)?.int16Value ?? 0o644
        var data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        guard modificationDate() == expectedModification else { throw InstallError.changedWhileWriting }
        try writeFile(data, to: target, mode: mode)
    }

    private static func writePrivate(_ data: Data, to url: URL) throws {
        try writeFile(data, to: url, mode: 0o600)
    }

    /// Writes to a temporary file created with `mode` from the start, then renames
    /// it over `url`, so the contents are never visible with wider permissions.
    static func writeFile(_ data: Data, to url: URL, mode: Int16) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).pace-\(UUID().uuidString)")
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(mode))
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            fchmodIfNeeded(tmp.path, mode)
            guard rename(tmp.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            unlink(tmp.path)
            throw error
        }
    }

    /// `open` applies the umask; set the exact mode afterwards on the private temp file.
    private static func fchmodIfNeeded(_ path: String, _ mode: Int16) {
        chmod(path, mode_t(mode))
    }
}

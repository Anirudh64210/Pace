import Foundation

/// Reads the Claude Code OAuth credentials from the login Keychain.
///
/// Claude Code stores and updates this item through Apple's `/usr/bin/security`
/// tool, so the item's access list trusts that tool. Reading through the same
/// tool never shows a password prompt. Reading it directly through the Security
/// framework would make macOS ask on every rebuild of Pace, because each build
/// has a new code signature and Claude Code resets the access list whenever it
/// refreshes the token.
///
/// The token is returned to the caller and never persisted or logged.
enum ClaudeKeychain {
    static let service = "Claude Code-credentials"
    /// Overridable for tests only.
    nonisolated(unsafe) static var tool = URL(fileURLWithPath: "/usr/bin/security")

    /// Printing, dumping or reflecting this never shows the token.
    struct Credentials: Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        var accessToken: String
        var expiresAt: Date?
        var subscriptionType: String?

        var description: String { "Credentials(token: <redacted>, plan: \(subscriptionType ?? "unknown"))" }
        var debugDescription: String { description }
        var customMirror: Mirror { Mirror(self, children: ["token": "<redacted>", "plan": subscriptionType as Any]) }

        func isExpired(at now: Date, leeway: TimeInterval = 60) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt.addingTimeInterval(-leeway) <= now
        }
    }

    /// Runs off the main thread. Gives up, and kills the tool, after `timeout` seconds.
    static func read(timeout: TimeInterval = 15) async throws -> Credentials {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(with: Result { try readBlocking(timeout: timeout) })
            }
        }
    }

    static func readBlocking(timeout: TimeInterval) throws -> Credentials {
        let process = Process()
        process.executableURL = tool
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // Drain both pipes as data arrives, so the timeout below is real: a
        // blocking read would wait for as long as a Keychain dialog stays open.
        let buffer = LockedData()
        out.fileHandleForReading.readabilityHandler = { buffer.append($0.availableData) }
        err.fileHandleForReading.readabilityHandler = { _ = $0.availableData }
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        defer {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            try? out.fileHandleForReading.close()
            try? err.fileHandleForReading.close()
        }

        do { try process.run() } catch {
            throw ProviderError.keychainUnavailable("the security tool could not start")
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            throw ProviderError.keychainUnavailable("macOS did not answer. If it asked for your password, choose Always Allow, then retry.")
        }
        out.fileHandleForReading.readabilityHandler = nil
        buffer.append(out.fileHandleForReading.readDataToEndOfFile())

        switch process.terminationStatus {
        case 0: return try parse(decodeOutput(buffer.value))
        case 44: throw ProviderError.notSignedIn          // errSecItemNotFound
        case 128, 51: throw ProviderError.keychainUnavailable("access was declined")
        default: throw ProviderError.keychainUnavailable("the Keychain is locked or unavailable (code \(process.terminationStatus))")
        }
    }

    /// `security -w` prints the secret followed by a newline. Secrets that are not
    /// plain text come back as hex.
    static func decodeOutput(_ data: Data) -> Data {
        var text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.hasPrefix("{"), text.count % 2 == 0, text.allSatisfy(\.isHexDigit) {
            var bytes = Data(capacity: text.count / 2)
            var i = text.startIndex
            while i < text.endIndex {
                let j = text.index(i, offsetBy: 2)
                if let b = UInt8(text[i..<j], radix: 16) { bytes.append(b) }
                i = j
            }
            text = String(decoding: bytes, as: UTF8.self)
        }
        return Data(text.utf8)
    }

    static func parse(_ data: Data) throws -> Credentials {
        guard let root = try? JSONHelpers.object(data),
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw ProviderError.notSignedIn
        }
        return Credentials(
            accessToken: token,
            expiresAt: JSONHelpers.date(oauth["expiresAt"]),
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }
}

/// A byte buffer shared with pipe callbacks.
final class LockedData: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ more: Data) { lock.lock(); data.append(more); lock.unlock() }
    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}

/// Picks the freshest Claude Code sign-in on this Mac. Read only.
///
/// Claude Code normally keeps its sign-in in the Keychain. The Claude desktop
/// app runs its own copy of Claude Code, which renews the sign-in but can only
/// save the new one to `~/.claude/.credentials.json`, leaving the Keychain copy
/// stale (anthropics/claude-code#94464). Reading both and taking the one that
/// expires last keeps Pace working on days spent in the desktop app.
///
/// Pace never renews, rewrites or deletes either copy: renewal credentials are
/// single use, so a second writer could sign you out of Claude Code.
enum ClaudeCredentials {
    /// Candidate files, in `$CLAUDE_CONFIG_DIR` when set and in `~/.claude`.
    static var files: [URL] {
        var urls: [URL] = []
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            urls.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath).appendingPathComponent(".credentials.json"))
        }
        urls.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json"))
        return urls
    }

    /// Reads a credentials file if it is a regular file owned by this user and
    /// not readable by anyone else. Anything else is ignored.
    static func readFile(_ url: URL) -> ClaudeKeychain.Credentials? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue, mode & 0o077 == 0,
              let size = attrs[.size] as? NSNumber, size.intValue < 1_000_000,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? ClaudeKeychain.parse(data)
    }

    /// The candidate that is still valid and expires last. If none is valid,
    /// the one that expired last, so the caller can report "expired".
    static func pick(_ candidates: [ClaudeKeychain.Credentials], now: Date = Date()) -> ClaudeKeychain.Credentials? {
        let plan = candidates.compactMap(\.subscriptionType).first
        let sorted = candidates.sorted { ($0.expiresAt ?? .distantFuture) > ($1.expiresAt ?? .distantFuture) }
        guard var best = sorted.first(where: { !$0.isExpired(at: now) }) ?? sorted.first else { return nil }
        if best.subscriptionType == nil { best.subscriptionType = plan }   // the file copy omits the plan
        return best
    }

    static func read(now: Date = Date()) async throws -> ClaudeKeychain.Credentials {
        var candidates: [ClaudeKeychain.Credentials] = []
        var keychainError: Error?
        do { candidates.append(try await ClaudeKeychain.read()) } catch { keychainError = error }
        candidates += files.compactMap(readFile)
        guard let best = pick(candidates, now: now) else { throw keychainError ?? ProviderError.notSignedIn }
        return best
    }
}

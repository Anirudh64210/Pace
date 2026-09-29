import Foundation

/// Sums input and output tokens from Claude Code's transcript files in
/// `~/.claude/projects/**/*.jsonl`. Results are approximate ("about"), and the
/// scan is incremental: each file is only re-read from the byte it grew past.
/// All mutable state is touched only on `queue`.
final class TokenLogReader: @unchecked Sendable {
    struct FileState: Codable {
        var offset: Int
        var tokens: Int
    }

    let projectsDirectory: URL
    let cacheURL: URL
    private var cache: [String: FileState] = [:]
    private let queue = DispatchQueue(label: "pace.tokenlog", qos: .utility)

    init(projectsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"),
         cacheURL: URL = StatusLineProvider.defaultDirectory.appendingPathComponent("token-cache.json")) {
        self.projectsDirectory = projectsDirectory
        self.cacheURL = cacheURL
        if let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode([String: FileState].self, from: data) {
            cache = saved
        }
    }

    /// Total tokens across all transcripts, or nil when there are none.
    func total() async -> Int? {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: self.scan()) }
        }
    }

    static let chunkSize = 4 << 20   // 4 MB

    private func scan() -> Int? {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let e = fm.enumerator(at: projectsDirectory, includingPropertiesForKeys: keys) else { return nil }
        var seen = Set<String>()
        var any = false
        for case let url as URL in e where url.pathExtension == "jsonl" {
            // Real files only: a symlink could point at /dev/zero or outside ~/.claude.
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let key = url.path
            seen.insert(key)
            any = true
            let size = values.fileSize ?? 0
            var state = cache[key] ?? FileState(offset: 0, tokens: 0)
            if size < state.offset { state = FileState(offset: 0, tokens: 0) } // truncated or rewritten
            if size > state.offset {
                let (tokens, consumed) = Self.count(url, from: state.offset, to: size)
                state.tokens += tokens
                state.offset += consumed
            }
            cache[key] = state
        }
        cache = cache.filter { seen.contains($0.key) }
        persist()
        guard any else { return nil }
        return cache.values.reduce(0) { $0 + $1.tokens }
    }

    /// Counts tokens in complete lines between `start` and `end`, reading in
    /// bounded chunks. Returns the bytes consumed, which stops at the last full
    /// line so a line still being written is counted once, next time.
    static func count(_ url: URL, from start: Int, to end: Int) -> (tokens: Int, consumed: Int) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (0, 0) }
        defer { try? handle.close() }
        var offset = start
        var tokens = 0
        var carry = Data()
        while offset < end {
            try? handle.seek(toOffset: UInt64(offset))
            guard let chunk = try? handle.read(upToCount: min(chunkSize, end - offset)), !chunk.isEmpty else { break }
            offset += chunk.count
            var data = carry
            data.append(chunk)
            guard let lastNewline = data.lastIndex(of: 0x0A) else {
                carry = data
                if carry.count > 64 << 20 { carry.removeAll() }   // a single absurd line: skip it
                continue
            }
            tokens += Self.tokens(in: data[data.startIndex...lastNewline])
            carry = Data(data[(lastNewline + 1)...])
        }
        return (tokens, offset - start - carry.count)
    }

    /// Holds only file paths, byte offsets and counts. Kept private to the user anyway.
    private func persist() {
        let fm = FileManager.default
        let dir = cacheURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? StatusLineInstaller.writeFile(data, to: cacheURL, mode: 0o600)
    }

    /// Byte scan for `"input_tokens":N` and `"output_tokens":N`. Avoids decoding
    /// whole transcript lines, which can be hundreds of kilobytes each.
    static func tokens(in data: Data) -> Int {
        var total = 0
        total += sum(of: Array("\"input_tokens\":".utf8), in: data)
        total += sum(of: Array("\"output_tokens\":".utf8), in: data)
        return total
    }

    private static func sum(of needle: [UInt8], in data: Data) -> Int {
        var total = 0
        let n = needle.count
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let bytes = buf.bindMemory(to: UInt8.self)
            let count = bytes.count
            guard count >= n else { return }
            var i = 0
            while i <= count - n {
                if bytes[i] == needle[0] {
                    var match = true
                    for j in 1..<n where bytes[i + j] != needle[j] { match = false; break }
                    if match {
                        var k = i + n
                        while k < count, bytes[k] == 0x20 { k += 1 }
                        var value = 0
                        var digits = 0
                        while k < count, bytes[k] >= 0x30, bytes[k] <= 0x39 {
                            value = value * 10 + Int(bytes[k] - 0x30)
                            k += 1; digits += 1
                            if digits > 12 { break }
                        }
                        total += value
                        i = k
                        continue
                    }
                }
                i += 1
            }
        }
        return total
    }
}

import XCTest

/// Runs the real status line script against hostile and messy input.
final class ScriptTests: XCTestCase {
    var home: URL!
    let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("scripts/pace-statusline.sh")

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("pace-script-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    var statusFile: URL { home.appendingPathComponent("Library/Application Support/Pace/status.json") }

    @discardableResult
    func run(_ input: Data) throws -> (out: String, code: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        p.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        inPipe.fileHandleForWriting.write(input)
        try inPipe.fileHandleForWriting.close()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: out, as: UTF8.self), p.terminationStatus)
    }

    @discardableResult
    func run(_ text: String) throws -> (out: String, code: Int32) { try run(Data(text.utf8)) }

    func saved() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: statusFile)) as! [String: Any]
    }

    func testNormalInput() throws {
        let now = Int(Date().timeIntervalSince1970)
        let r = try run(#"{"rate_limits":{"five_hour":{"used_percentage":62,"resets_at":\#(now + 8048)},"seven_day":{"used_percentage":41,"resets_at":\#(now + 405720)}}}"#)
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.hasPrefix("● on track  38% session · 2h 14m  59% week"), r.out)
    }

    func testSavesNumbersOnlyAndPrivately() throws {
        let now = Int(Date().timeIntervalSince1970)
        try run(#"{"session_id":"secret-session","transcript_path":"/Users/x/secret","cwd":"/Users/x/project","model":{"id":"m"},"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":\#(now + 100)}}}"#)
        let text = try String(contentsOf: statusFile, encoding: .utf8)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("/Users/x"))
        let perms = try FileManager.default.attributesOfItem(atPath: statusFile.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testHostileInputNeverCrashesOrCorruptsTheFile() throws {
        let now = Int(Date().timeIntervalSince1970)
        try run(#"{"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":\#(now + 3600)}}}"#)
        let inputs: [Data] = [
            Data(),
            Data("not json".utf8),
            Data("[1,2,3]".utf8),
            Data(#"{"rate_limits":"oops"}"#.utf8),
            Data(#"{"rate_limits":{"five_hour":"x","seven_day":[1]}}"#.utf8),
            Data(#"{"rate_limits":{"five_hour":{"used_percentage":"NaN","resets_at":"soon"}}}"#.utf8),
            Data(#"{"rate_limits":{"five_hour":{"used_percentage":1e308,"resets_at":-5}}}"#.utf8),
            Data(#"{"rate_limits":{"five_hour":{"used_percentage":"$(touch /tmp/pace-pwned)","resets_at":"`id`"}}}"#.utf8),
            Data((0..<256).map { UInt8($0) }),
            Data(String(repeating: "{\"a\":", count: 5000).utf8),
            Data(("{\"x\":\"" + String(repeating: "A", count: 2_000_000) + "\"}").utf8),
        ]
        for input in inputs {
            let r = try run(input)
            XCTAssertEqual(r.code, 0, "exit code for input of \(input.count) bytes")
            let s = try saved()
            XCTAssertNotNil(s["rate_limits"] as? [String: Any], "status file stays valid JSON")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/pace-pwned"), "input is never executed")
        let five = (try saved()["rate_limits"] as? [String: Any])?["five_hour"] as? [String: Any]
        XCTAssertNotNil(five, "garbage input does not erase good data")
    }

    func testStaleSessionCannotOverwriteNewerWindow() throws {
        let now = Int(Date().timeIntervalSince1970)
        try run(#"{"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":\#(now + 18000)}}}"#)
        try run(#"{"rate_limits":{"five_hour":{"used_percentage":90,"resets_at":\#(now + 600)}}}"#)
        let five = (try saved()["rate_limits"] as? [String: Any])?["five_hour"] as? [String: Any]
        XCTAssertEqual(five?["used_percentage"] as? Double, 5)
    }

    func testChainedStatusLineStillPrints() throws {
        try "echo my-own-line".write(to: home.appendingPathComponent(".claude/pace-statusline-chain"), atomically: true, encoding: .utf8)
        let r = try run("{}")
        XCTAssertEqual(r.out.trimmingCharacters(in: .whitespacesAndNewlines), "my-own-line")
    }
}

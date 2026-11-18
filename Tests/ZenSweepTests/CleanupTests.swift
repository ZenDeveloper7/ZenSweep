import Foundation

func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs, "Expected \(rhs), got \(lhs)") }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression(); preconditionFailure("Expected rejection") } catch {}
}

final class CleanupTests {
    var root: URL!
    func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("ZenSweepTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func file(_ path: String, size: Int = 32) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: size).write(to: url); return url
    }
    func entry(_ url: URL, removable: Bool = true) throws -> FileEntry {
        var notes: [String] = []; return try FileScanner().entry(url, category: "Test", removable: removable, issues: &notes)
    }
    func testCacheAndLogRootsAreAllowedButLibraryDataIsNot() throws {
        let cache = try file("Library/Caches/Test.cache")
        let log = try file("Library/Logs/Test.log")
        let data = try file("Library/Application Support/Important.db")
        let policy = CleanupPolicy(home: root, appRoots: [])
        try policy.validate(entry(cache), chosenRoot: nil)
        try policy.validate(entry(log), chosenRoot: nil)
        XCTAssertThrowsError(try policy.validate(entry(data), chosenRoot: root))
        XCTAssertThrowsError(try policy.validate(entry(root.appendingPathComponent("Library/Caches")), chosenRoot: nil))
    }
    func testChangedFileIsRejected() throws {
        let url = try file("Library/Caches/test")
        let old = try entry(url)
        try Data(repeating: 2, count: 100).write(to: url)
        XCTAssertThrowsError(try CleanupPolicy(home: root, appRoots: []).validate(old, chosenRoot: nil))
    }
    func testSymlinkAndSymlinkAncestorAreRejected() throws {
        let target = try file("Documents/real")
        let link = root.appendingPathComponent("Library/Caches/link")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try entry(link))
        let folderLink = root.appendingPathComponent("Shortcut")
        try FileManager.default.createSymbolicLink(at: folderLink, withDestinationURL: target.deletingLastPathComponent())
        XCTAssertThrowsError(try CleanupPolicy(home: root, appRoots: []).validate(entry(folderLink.appendingPathComponent("real")), chosenRoot: folderLink))
    }
    func testLargeFilesRequireExplicitRootAndExcludeDirectoriesAndHiddenData() throws {
        let doc = try file("Documents/movie.mov")
        let hidden = try file("Documents/.private/token")
        let policy = CleanupPolicy(home: root, appRoots: [])
        XCTAssertThrowsError(try policy.validate(entry(doc), chosenRoot: nil))
        try policy.validate(entry(doc), chosenRoot: root.appendingPathComponent("Documents"))
        XCTAssertThrowsError(try policy.validate(entry(hidden), chosenRoot: root.appendingPathComponent("Documents")))
        XCTAssertThrowsError(try policy.validate(entry(doc.deletingLastPathComponent()), chosenRoot: root))
        XCTAssertThrowsError(try policy.validate(entry(doc, removable: false), chosenRoot: root))
    }
    func testScanCountsNestedFilesAndDoesNotFollowLinks() throws {
        _ = try file("Library/Caches/Test/a", size: 30)
        _ = try file("Library/Caches/Test/b", size: 70)
        let outside = try file("Elsewhere/secret", size: 500)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Library/Caches/Test/link"), withDestinationURL: outside)
        let result = try FileScanner().cleanup(home: root)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.bytes, 100)
        XCTAssertFalse(result.issues.isEmpty) // Missing Logs is reported, never counted as scanned.
    }
    func testApplicationsMustBeDirectAppBundles() throws {
        let app = try file("Applications/Test.app/Contents/test")
        let policy = CleanupPolicy(home: root, appRoots: [root.appendingPathComponent("Applications")])
        try policy.validate(entry(app.deletingLastPathComponent().deletingLastPathComponent()), chosenRoot: nil)
        XCTAssertThrowsError(try policy.validate(entry(app), chosenRoot: nil))
    }
}

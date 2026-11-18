import Foundation
import AppKit

struct TestFailure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(description: message) }
}
@MainActor final class MemoryHistory: HistoryStore {
    var records: [ActivityRecord] = []
    func load() -> [ActivityRecord] { records }
    func save(_ records: [ActivityRecord]) throws { self.records = records }
}
extension CleanupTests {
    var environment: ScanEnvironment {
        ScanEnvironment(home: root, appRoots: [root.appendingPathComponent("Applications")], backgroundRoots: [root.appendingPathComponent("Library/LaunchAgents"), root.appendingPathComponent("Library/LaunchDaemons")])
    }
    func sparse(_ path: String, bytes: UInt64) throws -> URL {
        let url = try file(path, size: 0)
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.truncate(atOffset: bytes); return url
    }
    func testCleanupCategories() throws {
        _ = try file("Library/Caches/one", size: 30); _ = try file("Library/Logs/two", size: 50); _ = try file("Library/Logs/empty", size: 0)
        let r = try ScanService(environment: environment).scan(.cleanup, root: root)
        try expect(r.entries.map(\.bytes) == [50, 30], "Cleanup size sorting")
        try expect(Set(r.entries.map(\.category)) == ["User caches", "User logs"], "Both categories")
        try expect(r.entries.allSatisfy(\.removable), "Reviewable cleanup items")
    }
    func testApplicationInventory() throws {
        _ = try file("Applications/Small.app/Contents/a", size: 10)
        _ = try file("Applications/Large.app/Contents/a", size: 40)
        _ = try file("Applications/readme", size: 500)
        _ = try file("Applications/NotABundle.app", size: 500)
        let r = try ScanService(environment: environment).scan(.applications, root: root)
        try expect(r.entries.map(\.name) == ["Large.app", "Small.app"], "Only application bundle directories, size sorted")
    }
    func testLargeFileDiscovery() throws {
        _ = try sparse("Documents/big.bin", bytes: 100_000_000)
        _ = try sparse("Documents/small.bin", bytes: 99_999_999)
        _ = try sparse("Documents/.hidden.bin", bytes: 200_000_000)
        let real = try sparse("Documents/nested/movie.bin", bytes: 110_000_000)
        _ = try sparse("Documents/Test.app/Contents/archive", bytes: 300_000_000)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Documents/shortcut"), withDestinationURL: real)
        let r = try ScanService(environment: environment).scan(.clutter, root: root.appendingPathComponent("Documents"))
        try expect(r.entries.map(\.name) == ["movie.bin", "big.bin"], "Threshold, nested files, hidden data, packages, and links: \(r.entries.map(\.name)), visited \(r.visited), notes \(r.issues)")
        try expect(r.entries.allSatisfy(\.removable), "Normal chosen files removable")
        _ = try sparse("Library/Private/big.bin", bytes: 100_000_000)
        let protected = try ScanService(environment: environment).scan(.clutter, root: root.appendingPathComponent("Library/Private"))
        try expect(protected.entries.count == 1 && !protected.entries[0].removable, "Library large files inspection-only")
    }
    func testStorageMap() throws {
        _ = try file("Documents/folder/a", size: 20); _ = try file("Documents/folder/b", size: 30); _ = try file("Documents/other", size: 10)
        let service = ScanService(environment: environment)
        let r = try service.scan(.storage, root: root.appendingPathComponent("Documents"))
        try expect(r.entries.map(\.bytes) == [50, 10], "Folder aggregation")
        try expect(r.entries.allSatisfy { !$0.removable }, "Storage read-only")
        let child = try service.scan(.storage, root: r.entries[0].url)
        try expect(child.entries.map(\.bytes) == [30, 20], "Folder drilldown")
    }
    func testBackgroundInventory() throws {
        _ = try file("Library/LaunchAgents/test.plist"); _ = try file("Library/LaunchDaemons/test.plist")
        let r = try ScanService(environment: environment).scan(.background, root: root)
        try expect(Set(r.entries.map(\.category)) == ["Launch agents", "Launch daemons"], "Background categories")
        try expect(r.entries.allSatisfy { !$0.removable }, "Background items read-only")
    }
    func testMissingAndEmptyFolders() throws {
        let service = ScanService(environment: environment)
        let r = try service.scan(.cleanup, root: root)
        try expect(r.entries.isEmpty && r.issues.count == 2, "Missing cleanup roots reported")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        let empty = try service.scan(.storage, root: root.appendingPathComponent("Documents"))
        try expect(empty.entries.isEmpty && empty.issues.isEmpty, "Empty folder succeeds")
    }
    func testUnreadableFolder() throws {
        let url = try file("Library/Caches/Locked/item")
        let folder = url.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        let r = try FileScanner().cleanup(home: root)
        try expect(!r.issues.isEmpty, "Unreadable content noted")
    }
    @MainActor func wait(_ model: AppModel) async throws {
        for _ in 0..<500 { if !model.isScanning { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw TestFailure(description: "Scan did not complete")
    }
    @MainActor func testModelScanAndFiltering() async throws {
        _ = try file("Library/Caches/Alpha", size: 20); _ = try file("Library/Logs/Beta", size: 40)
        let m = AppModel(environment: environment, history: MemoryHistory())
        m.scan(); try await wait(m)
        try expect(m.module == .cleanup && m.entries.count == 2 && m.scannedAt[.cleanup] != nil, "Overview scan routes and timestamps")
        try expect(m.disk.total > 0 && m.disk.free > 0 && m.disk.free <= m.disk.total, "Actual disk metrics")
        try expect(m.selected.isEmpty, "Nothing selected automatically")
        m.search = "aLpHa"; try expect(m.filtered.count == 1, "Case insensitive name search")
        m.search = "Library/Logs"; try expect(m.filtered.map(\.name) == ["Beta"], "Path search")
        m.search = ""; m.category = "User caches"; try expect(m.filtered.map(\.name) == ["Alpha"], "Category filter")
        m.selected = Set(m.entries.map(\.id)); try expect(m.selectedBytes == 60, "Selection sums")
        m.selected = []; try expect(m.selectedBytes == 0, "Clear selection")
        m.search = "no match"; try expect(m.filtered.isEmpty, "No matches")
        m.navigate(.applications)
        try expect(m.search.isEmpty && m.category == "All items" && m.selected.isEmpty, "Navigation resets review state")
    }
    @MainActor func testCancellation() async throws {
        for i in 0..<100 { _ = try file("Library/Caches/Folder/f\(i)") }
        let m = AppModel(environment: environment, history: MemoryHistory())
        m.scan(); m.navigate(.activity)
        try await Task.sleep(nanoseconds: 100_000_000)
        try expect(!m.isScanning && m.module == .activity && m.results[.cleanup] == nil, "Cancelled scan cannot overwrite current screen")
        m.navigate(.cleanup); m.scan(); try await wait(m)
        try expect(m.entries.count == 1, "Rescan after cancellation")
    }
    @MainActor func testConfirmationGate() async throws {
        _ = try file("Library/Logs/disposable.log")
        let m = AppModel(environment: environment, history: MemoryHistory())
        m.navigate(.cleanup); m.scan(); try await wait(m)
        m.beginReview(); try expect(!m.confirmTrash, "Cannot review empty selection")
        m.selected = Set(m.entries.map(\.id)); m.beginReview(); m.confirmCleanup()
        try expect(m.confirmTrash && m.records.isEmpty && FileManager.default.fileExists(atPath: m.entries[0].url.path), "Unchecked review cannot clean")
        m.reviewedSelection = true; m.cancelReview(); m.confirmCleanup()
        try expect(!m.confirmTrash && !m.reviewedSelection && m.records.isEmpty, "Cancellation disarms cleanup")
    }
    @MainActor func testHistoryPersistence() throws {
        let suite = "in.builtbyzen.ZenSweep.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DefaultsHistoryStore(defaults: defaults)
        try expect(store.load().isEmpty, "Empty history")
        let record = ActivityRecord(date: Date(), originalPath: "/fixture", trashPath: "/fixture-trash", bytes: 20)
        try store.save([record])
        let second = DefaultsHistoryStore(defaults: UserDefaults(suiteName: suite)!)
        try expect(second.load().first?.id == record.id && second.load().first?.bytes == 20, "Persisted history reload")
        defaults.set(Data("invalid".utf8), forKey: "ZenSweep.history")
        try expect(store.load().isEmpty, "Malformed history handled")
    }
    @MainActor func testRunningAppProtection() throws {
        guard let identifier = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).first else { throw TestFailure(description: "No running application available") }
        let app = root.appendingPathComponent("Applications/Running.app")
        _ = try file("Applications/Running.app/Contents/MacOS/fake")
        let info: [String: String] = ["CFBundleIdentifier": identifier, "CFBundleName": "Running", "CFBundleExecutable": "fake", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let item = try entry(app)
        do { _ = try CleanupService(home: root, appRoots: environment.appRoots).moveToTrash(item, chosenRoot: nil); throw TestFailure(description: "Running app was not blocked") }
        catch ScanError.running { }
        try expect(FileManager.default.fileExists(atPath: app.path), "Running bundle retained")
    }
    @MainActor func testMotionPolicy() throws {
        try expect(MotionPreferences.allowsAmbient(reduceMotion: false, active: true), "Active animation")
        try expect(!MotionPreferences.allowsAmbient(reduceMotion: true, active: true), "Reduce Motion disables ambient animation")
        try expect(!MotionPreferences.allowsAmbient(reduceMotion: false, active: false), "Inactive app pauses animation")
    }
    @MainActor func testTrashIntegration() async throws {
        _ = try file("Library/Caches/disposable-cache/data", size: 25)
        _ = try file("Library/Logs/disposable.log", size: 32)
        _ = try file("Applications/Disposable.app/Contents/MacOS/test", size: 12)
        _ = try sparse("Documents/disposable.bin", bytes: 100_000_000)
        let history = MemoryHistory()
        let model = AppModel(environment: environment, history: history)
        defer {
            // Best effort on failure; the normal path below asserts every recovery.
            for record in history.records where FileManager.default.fileExists(atPath: record.trashPath) {
                let original = URL(fileURLWithPath: record.originalPath)
                if original.deletingLastPathComponent().resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") {
                    try? FileManager.default.moveItem(at: URL(fileURLWithPath: record.trashPath), to: original)
                }
            }
        }
        model.navigate(.storage); model.folder = root.appendingPathComponent("Library/Caches")
        model.scan(); try await wait(model)
        try expect(model.entries.count == 1, "Storage preflight fixture")
        for module in [Module.cleanup, .applications, .clutter] {
            model.navigate(module)
            if module == .clutter { model.folder = root.appendingPathComponent("Documents") }
            model.scan(); try await wait(model)
            try expect(!model.entries.isEmpty, "Integration fixture discovered for \(module.rawValue)")
            model.selected = Set(model.entries.map(\.id))
            model.beginReview(); model.reviewedSelection = true; model.confirmCleanup()
            try expect(model.entries.isEmpty && model.selected.isEmpty, "Cleanup invalidates selection and results")
            try expect(model.message?.contains("Moved") == true, "Cleanup outcome feedback")
            if module == .cleanup { try expect(model.results[.storage]?.entries.isEmpty == true, "Cleanup invalidates cached storage results") }
        }
        try expect(history.records.count == 4, "Four fixture items recorded")
        let reloaded = AppModel(environment: environment, history: history)
        try expect(reloaded.records.count == 4, "Activity reload after cleanup")
        for record in history.records {
            try expect(!FileManager.default.fileExists(atPath: record.originalPath), "Original fixture moved")
            try expect(FileManager.default.fileExists(atPath: record.trashPath), "Trash record points to recoverable item")
        }
        for record in history.records {
            let original = URL(fileURLWithPath: record.originalPath)
            try expect(original.deletingLastPathComponent().resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"), "Recovery is within the fixture root: original=\(original.path) resolved=\(original.resolvingSymlinksInPath().path) root=\(root.resolvingSymlinksInPath().path)")
            try FileManager.default.moveItem(at: URL(fileURLWithPath: record.trashPath), to: original)
            var notes: [String] = []
            let restoredSize = try FileScanner().size(original, issues: &notes)
            try expect(restoredSize == record.bytes && notes.isEmpty, "Restored fixture matches its recorded byte count")
            try expect(!FileManager.default.fileExists(atPath: record.trashPath), "Recovery removes the Trash entry")
            print("RECOVERED: \(original.lastPathComponent) · \(restoredSize) bytes")
        }
    }
}
@main struct TestRunner {
    @MainActor static func main() async {
        do { try await run() }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        let t = CleanupTests()
        let cases: [(String, () async throws -> Void)] = [
            ("Cleanup boundaries", { try t.testCacheAndLogRootsAreAllowedButLibraryDataIsNot() }),
            ("Changed-file rejection", { try t.testChangedFileIsRejected() }),
            ("Symbolic links", { try t.testSymlinkAndSymlinkAncestorAreRejected() }),
            ("Chosen-folder boundaries", { try t.testLargeFilesRequireExplicitRootAndExcludeDirectoriesAndHiddenData() }),
            ("Nested file sizes", { try t.testScanCountsNestedFilesAndDoesNotFollowLinks() }),
            ("App bundle boundaries", { try t.testApplicationsMustBeDirectAppBundles() }),
            ("Cleanup categories and sorting", { try t.testCleanupCategories() }),
            ("Application inventory", { try t.testApplicationInventory() }),
            ("Large-file threshold and exclusions", { try t.testLargeFileDiscovery() }),
            ("Storage map and drilldown", { try t.testStorageMap() }),
            ("Background inventory", { try t.testBackgroundInventory() }),
            ("Missing and empty folders", { try t.testMissingAndEmptyFolders() }),
            ("Access-error reporting", { try t.testUnreadableFolder() }),
            ("Scan state, search, category, selection, navigation", { try await t.testModelScanAndFiltering() }),
            ("Cancellation and rescan", { try await t.testCancellation() }),
            ("Explicit confirmation and cancellation", { try await t.testConfirmationGate() }),
            ("History persistence and malformed data", { try t.testHistoryPersistence() }),
            ("Running-app protection", { try t.testRunningAppProtection() }),
            ("Reduce Motion and inactive-app policy", { try t.testMotionPolicy() })
        ]
        var passed = 0
        for (name, test) in cases {
            try t.setUpWithError()
            do { try await test(); try t.tearDownWithError(); print("PASS: \(name)"); passed += 1 }
            catch { try? t.tearDownWithError(); throw TestFailure(description: "\(name): \(error)") }
        }
        if ProcessInfo.processInfo.environment["ZENSWEEP_TRASH_TEST"] == "1" {
            try t.setUpWithError()
            do { try await t.testTrashIntegration(); try t.tearDownWithError(); print("PASS: Real cache, log, app, and large-file Trash/recovery integration"); passed += 1 }
            catch { try? t.tearDownWithError(); throw error }
        }
        print("\(passed) checks passed")
    }
}

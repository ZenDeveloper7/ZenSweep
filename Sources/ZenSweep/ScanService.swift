import Foundation

struct ScanEnvironment: Sendable {
    let home: URL
    let appRoots: [URL]
    let backgroundRoots: [URL]
    static let live: ScanEnvironment = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ScanEnvironment(home: home, appRoots: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")], backgroundRoots: [home.appendingPathComponent("Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchDaemons")])
    }()
}
struct ScanService: Sendable {
    let environment: ScanEnvironment
    func scan(_ module: Module, root: URL) throws -> ScanResult {
        let scanner = FileScanner()
        switch module {
        case .cleanup, .overview: return try scanner.cleanup(home: environment.home)
        case .applications:
            return try combined(environment.appRoots, scanner: scanner, removable: true) { _ in "Applications" }
        case .clutter:
            var result = try scanner.largeFiles(root: root)
            let policy = CleanupPolicy(home: environment.home, appRoots: environment.appRoots)
            result.entries = result.entries.map { item in
                var copy = item
                copy.removable = policy.allowsLocation(item, chosenRoot: root)
                return copy
            }
            return result
        case .storage: return try scanner.children(root, category: "Storage", removable: false)
        case .background:
            return try combined(environment.backgroundRoots, scanner: scanner, removable: false) { $0.lastPathComponent == "LaunchDaemons" ? "Launch daemons" : "Launch agents" }
        case .activity: return ScanResult()
        }
    }
    private func combined(_ roots: [URL], scanner: FileScanner, removable: Bool, category: (URL) -> String) throws -> ScanResult {
        var result = ScanResult()
        for root in roots {
            do {
                let part = try scanner.children(root, category: category(root), removable: removable)
                result.entries += part.entries.filter { !removable || ($0.isDirectory && $0.url.pathExtension == "app" && $0.url.path != Bundle.main.bundlePath) }
                result.issues += part.issues; result.visited += part.visited
            } catch is CancellationError { throw CancellationError() }
            catch { result.issues.append("\(root.path): \(error.localizedDescription)") }
        }
        result.entries.sort { $0.bytes > $1.bytes }; return result
    }
}

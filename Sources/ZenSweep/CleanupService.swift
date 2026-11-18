import Foundation
import AppKit

struct CleanupPolicy {
    let home: URL
    let appRoots: [URL]
    func allowsLocation(_ item: FileEntry, chosenRoot: URL?) -> Bool {
        let url = item.url.standardizedFileURL
        guard item.removable, url == url.resolvingSymlinksInPath(), url.path != Bundle.main.bundlePath else { return false }
        let caches = home.appendingPathComponent("Library/Caches").standardizedFileURL
        let logs = home.appendingPathComponent("Library/Logs").standardizedFileURL
        let isCleanup = [caches, logs].contains { url.deletingLastPathComponent() == $0 }
        let isApp = appRoots.contains { url.deletingLastPathComponent() == $0.standardizedFileURL } && url.pathExtension == "app"
        let isLarge = chosenRoot.map { root in
            let r = root.standardizedFileURL.resolvingSymlinksInPath()
            let library = home.appendingPathComponent("Library").path + "/"
            return !item.isDirectory && url.path.hasPrefix(r.path + "/") && url.path.hasPrefix(home.path + "/") && !url.path.hasPrefix(library) && !url.path.dropFirst(home.path.count + 1).split(separator: "/").contains(where: { $0.hasPrefix(".") })
        } ?? false
        return isCleanup || isApp || isLarge
    }
    func validate(_ item: FileEntry, chosenRoot: URL?) throws {
        guard allowsLocation(item, chosenRoot: chosenRoot) else { throw ScanError.unsafe }
        let url = item.url.standardizedFileURL
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.modificationDate] as? Date == item.modified,
              (attributes[.systemFileNumber] as? NSNumber)?.uint64Value == item.inode else { throw ScanError.changed }
        if !item.isDirectory {
            guard (attributes[.size] as? NSNumber)?.int64Value == item.bytes else { throw ScanError.changed }
        }
    }
}
@MainActor final class CleanupService {
    let policy: CleanupPolicy
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, appRoots: [URL]? = nil) {
        policy = CleanupPolicy(home: home, appRoots: appRoots ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")])
    }
    func moveToTrash(_ item: FileEntry, chosenRoot: URL?) throws -> ActivityRecord {
        try policy.validate(item, chosenRoot: chosenRoot)
        if item.url.pathExtension == "app", let identifier = Bundle(url: item.url)?.bundleIdentifier,
           !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty { throw ScanError.running }
        var target: NSURL?
        try FileManager.default.trashItem(at: item.url, resultingItemURL: &target)
        return ActivityRecord(date: Date(), originalPath: item.url.path, trashPath: target?.path ?? "", bytes: item.bytes)
    }
}

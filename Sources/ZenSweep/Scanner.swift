import Foundation

struct FileScanner {
    let manager = FileManager.default
    func entry(_ url: URL, category: String, removable: Bool, issues: inout [String]) throws -> FileEntry {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true else { throw ScanError.symbolicLink }
        let attrs = try manager.attributesOfItem(atPath: url.path)
        let bytes = try size(url, issues: &issues)
        return FileEntry(url: url, bytes: bytes, category: category, modified: attrs[.modificationDate] as? Date ?? .distantPast, inode: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0, removable: removable, isDirectory: values.isDirectory == true)
    }
    func size(_ url: URL, issues: inout [String]) throws -> Int64 {
        try Task.checkCancellation()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        let v = try url.resourceValues(forKeys: keys)
        if v.isSymbolicLink == true { return 0 }
        if v.isDirectory != true { return Int64(v.fileSize ?? 0) }
        var enumerationIssues: [String] = []
        defer { issues += enumerationIssues }
        guard let iterator = manager.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { child, error in
            if enumerationIssues.count < 50 { enumerationIssues.append("\(child.path): \(error.localizedDescription)") }; return true
        }) else { throw ScanError.unreadable }
        var total: Int64 = 0
        for case let child as URL in iterator {
            try Task.checkCancellation()
            do {
                let value = try child.resourceValues(forKeys: keys)
                if value.isSymbolicLink == true { continue }
                if value.isDirectory != true { total += Int64(value.fileSize ?? 0) }
            } catch { if issues.count < 50 { issues.append("\(child.path): \(error.localizedDescription)") } }
        }
        return total
    }
    func children(_ root: URL, category: String, removable: Bool) throws -> ScanResult {
        var result = ScanResult()
        let children = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])
        for child in children {
            try Task.checkCancellation()
            do { result.entries.append(try entry(child, category: category, removable: removable, issues: &result.issues)) }
            catch is CancellationError { throw CancellationError() }
            catch ScanError.symbolicLink { continue }
            catch { if result.issues.count < 50 { result.issues.append("\(child.path): \(error.localizedDescription)") } }
            result.visited += 1
        }
        result.entries.sort { $0.bytes > $1.bytes }; return result
    }
    func cleanup(home: URL) throws -> ScanResult {
        var result = ScanResult()
        for (path, category) in [("Library/Caches", "User caches"), ("Library/Logs", "User logs")] {
            do {
                let part = try children(home.appendingPathComponent(path), category: category, removable: true)
                result.entries += part.entries.filter { $0.bytes > 0 }; result.issues += part.issues; result.visited += part.visited
            } catch is CancellationError { throw CancellationError() }
            catch { result.issues.append("\(path): \(error.localizedDescription)") }
        }
        result.entries.sort { $0.bytes > $1.bytes }; return result
    }
    func largeFiles(root: URL) throws -> ScanResult {
        var result = ScanResult()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .isPackageKey]
        guard let iterator = manager.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { u,e in
            if result.issues.count < 50 { result.issues.append("\(u.path): \(e.localizedDescription)") }; return true
        }) else { throw ScanError.unreadable }
        for case let url as URL in iterator {
            try Task.checkCancellation(); result.visited += 1
            do {
                let v = try url.resourceValues(forKeys: Set(keys))
                if v.isSymbolicLink == true { continue }
                if v.isDirectory == true && (v.isPackage == true || url.pathExtension == "app") { iterator.skipDescendants(); continue }
                if v.isDirectory != true && (v.fileSize ?? 0) >= 100_000_000 {
                    result.entries.append(try entry(url, category: "Large files", removable: true, issues: &result.issues))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { if result.issues.count < 50 { result.issues.append("\(url.path): \(error.localizedDescription)") } }
        }
        result.entries.sort { $0.bytes > $1.bytes }; return result
    }
}
enum ScanError: LocalizedError {
    case symbolicLink, unreadable, unsafe, changed, running
    var errorDescription: String? {
        switch self {
        case .symbolicLink: "Symbolic links are excluded."
        case .unreadable: "This folder cannot be read. Choose another folder or check its permissions."
        case .unsafe: "This item is outside the allowed cleanup locations or is protected."
        case .changed: "This item changed since scanning. Scan again before removing it."
        case .running: "This app is running. Quit it first."
        }
    }
}

import Foundation

enum Module: String, CaseIterable, Identifiable {
    case overview = "Overview", cleanup = "Cleanup", applications = "Applications", clutter = "Large files", storage = "Storage map", background = "Background items", activity = "Activity"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "sparkles"
        case .cleanup: "externaldrive.badge.minus"
        case .applications: "square.stack.3d.up"
        case .clutter: "folder.badge.questionmark"
        case .storage: "chart.pie"
        case .background: "bolt.circle"
        case .activity: "clock.arrow.circlepath"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: "A little breathing room for your Mac."
        case .cleanup: "Review application caches and logs before moving them to Trash."
        case .applications: "Explore installed applications. Quit an app before removing it."
        case .clutter: "Find files over 100 MB in a folder you choose."
        case .storage: "See the size of each folder, then explore what’s inside."
        case .background: "Inspect launch agents and open macOS settings to manage them."
        case .activity: "Your cleanup history, stored on this Mac."
        }
    }
}
struct FileEntry: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let bytes: Int64
    let category: String
    let modified: Date
    let inode: UInt64
    var removable: Bool
    let isDirectory: Bool
    var name: String { url.lastPathComponent }
}
struct ScanResult: Sendable {
    var entries: [FileEntry] = []
    var issues: [String] = []
    var visited = 0
}
struct ActivityRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let originalPath: String
    let trashPath: String
    let bytes: Int64
}
func formattedBytes(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

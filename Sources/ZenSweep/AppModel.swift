import Foundation
import SwiftUI
import AppKit

@MainActor final class AppModel: ObservableObject {
    @Published var module: Module = .overview
    @Published var results: [Module: ScanResult] = [:]
    @Published var selected: Set<String> = []
    @Published var isScanning = false
    @Published var scanLabel = ""
    @Published var search = ""
    @Published var category = "All items"
    @Published var message: String?
    @Published var showIssues = false
    @Published var confirmTrash = false
    @Published var reviewedSelection = false
    @Published var records: [ActivityRecord] = []
    @Published var folder: URL?
    @Published var scannedAt: [Module: Date] = [:]
    private var worker: Task<ScanResult, Error>?
    private var scanGeneration = UUID()
    private let environment: ScanEnvironment
    private let cleaner: CleanupService
    private let history: any HistoryStore
    private var home: URL { environment.home }
    init(environment: ScanEnvironment = .live, history: (any HistoryStore)? = nil) {
        self.environment = environment
        self.cleaner = CleanupService(home: environment.home, appRoots: environment.appRoots)
        self.history = history ?? DefaultsHistoryStore()
        records = self.history.load()
    }
    var entries: [FileEntry] { results[module]?.entries ?? [] }
    var filtered: [FileEntry] { entries.filter { (category == "All items" || $0.category == category) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.url.path.localizedCaseInsensitiveContains(search)) } }
    var categories: [String] { ["All items"] + Set(entries.map(\.category)).sorted() }
    var selectedEntries: [FileEntry] { entries.filter { selected.contains($0.id) } }
    var selectedBytes: Int64 { selectedEntries.reduce(0) { $0 + $1.bytes } }
    var issues: [String] { results[module]?.issues ?? [] }
    var disk: (total: Int64, free: Int64) {
        let a = (try? FileManager.default.attributesOfFileSystem(forPath: home.path)) ?? [:]
        return ((a[.systemSize] as? NSNumber)?.int64Value ?? 0, (a[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)
    }
    func navigate(_ destination: Module) {
        cancel(); selected = []; search = ""; category = "All items"; module = destination
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to inspect. Nothing is selected for cleanup automatically."
        if panel.runModal() == .OK, let url = panel.url { folder = url; scan() }
    }
    func cancel() { scanGeneration = UUID(); worker?.cancel(); worker = nil; isScanning = false }
    func scan(root override: URL? = nil) {
        cancel(); selected = []; category = "All items"
        let target = module == .overview ? Module.cleanup : module
        if module == .overview { module = .cleanup }
        if target == .activity { return }
        if (target == .clutter || target == .storage), folder == nil, override == nil { chooseFolder(); return }
        let root = override ?? folder ?? home
        if target == .storage { folder = root }
        let service = ScanService(environment: environment)
        let token = UUID(); scanGeneration = token; isScanning = true; scanLabel = "Scanning \(target.rawValue.lowercased())…"
        let task = Task.detached(priority: .userInitiated) { try service.scan(target, root: root) }
        worker = task
        Task {
            do {
                let result = try await task.value
                guard scanGeneration == token else { return }
                results[target] = result; scannedAt[target] = Date(); isScanning = false; worker = nil
            } catch {
                guard scanGeneration == token else { return }
                isScanning = false; worker = nil
                if !(error is CancellationError) { message = error.localizedDescription }
            }
        }
    }
    func beginReview() {
        guard !isScanning, !selectedEntries.isEmpty else { return }
        reviewedSelection = false; confirmTrash = true
    }
    func cancelReview() { confirmTrash = false; reviewedSelection = false }
    func confirmCleanup() {
        guard confirmTrash, reviewedSelection, !isScanning else { return }
        confirmTrash = false; reviewedSelection = false
        trashSelected()
    }
    private func trashSelected() {
        var failures: [String] = []; var moved = 0
        for item in selectedEntries {
            do {
                let record = try cleaner.moveToTrash(item, chosenRoot: module == .clutter ? folder : nil)
                records.insert(record, at: 0); moved += 1
                // Invalidate every view containing an item that was moved.
                for key in Array(results.keys) { results[key]?.entries.removeAll { $0.id == item.id || $0.url.path.hasPrefix(item.url.path + "/") } }
            } catch { failures.append("\(item.name): \(error.localizedDescription)") }
        }
        selected = []
        do { try history.save(records) } catch { failures.append("History could not be saved: \(error.localizedDescription)") }
        message = "Moved \(moved) item\(moved == 1 ? "" : "s") to Trash. Storage is reclaimed when you empty Trash in Finder." + (failures.isEmpty ? "" : "\n\nSkipped:\n" + failures.joined(separator: "\n"))
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func openLoginSettings() { if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) } }
}

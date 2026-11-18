import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var model = AppModel()
    @ObservedObject private var motion = MotionPreferences.shared
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                Group {
                    if model.module == .overview { overview }
                    else if model.module == .activity { activity }
                    else { workspace }
                }.id(model.module).arrive()

            }.background(Theme.pale)
        }
        .frame(minWidth: 1040, minHeight: 700)
        .preferredColorScheme(.light)
        .sheet(isPresented: $model.confirmTrash) { cleanupReview }
        .alert("ZenSweep", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
        .sheet(isPresented: $model.showIssues) { issuesSheet }
    }
    private var cleanupReview: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Review before cleanup", systemImage: "trash").font(.system(size: 25, weight: .semibold, design: .rounded))
            Text("\(model.selectedEntries.count) selected · \(formattedBytes(model.selectedBytes))").font(.headline)
            Text("Quit affected apps first. Caches will be rebuilt; removing logs discards diagnostic history. Items move to Finder’s Trash, where you can put them back.").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.selectedEntries) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.system(size: 13, weight: .semibold))
                            Text(item.url.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(16)
            }.background(Theme.pale, in: RoundedRectangle(cornerRadius: 12))
            Toggle("I reviewed these items and want to move them to Trash", isOn: $model.reviewedSelection).toggleStyle(.checkbox)
            HStack {
                Button("Cancel") { model.cancelReview() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Move reviewed items to Trash") {
                    model.confirmCleanup()
                }.buttonStyle(PrimaryButton()).disabled(!model.reviewedSelection).opacity(model.reviewedSelection ? 1 : 0.4)
            }
        }.padding(28).frame(width: 640, height: 520)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                LogoMark().frame(width: 43, height: 43)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ZenSweep").font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("SPACE TO DO MORE").font(.system(size: 8, weight: .bold)).tracking(1.8).foregroundStyle(.white.opacity(0.5))
                }
            }.padding(.top, 28).padding(.horizontal, 20)
            VStack(spacing: 7) {
                ForEach(Module.allCases) { module in
                    Button { model.navigate(module) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: module.icon).font(.system(size: 17)).frame(width: 24)
                            Text(module.rawValue).font(.system(size: 13, weight: model.module == module ? .semibold : .regular))
                            Spacer()
                            if model.module == module { Circle().fill(.mint).frame(width: 5, height: 5) }
                        }.padding(.horizontal, 14).padding(.vertical, 13)
                            .foregroundStyle(.white.opacity(model.module == module ? 1 : 0.65))
                            .background(.white.opacity(model.module == module ? 0.13 : 0), in: RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 12)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Label("On this Mac", systemImage: "lock.shield").font(.system(size: 12, weight: .semibold))
                Text("Local scans. Review first.\nRecover through Trash.").font(.system(size: 11)).lineSpacing(5).foregroundStyle(.white.opacity(0.5))
                Divider().overlay(.white.opacity(0.1))
                Text("ZenSweep 0.2").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }.padding(22)
        }.frame(width: 244).foregroundStyle(.white)
            .background(LinearGradient(colors: [Color(red: 0.20, green: 0.10, blue: 0.39), Color(red: 0.11, green: 0.08, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(model.module.rawValue).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                Text(model.module.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if let date = model.scannedAt[model.module] { Text(date, style: .time).font(.system(size: 11)).foregroundStyle(.secondary) }
            if model.isScanning { Button("Cancel") { model.cancel() }.buttonStyle(.bordered) }
            else if model.module != .overview && model.module != .activity {
                Button(model.results[model.module] == nil ? "Scan" : "Scan again") { model.scan() }.buttonStyle(PrimaryButton())
            }
        }.padding(28).background(.white)
    }
    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 30) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("YOUR MAC, A LITTLE LIGHTER").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(.mint)
                        Text("Make room for\nwhat’s next.").font(.system(size: 43, weight: .bold, design: .rounded)).tracking(-1)
                        Text("Find forgotten files and accumulated caches.\nYou decide what stays and what goes.").font(.system(size: 13)).lineSpacing(5).foregroundStyle(.white.opacity(0.7))
                        Button { model.scan() } label: { Label("Scan for cleanup", systemImage: "sparkle.magnifyingglass") }.buttonStyle(PrimaryButton()).padding(.top, 5)
                    }
                    Spacer(minLength: 0)
                    StorageRing(total: model.disk.total, free: model.disk.free)
                }.padding(30).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AmbientGlow())
                    .background(LinearGradient(colors: [Color(red: 0.18, green: 0.11, blue: 0.34), Color(red: 0.30, green: 0.19, blue: 0.52)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 22))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                HStack {
                    Text("A place for everything").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(formattedBytes(model.disk.total)) total storage").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    feature(.cleanup, description: "Review caches and diagnostic logs.", color: .teal).arrive(delay: 0.08)
                    feature(.applications, description: "See app sizes and remove unused apps.", color: .blue).arrive(delay: 0.14)
                    feature(.clutter, description: "Bring your biggest files into view.", color: .orange).arrive(delay: 0.20)
                    feature(.storage, description: "Follow the folders taking up space.", color: .purple).arrive(delay: 0.26)
                }
                Label("Scans report accessible files. macOS may restrict some folders.", systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
    private func feature(_ module: Module, description: String, color: Color) -> some View {
        Button { model.navigate(module) } label: {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: module.icon).font(.system(size: 23)).foregroundStyle(color).frame(width: 46, height: 46).background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 7) {
                    Text(module.rawValue).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                    Text(description).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").foregroundStyle(.tertiary)
            }.padding(20).frame(maxWidth: .infinity, minHeight: 90, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(LiftButtonStyle())
    }
    private var workspace: some View {
        VStack(spacing: 0) {
            if model.module == .clutter || model.module == .storage {
                HStack {
                    Image(systemName: "folder").foregroundStyle(Theme.purple)
                    Text(model.folder?.path ?? "Choose a folder to get started").lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if model.module == .storage, let folder = model.folder { Button("Up one level") { model.scan(root: folder.deletingLastPathComponent()) }.disabled(model.isScanning || folder.path == "/") }
                    Button("Choose folder…") { model.chooseFolder() }.disabled(model.isScanning)
                }.font(.system(size: 12)).padding(.horizontal, 28).padding(.vertical, 14)
            }
            if model.isScanning {
                Spacer(); ScanOrbit()
                Text(model.scanLabel).font(.system(size: 18, weight: .medium)).padding(.top, 18)
                Text("Finding the files behind the numbers. Large folders can take a few minutes.").foregroundStyle(.secondary).padding(.top, 5)
                Spacer()
            } else if model.results[model.module] == nil {
                Spacer()
                Image(systemName: model.module.icon).font(.system(size: 68, weight: .ultraLight)).foregroundStyle(Theme.purple).padding(20)
                Text("See what’s taking up space").font(.system(size: 25, weight: .semibold, design: .rounded))
                Text(model.module == .background ? "Inspect launch agent files, then manage them in System Settings." : "Start a scan to review real files on this Mac.").foregroundStyle(.secondary).padding(.top, 8)
                Button("Start scan") { model.scan() }.buttonStyle(PrimaryButton()).padding(.top, 22)
                Spacer()
            } else {
                results
            }
        }.foregroundStyle(Theme.ink)
            .animation(motion.standard, value: model.isScanning)
    }
    private var results: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("\(model.entries.count) \(model.entries.count == 1 ? "item" : "items")").font(.system(size: 19, weight: .semibold, design: .rounded))
                Text(formattedBytes(model.entries.reduce(0) { $0 + $1.bytes })).font(.system(size: 14)).foregroundStyle(.secondary)
                Spacer()
                if !model.issues.isEmpty { Button("\(model.issues.count) access notes") { model.showIssues = true }.font(.system(size: 11)) }
                TextField("Search files", text: $model.search).textFieldStyle(.roundedBorder).frame(width: 180)
                Picker("Category", selection: $model.category) { ForEach(model.categories, id: \.self) { Text($0) } }.labelsHidden().frame(width: 150)
            }.padding(22)
            if model.module == .storage { storageBar }
            Divider()
            if model.filtered.isEmpty {
                Spacer(); Text(model.entries.isEmpty ? "No matching items found in accessible folders." : "No results match your search.").foregroundStyle(.secondary); Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(model.filtered) { item in fileRow(item) }
                    }.padding(12)
                }
            }
            Divider()
            HStack {
                if model.module == .storage {
                    Text("Double-click a folder to explore. Sizes are logical file sizes.").font(.system(size: 11)).foregroundStyle(.secondary)
                } else if model.module == .background {
                    Text("Inspection only. macOS manages these items.").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(); Button("Open Login Items settings") { model.openLoginSettings() }.buttonStyle(PrimaryButton())
                } else {
                    Text("\(model.selectedEntries.count) selected").font(.system(size: 13, weight: .medium))
                    Text(formattedBytes(model.selectedBytes)).foregroundStyle(.secondary)
                    Button("Clear selection") { model.selected = [] }.buttonStyle(.link).disabled(model.selected.isEmpty)
                    Spacer()
                    Button { model.beginReview() } label: { Label("Move to Trash", systemImage: "trash") }.buttonStyle(PrimaryButton()).disabled(model.selected.isEmpty).opacity(model.selected.isEmpty ? 0.4 : 1)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white)
        }
    }
    private func fileRow(_ item: FileEntry) -> some View {
        HStack(spacing: 13) {
            if item.removable {
                Toggle("Select \(item.name)", isOn: Binding(get: { model.selected.contains(item.id) }, set: { if $0 { model.selected.insert(item.id) } else { model.selected.remove(item.id) } })).labelsHidden().toggleStyle(.checkbox)
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(item.url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(item.category).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(formattedBytes(item.bytes)).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(width: 85, alignment: .trailing)
            Button { model.reveal(item.url) } label: { Image(systemName: "arrow.up.forward.square") }.buttonStyle(.borderless).help("Reveal in Finder").accessibilityLabel("Reveal \(item.name) in Finder")
            if model.module == .storage && item.isDirectory {
                Button { model.scan(root: item.url) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless).accessibilityLabel("Explore \(item.name)")
            }
        }.padding(.horizontal, 14).padding(.vertical, 13)
            .background(model.selected.contains(item.id) ? Theme.purple.opacity(0.07) : .white, in: RoundedRectangle(cornerRadius: 10))
            .animation(motion.quick, value: model.selected.contains(item.id))
            .contentShape(Rectangle()).onTapGesture(count: 2) { if model.module == .storage && item.isDirectory { model.scan(root: item.url) } else { model.reveal(item.url) } }
    }
    private var storageBar: some View {
        let items = Array(model.entries.prefix(8))
        let total = max(1, model.entries.reduce(Int64(0)) { $0 + $1.bytes })
        return VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Rectangle().fill(Theme.colors[index % Theme.colors.count]).frame(width: max(0, (geometry.size.width - 16) * CGFloat(item.bytes) / CGFloat(total)))
                            .help("\(item.name): \(formattedBytes(item.bytes))")
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 8))
            }.frame(height: 25)
            HStack(spacing: 12) {
                ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                    Label { Text(item.name).lineLimit(1) } icon: { Circle().fill(Theme.colors[index]).frame(width: 7, height: 7) }.font(.system(size: 10))
                }
            }
        }.padding(.horizontal, 24).padding(.bottom, 20)
    }
    private var activity: some View {
        Group {
            if model.records.isEmpty {
                VStack(spacing: 16) { Image(systemName: "clock.arrow.circlepath").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(Theme.purple); Text("A fresh start").font(.title2.bold()); Text("Items you move to Trash will appear here.").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.records) { record in
                            HStack {
                                Image(systemName: "trash.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.purple)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(URL(fileURLWithPath: record.originalPath).lastPathComponent).font(.system(size: 14, weight: .semibold))
                                    Text("Moved to Trash · \(record.date.formatted()) · \(formattedBytes(record.bytes))").font(.system(size: 11)).foregroundStyle(.secondary)
                                    Text(record.originalPath).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button("Show in Trash") { if FileManager.default.fileExists(atPath: record.trashPath) { model.reveal(URL(fileURLWithPath: record.trashPath)) } else { model.message = "This item is no longer at its recorded Trash location. It may have been restored or permanently deleted." } }.disabled(record.trashPath.isEmpty)
                            }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }.padding(28)
                }
            }
        }
    }
    private var issuesSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Access notes").font(.title2.bold())
            Text("These items could not be inspected. Scan totals cover accessible files only. Up to 50 notes per folder are shown.").foregroundStyle(.secondary)
            ScrollView { Text(model.issues.joined(separator: "\n\n")).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            Button("Done") { model.showIssues = false }.buttonStyle(PrimaryButton())
        }.padding(28).frame(width: 650, height: 480)
    }
}

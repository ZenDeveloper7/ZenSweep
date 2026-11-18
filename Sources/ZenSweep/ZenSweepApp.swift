import SwiftUI
import AppKit

@main struct ZenSweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup { ContentView() }.defaultSize(width: 1180, height: 820).windowStyle(.hiddenTitleBar)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Swift package executables can start with the generic Dock icon. Assign
        // the packaged image explicitly, retaining the vector master as fallback.
        let bundledIcon = Bundle.main.url(forResource: "ZenSweep", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) }
        NSApp.applicationIconImage = bundledIcon ?? LogoArtwork.mark
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

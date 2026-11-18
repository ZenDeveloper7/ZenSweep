import SwiftUI
import AppKit
import Combine

@MainActor final class MotionPreferences: ObservableObject {
    static let shared = MotionPreferences()
    @Published private(set) var reduceMotion: Bool
    @Published private(set) var active = true
    private var subscriptions = Set<AnyCancellable>()
    var ambientEnabled: Bool { Self.allowsAmbient(reduceMotion: reduceMotion, active: active) }
    static func allowsAmbient(reduceMotion: Bool, active: Bool) -> Bool { !reduceMotion && active }
    init() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        active = NSApp?.isActive ?? true
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.active = true }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.active = false }.store(in: &subscriptions)
    }
    var quick: Animation? { reduceMotion ? nil : .easeOut(duration: 0.14) }
    var standard: Animation? { reduceMotion ? nil : .timingCurve(0.2, 0, 0, 1, duration: 0.32) }
}
@MainActor final class EntranceState: ObservableObject { @Published var visible = false }
struct Entrance: ViewModifier {
    let delay: Double
    @StateObject private var state = EntranceState()
    @ObservedObject private var motion = MotionPreferences.shared
    func body(content: Content) -> some View {
        content.opacity(state.visible || motion.reduceMotion ? 1 : 0)
            .offset(y: state.visible || motion.reduceMotion ? 0 : 12)
            .onAppear { withAnimation(motion.reduceMotion ? nil : .timingCurve(0.2, 0, 0, 1, duration: 0.4).delay(delay)) { state.visible = true } }
            .onDisappear { state.visible = false }
    }
}
extension View {
    func arrive(delay: Double = 0) -> some View { modifier(Entrance(delay: delay)) }
}
@MainActor final class HoverState: ObservableObject { @Published var hovered = false }
struct LiftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { LiftButtonBody(configuration: configuration) }
}
private struct LiftButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @StateObject private var state = HoverState()
    @ObservedObject private var motion = MotionPreferences.shared
    var body: some View {
        configuration.label
            .scaleEffect(motion.reduceMotion ? 1 : configuration.isPressed ? 0.985 : state.hovered ? 1.012 : 1)
            .shadow(color: Theme.purple.opacity(state.hovered ? 0.09 : 0), radius: state.hovered ? 14 : 0, y: 6)
            .animation(motion.quick, value: configuration.isPressed)
            .animation(motion.quick, value: state.hovered)
            .onHover { state.hovered = $0 }
    }
}
struct LogoMark: View {
    var body: some View {
        Image(nsImage: LogoArtwork.mark).resizable().interpolation(.high).aspectRatio(contentMode: .fit).accessibilityLabel("ZenSweep logo")
    }
}
struct AmbientGlow: View {
    @ObservedObject private var motion = MotionPreferences.shared
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !motion.ambientEnabled)) { context in
            let phase = motion.ambientEnabled ? sin(context.date.timeIntervalSinceReferenceDate / 4) : 0
            GeometryReader { proxy in
                Ellipse().fill(Color.mint.opacity(0.09)).frame(width: 330, height: 300).blur(radius: 55)
                    .position(x: proxy.size.width * 0.77 + phase * 16, y: proxy.size.height * 0.55 + phase * 10)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct ScanOrbit: View {
    @ObservedObject private var motion = MotionPreferences.shared
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !motion.ambientEnabled)) { context in
            let time = motion.ambientEnabled ? context.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                Circle().stroke(Theme.purple.opacity(0.07), lineWidth: 1).frame(width: 170, height: 170)
                Circle().stroke(Theme.purple.opacity(0.06), lineWidth: 1).frame(width: 210, height: 210)
                Circle().trim(from: 0, to: 0.24).stroke(AngularGradient(colors: [.mint.opacity(0), .mint], center: .center), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 170, height: 170).rotationEffect(.degrees(time.truncatingRemainder(dividingBy: 3) * 120))
                LogoMark().frame(width: 112, height: 112).scaleEffect(1 + sin(time * 2) * 0.025)
            }.frame(width: 230, height: 230)
        }.accessibilityLabel("Scanning files")
    }
}

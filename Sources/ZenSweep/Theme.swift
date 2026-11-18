import SwiftUI

enum Theme {
    static let ink = Color(red: 0.15, green: 0.12, blue: 0.23)
    static let purple = Color(red: 0.43, green: 0.23, blue: 0.82)
    static let pale = Color(red: 0.96, green: 0.95, blue: 0.98)
    static let colors: [Color] = [.purple, .teal, .indigo, .pink, .orange, .blue, .mint]
}
struct PrimaryButton: ButtonStyle {
    @ObservedObject private var motion = MotionPreferences.shared
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold)).padding(.horizontal, 22).padding(.vertical, 12)
            .foregroundStyle(.white).background(Theme.purple.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed && !motion.reduceMotion ? 0.97 : 1)
            .animation(motion.quick, value: configuration.isPressed)
    }
}
struct StorageRing: View {
    let total: Int64
    let free: Int64
    @StateObject private var entrance = EntranceState()
    @ObservedObject private var motion = MotionPreferences.shared
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.13), lineWidth: 22)
            Circle().trim(from: 0, to: (entrance.visible || motion.reduceMotion) && total > 0 ? CGFloat(max(0, min(1, Double(total-free) / Double(total)))) : 0)
                .stroke(AngularGradient(colors: [.cyan, .mint, .purple], center: .center), style: StrokeStyle(lineWidth: 22, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 7) {
                Text(formattedBytes(free)).contentTransition(.numericText()).font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("available").font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
            }
        }.frame(width: 200, height: 200).padding(15)
            .onAppear { withAnimation(motion.reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.1)) { entrance.visible = true } }
            .onDisappear { entrance.visible = false }
    }
}

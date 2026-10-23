import SwiftUI
import UIKit

struct WaterBackground: View {
    var progress: Double
    var active: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var motion = WaterMotion()

    var body: some View {
        GeometryReader { geometry in
            let surface = WaterSurface(fill: motion.level, slope: motion.tilt * geometry.size.width / max(1, geometry.size.height),
                                       swell: motion.swell, ripple: reduceMotion || motion.lowPower || reduceTransparency ? 0 : 0.0025,
                                       phase: motion.phase)
            if reduceTransparency {
                Color(uiColor: .systemBackground)
                    .overlay(alignment: .bottom) {
                        Color.cyan.opacity(colorScheme == .dark ? 0.18 : 0.12)
                            .frame(height: geometry.size.height * min(1, max(0, progress)))
                    }
            } else {
                Rectangle().fill(.white)
                    .colorEffect(ShaderLibrary.opengymWater(
                        .float2(Float(geometry.size.width), Float(geometry.size.height)), .float(Float(motion.phase)),
                        .float(Float(surface.base)), .float(Float(surface.slope)),
                        .float(Float(surface.swell)), .float(Float(surface.ripple)),
                        .float(colorScheme == .dark ? 1 : 0)))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { motion.setProgress(progress); configure() }
        .onDisappear { motion.stop() }
        .onChange(of: progress) { _, value in motion.setProgress(value) }
        .onChange(of: active) { _, _ in configure() }
        .onChange(of: scenePhase) { _, _ in configure() }
        .onChange(of: reduceMotion) { _, _ in configure() }
        .onChange(of: reduceTransparency) { _, _ in configure() }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in configure() }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in configure() }
    }

    private func configure() {
        motion.configure(active: active && scenePhase == .active, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
    }
}

// Xcode previews are design fixtures only; never seed the production store.
#Preview("Water · 50%") { WaterBackground(progress: 0.5, active: true) }
#Preview("Water · Empty") { WaterBackground(progress: 0, active: false) }
#Preview("Water · Full") { WaterBackground(progress: 1, active: false) }

import SwiftUI
import UIKit

struct WaterBackground: View {
    var progress: Double
    var active: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var motion = WaterMotion()

    var body: some View {
        // Read the published frame in body, before GeometryReader's escaping
        // content closure, to explicitly invalidate the shader every frame.
        let frame = motion.frame
        GeometryReader { geometry in
            let surface = WaterSurface(depths: frame.depths, ripple: reduceMotion || reduceTransparency ? 0 : 0.0018,
                                       phase: frame.phase)
            Group {
                if reduceTransparency {
                    ZStack {
                        Color(uiColor: .systemBackground)
                        SolidWaterShape(surface: surface)
                            .fill(colorScheme == .dark ? Color(red: 0.04, green: 0.15, blue: 0.22)
                                  : Color(red: 0.84, green: 0.95, blue: 0.98))
                    }
                    .clipped()
                } else {
                    Rectangle().fill(.white)
                        .colorEffect(ShaderLibrary.opengymWater(
                            .float2(Float(geometry.size.width), Float(geometry.size.height)), .float(Float(frame.phase)),
                            .floatArray(frame.depths.map(Float.init)), .floatArray(frame.velocities.map(Float.init)),
                            .floatArray(frame.foam.map(Float.init)), .float(Float(surface.rippleAmplitude)), .float(Float(frame.level)),
                            .float(colorScheme == .dark ? 1 : 0)))
                }
            }
            .onAppear { motion.setViewport(geometry.size) }
            .onChange(of: geometry.size) { _, size in motion.setViewport(size) }
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
        motion.configure(active: active && scenePhase == .active, reduceMotion: reduceMotion)
    }
}

// Reducing transparency changes the material, not the gravity response.
private struct SolidWaterShape: Shape {
    var surface: WaterSurface

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0...96 {
            let x = Double(index) / 96
            let point = CGPoint(x: rect.minX + x * rect.width,
                                y: rect.minY + surface.waterline(at: x) * rect.height)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// Xcode previews are design fixtures only; never seed the production store.
#Preview("Water · 50%") { WaterBackground(progress: 0.5, active: true) }
#Preview("Water · Empty") { WaterBackground(progress: 0, active: false) }
#Preview("Water · Full") { WaterBackground(progress: 1, active: false) }

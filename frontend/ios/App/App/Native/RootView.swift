import SwiftUI
import UIKit

struct RootView: View {
    @State private var store = GymStore()
    @State private var centerActionFrame: CGRect?
    @State private var keyboardVisible = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.tab) {
            Tab("今天", systemImage: "sun.max", value: AppTab.today) {
                TodayView()
            }
            Tab("计划", systemImage: "calendar", value: AppTab.plan) {
                PlanView()
            }
            Tab(value: AppTab.workout) {
                WorkoutView()
            } label: {
                Label {
                    Text("开始")
                } icon: {
                    if showsCenterAction {
                        // Keep the native item and its label/accessibility, reserving its icon space.
                        Image(uiImage: Self.clearTabIcon).renderingMode(.original)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .badge(store.active != nil && !showsCenterAction ? Text("练") : nil)
            Tab("身体", systemImage: "figure.strengthtraining.traditional", value: AppTab.body) {
                BodyView()
            }
            Tab("喝水", systemImage: "drop", value: AppTab.water) {
                WaterView()
            }
        }
        .environment(store)
        .tabBarMinimizeBehavior(.never)
        .background {
            NativeTabBarAnchor { centerActionFrame = $0 }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay {
            if showsCenterAction, let frame = centerActionFrame {
                GeometryReader { _ in
                    Button { store.tab = .workout } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 27, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: frame.width, height: frame.height)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
                    .overlay(alignment: .topTrailing) {
                        if store.active != nil {
                            Text("练").font(.caption2.bold()).foregroundStyle(.white)
                                .padding(4).background(.orange, in: .circle)
                                .allowsHitTesting(false)
                        }
                    }
                    // VoiceOver and keyboard navigation use the real middle tab, avoiding two stops.
                    .accessibilityHidden(true)
                    .focusable(false)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            store.wellness.activate()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                store.wellness.refreshTime()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.wellness.activate()
        }
        .alert("记录未保存", isPresented: Binding(
            get: { store.wellness.errorMessage != nil },
            set: { if !$0 { store.wellness.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { store.wellness.errorMessage = nil }
        } message: {
            Text(store.wellness.errorMessage ?? "")
        }
    }

    private var showsCenterAction: Bool { centerActionFrame != nil && !keyboardVisible }

    private static let clearTabIcon = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { _ in }
}

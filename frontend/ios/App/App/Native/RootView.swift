import SwiftUI
import UIKit

struct RootView: View {
    @State private var store = GymStore()
    @State private var navigationTab: AppTab = .today
    @State private var keyboardVisible = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TabView(selection: Binding(
                get: { store.tab == .workout ? navigationTab : store.tab },
                set: { store.tab = $0; navigationTab = $0 }
            )) {
                Tab("今天", systemImage: "sun.max", value: AppTab.today) {
                    TodayView().toolbar(.hidden, for: .tabBar)
                }
                Tab("计划", systemImage: "calendar", value: AppTab.plan) {
                    PlanView().toolbar(.hidden, for: .tabBar)
                }
                Tab("身体", systemImage: "figure.strengthtraining.traditional", value: AppTab.body) {
                    BodyView().toolbar(.hidden, for: .tabBar)
                }
                Tab("喝水", systemImage: "drop", value: AppTab.water) {
                    WaterView().toolbar(.hidden, for: .tabBar)
                }
            }
            .opacity(store.tab == .workout ? 0 : 1)
            .allowsHitTesting(store.tab != .workout)
            .accessibilityHidden(store.tab == .workout)

            // The circular action opens the existing workout flow outside the
            // four navigation tabs. Their NavigationStacks stay mounted below.
            if store.tab == .workout {
                WorkoutView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                HomeDock(selection: store.tab, hasWorkout: store.active != nil) { store.tab = $0 }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            }
        }
        .environment(store)
        .onChange(of: store.tab) { _, value in
            if value != .workout { navigationTab = value }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            store.wellness.activate()
            await store.cloud.sync(store: store)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                store.wellness.refreshTime()
                await store.cloud.sync(store: store)
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
}

// Native SwiftUI controls/materials, composed as two separate shapes. This is
// intentionally not a prominent item inside UITabBar or a geometry overlay on it.
private struct HomeDock: View {
    var selection: AppTab
    var hasWorkout: Bool
    var select: (AppTab) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 12) {
                Button { select(.workout) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.green).interactive(), in: .circle)
                .overlay(alignment: .topTrailing) {
                    if hasWorkout {
                        Circle().fill(.orange).frame(width: 10, height: 10).padding(3).allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(hasWorkout ? "继续训练" : "开始训练")
                .accessibilityIdentifier("start-workout-action")

                HStack(spacing: 0) {
                    destination(.today, title: "今天", symbol: "sun.max")
                    destination(.plan, title: "计划", symbol: "calendar")
                    destination(.body, title: "身体", symbol: "figure.strengthtraining.traditional")
                    destination(.water, title: "喝水", symbol: "drop")
                }
                .padding(4)
                .glassEffect(.regular, in: .capsule)
            }
        }
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity)
    }

    private func destination(_ tab: AppTab, title: String, symbol: String) -> some View {
        let selected = selection == tab
        return Button { select(tab) } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 21, weight: .medium))
                if !dynamicType.isAccessibilitySize { Text(title).font(.caption2).lineLimit(1) }
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background { if selected { Capsule().fill(Color.accentColor.opacity(0.14)) } }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

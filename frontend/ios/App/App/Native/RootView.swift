import SwiftUI
import UIKit

struct RootView: View {
    @State private var store = GymStore()
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
            Tab("开始", systemImage: "play.fill", value: AppTab.workout) {
                WorkoutView()
            }
            .badge(store.active.map { _ in Text("练") })
            Tab("身体", systemImage: "figure.strengthtraining.traditional", value: AppTab.body) {
                BodyView()
            }
            Tab("喝水", systemImage: "drop", value: AppTab.water) {
                WaterView()
            }
        }
        .environment(store)
        .tabBarMinimizeBehavior(.onScrollDown)
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
}

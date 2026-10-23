import SwiftUI

struct RootView: View {
    @State private var store = GymStore()

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
    }
}

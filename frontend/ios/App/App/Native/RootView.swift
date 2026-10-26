import SwiftUI
import UIKit

struct RootView: View {
    @State private var store = GymStore()
    @State private var navigationTab: AppTab = .today
    @State private var visitedTabs: Set<AppTab> = [.today]
    @State private var keyboardVisible = false
    @State private var workoutRequest = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // Keep each visited NavigationStack alive without rendering a second,
            // hidden system tab bar. UIKit below owns the actual tab control.
            ForEach(NativeNavigationTabs.destinations, id: \.tab) { destination in
                if visitedTabs.contains(destination.tab) {
                    page(destination.tab)
                        .opacity(store.tab == destination.tab ? 1 : 0)
                        .allowsHitTesting(store.tab == destination.tab)
                        .accessibilityHidden(store.tab != destination.tab)
                }
            }

            // The circular action opens the existing workout flow outside the
            // four navigation tabs. Their NavigationStacks stay mounted below.
            if store.tab == .workout {
                WorkoutView().id(workoutRequest)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                HStack(spacing: 4) {
                    Button {
                        // Reopening an existing workout is an action even when
                        // its chooser is already visible under the tab bar.
                        workoutRequest += 1
                        store.tab = .workout
                    } label: {
                        Image(systemName: store.active == nil ? "plus" : "play.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .accessibilityLabel(store.active == nil ? "开始训练" : "继续训练")
                    .accessibilityIdentifier("start-workout-action")

                    NativeNavigationTabs(selection: navigationTab) { tab in
                        visitedTabs.insert(tab)
                        navigationTab = tab
                        store.tab = tab
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 4)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
        }
        .environment(store)
        .onChange(of: store.tab) { _, value in
            if value != .workout {
                visitedTabs.insert(value)
                navigationTab = value
            }
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

    @ViewBuilder private func page(_ tab: AppTab) -> some View {
        switch tab {
        case .today: TodayView()
        case .plan: PlanView()
        case .body: BodyView()
        case .water: WaterView()
        case .workout: EmptyView() // Training is an action, never a UITabBarItem.
        }
    }
}

// UITabBar is also a public standalone control. Keep its native background,
// selection indicator, gestures and accessibility intact; only handle selection.
// No extra glass layer or hand-drawn capsule is placed over the system control.
private struct NativeNavigationTabs: UIViewRepresentable {
    struct Destination {
        let tab: AppTab
        let title: String
        let symbol: String
    }

    static let destinations: [Destination] = [
        .init(tab: .today, title: "今天", symbol: "sun.max"),
        .init(tab: .plan, title: "计划", symbol: "calendar"),
        .init(tab: .body, title: "身体", symbol: "figure.strengthtraining.traditional"),
        .init(tab: .water, title: "喝水", symbol: "drop")
    ]

    var selection: AppTab
    var select: (AppTab) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(select: select) }

    func makeUIView(context: Context) -> UITabBar {
        let bar = UITabBar(frame: .zero)
        bar.delegate = context.coordinator
        bar.itemPositioning = .fill
        bar.setItems(Self.destinations.enumerated().map { index, destination in
            let item = UITabBarItem(title: destination.title, image: UIImage(systemName: destination.symbol), tag: index)
            item.accessibilityIdentifier = "navigation-\(destination.tab.rawValue)"
            return item
        }, animated: false)
        bar.accessibilityIdentifier = "native-navigation-tabs"
        updateSelection(bar)
        return bar
    }

    func updateUIView(_ bar: UITabBar, context: Context) {
        context.coordinator.select = select
        updateSelection(bar)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITabBar, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingExpandedSize.height))
        return CGSize(width: width, height: max(60, fitted.height))
    }

    private func updateSelection(_ bar: UITabBar) {
        guard let index = Self.destinations.firstIndex(where: { $0.tab == selection }),
              let items = bar.items, items.indices.contains(index) else { return }
        // Do not reset items/selection during a native selection transition.
        if bar.selectedItem !== items[index] { bar.selectedItem = items[index] }
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var select: (AppTab) -> Void

        init(select: @escaping (AppTab) -> Void) { self.select = select }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard NativeNavigationTabs.destinations.indices.contains(item.tag) else { return }
            select(NativeNavigationTabs.destinations[item.tag].tab)
        }
    }
}

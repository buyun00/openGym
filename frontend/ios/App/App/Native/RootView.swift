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
        NativeRootHost(selection: navigationTab, hasWorkout: store.active != nil, keyboardVisible: keyboardVisible,
                       select: { tab in
                           visitedTabs.insert(tab)
                           navigationTab = tab
                           store.tab = tab
                       }, start: {
                           workoutRequest += 1
                           store.tab = .workout
                       }) {
            pages.environment(store).environment(\.scenePhase, scenePhase)
        }
        .ignoresSafeArea(.container)
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

    private var pages: some View {
        ZStack {
            ForEach(NativeNavigationTabs.destinations, id: \.tab) { destination in
                if visitedTabs.contains(destination.tab) {
                    page(destination.tab)
                        .opacity(store.tab == destination.tab ? 1 : 0)
                        .allowsHitTesting(store.tab == destination.tab)
                        .accessibilityHidden(store.tab != destination.tab)
                }
            }
            if store.tab == .workout { WorkoutView().id(workoutRequest) }
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

// The native bar and action share one UIKit coordinate system. The hosting
// controller receives their measured occlusion as real safe-area insets.
private struct NativeRootHost<Content: View>: UIViewControllerRepresentable {
    var selection: AppTab
    var hasWorkout: Bool
    var keyboardVisible: Bool
    var select: (AppTab) -> Void
    var start: () -> Void
    var content: Content

    init(selection: AppTab, hasWorkout: Bool, keyboardVisible: Bool,
         select: @escaping (AppTab) -> Void, start: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.hasWorkout = hasWorkout
        self.keyboardVisible = keyboardVisible
        self.select = select
        self.start = start
        self.content = content()
    }

    func makeUIViewController(context: Context) -> RootNavigationController<Content> {
        let controller = RootNavigationController(content: content)
        controller.update(selection: selection, hasWorkout: hasWorkout, keyboardVisible: keyboardVisible,
                          select: select, start: start)
        return controller
    }

    func updateUIViewController(_ controller: RootNavigationController<Content>, context: Context) {
        controller.hosting.rootView = content
        controller.update(selection: selection, hasWorkout: hasWorkout, keyboardVisible: keyboardVisible,
                          select: select, start: start)
    }
}

private enum NativeNavigationTabs {
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
}

private final class RootNavigationController<Content: View>: UIViewController, UITabBarDelegate {
    let hosting: UIHostingController<Content>
    private let tabBar = UITabBar(frame: .zero)
    private let startButton = UIButton(type: .system)
    private var select: (AppTab) -> Void = { _ in }
    private var start: () -> Void = {}
    private var keyboardVisible = false
    private let actionDiameter: CGFloat = 52
    private let contentClearance: CGFloat = 12
    #if DEBUG
    private var lastLayoutDiagnostic = ""
    #endif

    init(content: Content) {
        hosting = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(content:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.backgroundColor = .clear
        hosting.safeAreaRegions = .all
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        tabBar.delegate = self
        tabBar.itemPositioning = .fill
        tabBar.setItems(NativeNavigationTabs.destinations.enumerated().map { index, destination in
            let item = UITabBarItem(title: destination.title, image: UIImage(systemName: destination.symbol), tag: index)
            item.accessibilityIdentifier = "navigation-\(destination.tab.rawValue)"
            return item
        }, animated: false)
        tabBar.accessibilityIdentifier = "native-navigation-tabs"
        view.addSubview(tabBar)

        startButton.accessibilityIdentifier = "start-workout-action"
        startButton.addAction(UIAction { [weak self] _ in self?.start() }, for: .touchUpInside)
        view.addSubview(startButton)
    }

    func update(selection: AppTab, hasWorkout: Bool, keyboardVisible: Bool,
                select: @escaping (AppTab) -> Void, start: @escaping () -> Void) {
        self.select = select
        self.start = start
        self.keyboardVisible = keyboardVisible
        loadViewIfNeeded()
        if let index = NativeNavigationTabs.destinations.firstIndex(where: { $0.tab == selection }),
           let items = tabBar.items, items.indices.contains(index), tabBar.selectedItem !== items[index] {
            tabBar.selectedItem = items[index]
        }
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: hasWorkout ? "play.fill" : "figure.strengthtraining.traditional")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        configuration.baseBackgroundColor = .systemIndigo
        configuration.background.backgroundColor = .systemIndigo
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        startButton.configuration = configuration
        startButton.accessibilityLabel = hasWorkout ? "继续训练" : "开始训练"
        view.setNeedsLayout()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        hosting.view.frame = view.bounds
        let system = windowSafeInsets()
        tabBar.isHidden = keyboardVisible
        startButton.isHidden = keyboardVisible
        if keyboardVisible {
            reserveContent(system: system, bottom: system.bottom)
            return
        }

        let availableWidth = view.bounds.width - system.left - system.right
        let rowWidth = min(600, availableWidth)
        let rowX = system.left + (availableWidth - rowWidth) / 2
        let tabX = rowX + 16 + actionDiameter + 8
        let tabWidth = max(1, rowWidth - 16 - actionDiameter - 8 - 8)
        let proposal = CGSize(width: tabWidth, height: UIView.layoutFittingExpandedSize.height)

        // sizeThatFits includes the bar's own bottom safe area. Measure only
        // after it has a window and has been positioned at the actual bottom.
        // A second pass accommodates the inset becoming known after placement.
        var nativeHeight = tabBar.sizeThatFits(proposal).height
        for _ in 0..<3 {
            tabBar.frame = CGRect(x: tabX, y: view.bounds.maxY - nativeHeight,
                                 width: tabWidth, height: nativeHeight)
            tabBar.setNeedsLayout()
            tabBar.layoutIfNeeded()
            let measured = tabBar.sizeThatFits(proposal).height
            if abs(measured - nativeHeight) < 0.5 { break }
            nativeHeight = measured
        }
        tabBar.frame = CGRect(x: tabX, y: view.bounds.maxY - nativeHeight, width: tabWidth, height: nativeHeight)
        tabBar.layoutIfNeeded()

        // Prefer the real laid-out native item/control frames, not the tab
        // bar's outer frame (which also includes bottom safe-area space).
        let measuredItems = tabItemRegion()
        let itemRegion = measuredItems.rect ?? tabBar.convert(tabBar.safeAreaLayoutGuide.layoutFrame, to: view)
        startButton.frame = CGRect(x: rowX + 16, y: itemRegion.midY - actionDiameter / 2,
                                   width: actionDiameter, height: actionDiameter)
        let occupiedTop = min(tabBar.frame.minY, min(itemRegion.minY, startButton.frame.minY))
        let requiredBottom = view.bounds.maxY - occupiedTop + contentClearance
        reserveContent(system: system, bottom: max(system.bottom, requiredBottom))
        #if DEBUG
        let diagnostic = "bounds=\(view.bounds) system=\(system) tab=\(tabBar.frame) fitted=\(nativeHeight) "
            + "items=\(itemRegion) source=\(measuredItems.source) start=\(startButton.frame) "
            + "reservedBottom=\(requiredBottom) additional=\(hosting.additionalSafeAreaInsets) "
            + "hostSafe=\(hosting.view.safeAreaInsets)"
        if diagnostic != lastLayoutDiagnostic {
            print("[RootDockLayout] \(diagnostic)")
            lastLayoutDiagnostic = diagnostic
        }
        #endif
    }

    private func tabItemRegion() -> (rect: CGRect?, source: String) {
        let identifiers = Set(NativeNavigationTabs.destinations.map { "navigation-\($0.tab.rawValue)" })
        var identified: [CGRect] = []
        var controls: [CGRect] = []
        func inspect(_ candidate: UIView) {
            guard !candidate.isHidden, candidate.alpha > 0, !candidate.bounds.isEmpty else { return }
            let frame = candidate.convert(candidate.bounds, to: view)
            if let identifier = candidate.accessibilityIdentifier, identifiers.contains(identifier) {
                identified.append(frame)
                return
            }
            if candidate is UIControl { controls.append(frame) }
            for child in candidate.subviews { inspect(child) }
        }
        for child in tabBar.subviews { inspect(child) }
        let frames: [CGRect]
        let source: String
        if identified.count == NativeNavigationTabs.destinations.count {
            frames = identified; source = "native-item-identifiers"
        } else if controls.count == NativeNavigationTabs.destinations.count {
            frames = controls; source = "native-controls"
        } else {
            // No private class names or KVC. Keep a public-guide fallback and
            // identify it in device diagnostics if UIKit changes its hierarchy.
            return (nil, "safe-area-guide-fallback")
        }
        return (frames.reduce(CGRect.null) { $0.union($1) }, source)
    }

    private func windowSafeInsets() -> UIEdgeInsets {
        let safeFrame: CGRect
        if let window = view.window {
            safeFrame = view.convert(window.safeAreaLayoutGuide.layoutFrame, from: window).intersection(view.bounds)
        } else {
            safeFrame = view.safeAreaLayoutGuide.layoutFrame
        }
        guard !safeFrame.isNull else { return view.safeAreaInsets }
        return UIEdgeInsets(top: max(0, safeFrame.minY - view.bounds.minY),
                            left: max(0, safeFrame.minX - view.bounds.minX),
                            bottom: max(0, view.bounds.maxY - safeFrame.maxY),
                            right: max(0, view.bounds.maxX - safeFrame.maxX))
    }

    private func reserveContent(system: UIEdgeInsets, bottom: CGFloat) {
        let old = hosting.additionalSafeAreaInsets
        let actual = hosting.view.safeAreaInsets
        // Subtract the previous addition to avoid counting the home indicator
        // or our own reservation twice when UIKit lays out again.
        let inherited = UIEdgeInsets(top: max(0, actual.top - old.top), left: max(0, actual.left - old.left),
                                     bottom: max(0, actual.bottom - old.bottom), right: max(0, actual.right - old.right))
        let next = UIEdgeInsets(top: max(0, system.top - inherited.top), left: max(0, system.left - inherited.left),
                               bottom: max(0, bottom - inherited.bottom), right: max(0, system.right - inherited.right))
        if abs(next.top - old.top) > 0.5 || abs(next.left - old.left) > 0.5
            || abs(next.bottom - old.bottom) > 0.5 || abs(next.right - old.right) > 0.5 {
            hosting.additionalSafeAreaInsets = next
        }
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard NativeNavigationTabs.destinations.indices.contains(item.tag) else { return }
        select(NativeNavigationTabs.destinations[item.tag].tab)
    }
}

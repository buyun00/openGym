import SwiftUI
import UIKit

struct RootView: View {
    @State private var store = GymStore()
    @State private var navigationTab: AppTab = .today
    @State private var keyboardVisible = false
    @State private var workoutPresented = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NativeRootHost(selection: navigationTab, keyboardVisible: keyboardVisible,
                       reduceMotion: reduceMotion, contentEnabled: store.tab != .workout && !workoutPresented,
                       select: { tab in
                           navigationTab = tab
                           store.tab = tab
                       }) { tab in
            page(tab).environment(store).environment(\.scenePhase, scenePhase)
        }
        .ignoresSafeArea(.container)
        .environment(store)
        .onChange(of: store.tab, initial: true) { _, value in
            if value != .workout {
                navigationTab = value
            }
            setWorkoutPresented(value == .workout)
        }
        .fullScreenCover(isPresented: Binding(get: { workoutPresented }, set: { presented in
            setWorkoutPresented(presented)
            if !presented && store.tab == .workout { store.tab = .today }
        })) {
            WorkoutView(resuming: store.active != nil, onClose: returnToToday)
                .environment(store).environment(\.scenePhase, scenePhase)
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

    private func setWorkoutPresented(_ presented: Bool) {
        guard workoutPresented != presented else { return }
        // Only the modal binding gets this transaction. Existing page sheets
        // and navigation pushes retain their own system transitions.
        var transaction = Transaction()
        transaction.disablesAnimations = reduceMotion
        withTransaction(transaction) { workoutPresented = presented }
    }

    private func returnToToday() {
        store.tab = .today
        setWorkoutPresented(false)
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

// The system tab bar uses the full available width. The native page container
// forwards its measured occlusion as real safe-area insets to every child.
private struct NativeRootHost<Content: View>: UIViewControllerRepresentable {
    var selection: AppTab
    var keyboardVisible: Bool
    var reduceMotion: Bool
    var contentEnabled: Bool
    var select: (AppTab) -> Void
    var content: (AppTab) -> Content

    init(selection: AppTab, keyboardVisible: Bool,
         reduceMotion: Bool, contentEnabled: Bool,
         select: @escaping (AppTab) -> Void,
         @ViewBuilder content: @escaping (AppTab) -> Content) {
        self.selection = selection
        self.keyboardVisible = keyboardVisible
        self.reduceMotion = reduceMotion
        self.contentEnabled = contentEnabled
        self.select = select
        self.content = content
    }

    func makeUIViewController(context: Context) -> RootNavigationController<Content> {
        let controller = RootNavigationController(content: content)
        controller.update(selection: selection, keyboardVisible: keyboardVisible, reduceMotion: reduceMotion,
                          contentEnabled: contentEnabled, select: select, content: content)
        return controller
    }

    func updateUIViewController(_ controller: RootNavigationController<Content>, context: Context) {
        controller.update(selection: selection, keyboardVisible: keyboardVisible, reduceMotion: reduceMotion,
                          contentEnabled: contentEnabled, select: select, content: content)
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
    private let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    private var hosts: [AppTab: UIHostingController<Content>] = [:]
    private var content: (AppTab) -> Content
    private let tabBar = UITabBar(frame: .zero)
    private var select: (AppTab) -> Void = { _ in }
    private var keyboardVisible = false
    private var reduceMotion = false
    private var contentEnabled = true
    private var requestedSelection: AppTab = .today
    private var displayedSelection: AppTab?
    private var transitionInFlight = false
    private var needsNonanimatedRecovery = false
    private var isVisible = false
    private var isResizing = false
    private let contentClearance: CGFloat = 12

    init(content: @escaping (AppTab) -> Content) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(content:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        addChild(pager)
        pager.view.backgroundColor = .systemBackground
        // No data source: page content gestures remain with the page. Only
        // the native tab bar requests these horizontal navigation transitions.
        pager.dataSource = nil
        view.addSubview(pager.view)
        pager.didMove(toParent: self)

        tabBar.delegate = self
        tabBar.itemPositioning = .fill
        tabBar.setItems(NativeNavigationTabs.destinations.enumerated().map { index, destination in
            let item = UITabBarItem(title: destination.title, image: UIImage(systemName: destination.symbol), tag: index)
            item.accessibilityIdentifier = "navigation-\(destination.tab.rawValue)"
            return item
        }, animated: false)
        tabBar.accessibilityIdentifier = "native-navigation-tabs"
        view.addSubview(tabBar)
    }

    func update(selection: AppTab, keyboardVisible: Bool, reduceMotion: Bool, contentEnabled: Bool,
                select: @escaping (AppTab) -> Void, content: @escaping (AppTab) -> Content) {
        self.select = select
        self.content = content
        self.keyboardVisible = keyboardVisible
        self.reduceMotion = reduceMotion
        self.contentEnabled = contentEnabled
        requestedSelection = selection
        // Reuse each hosting controller/SwiftUI identity rather than destroying
        // navigation stacks, form state and scroll views at every tab change.
        for (tab, hosting) in hosts { hosting.rootView = content(tab) }
        loadViewIfNeeded()
        if let index = NativeNavigationTabs.destinations.firstIndex(where: { $0.tab == selection }),
           let items = tabBar.items, items.indices.contains(index), tabBar.selectedItem !== items[index] {
            tabBar.selectedItem = items[index]
        }
        synchronizeInteraction()
        showRequestedTabIfPossible()
        view.setNeedsLayout()
    }

    private func host(for tab: AppTab) -> UIHostingController<Content> {
        if let hosting = hosts[tab] { return hosting }
        let hosting = UIHostingController(rootView: content(tab))
        hosting.safeAreaRegions = .all
        hosting.view.backgroundColor = .systemBackground
        hosts[tab] = hosting
        return hosting
    }

    private func showRequestedTabIfPossible() {
        guard !transitionInFlight, !isResizing else { return }
        let target = requestedSelection
        guard displayedSelection != target,
              let targetIndex = NativeNavigationTabs.destinations.firstIndex(where: { $0.tab == target }) else {
            synchronizeInteraction()
            return
        }
        let sourceIndex = displayedSelection.flatMap { current in
            NativeNavigationTabs.destinations.firstIndex { $0.tab == current }
        } ?? targetIndex
        let direction: UIPageViewController.NavigationDirection = targetIndex >= sourceIndex ? .forward : .reverse
        let animated = displayedSelection != nil && isVisible && view.window != nil
            && contentEnabled && !reduceMotion && !needsNonanimatedRecovery
        needsNonanimatedRecovery = false
        transitionInFlight = true
        synchronizeInteraction()
        let destination = host(for: target)
        pager.setViewControllers([destination], direction: direction, animated: animated) { [weak self] _ in
            guard let self else { return }
            // UIKit is authoritative if a transition was interrupted by a
            // size/lifecycle change. Never infer that the requested page won.
            let actual = self.pager.viewControllers?.first
            self.displayedSelection = self.hosts.first(where: { $0.value === actual })?.key
            self.needsNonanimatedRecovery = self.displayedSelection != target
            // One latest request, not a queue of intermediate taps. Defer the
            // unlock too: a SwiftUI update can arrive during this completion.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.transitionInFlight = false
                self.synchronizeInteraction()
                self.showRequestedTabIfPossible()
            }
        }
    }

    private func synchronizeInteraction() {
        tabBar.isUserInteractionEnabled = contentEnabled
        let settled = !transitionInFlight && displayedSelection == requestedSelection && contentEnabled
        pager.view.isUserInteractionEnabled = settled
        pager.view.accessibilityElementsHidden = !settled
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        showRequestedTabIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        isResizing = true
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.isResizing = false
            DispatchQueue.main.async { [weak self] in self?.showRequestedTabIfPossible() }
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        pager.view.frame = view.bounds
        let system = windowSafeInsets()
        tabBar.isHidden = keyboardVisible
        if keyboardVisible {
            reserveContent(system: system, bottom: system.bottom)
            return
        }

        // UITabBar owns its internal margins and capsule drawing; there is no
        // separate action, reserved left column, or artificial maximum width.
        let tabX = system.left
        let tabWidth = max(1, view.bounds.width - system.left - system.right)
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

        let requiredBottom = view.bounds.maxY - tabBar.frame.minY + contentClearance
        reserveContent(system: system, bottom: max(system.bottom, requiredBottom))
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
        // The native page container forwards this same viewport to each child.
        let old = pager.additionalSafeAreaInsets
        let actual = pager.view.safeAreaInsets
        // Subtract the previous addition to avoid counting the home indicator
        // or our own reservation twice when UIKit lays out again.
        let inherited = UIEdgeInsets(top: max(0, actual.top - old.top), left: max(0, actual.left - old.left),
                                     bottom: max(0, actual.bottom - old.bottom), right: max(0, actual.right - old.right))
        let next = UIEdgeInsets(top: max(0, system.top - inherited.top), left: max(0, system.left - inherited.left),
                               bottom: max(0, bottom - inherited.bottom), right: max(0, system.right - inherited.right))
        if abs(next.top - old.top) > 0.5 || abs(next.left - old.left) > 0.5
            || abs(next.bottom - old.bottom) > 0.5 || abs(next.right - old.right) > 0.5 {
            pager.additionalSafeAreaInsets = next
        }
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard NativeNavigationTabs.destinations.indices.contains(item.tag) else { return }
        select(NativeNavigationTabs.destinations[item.tag].tab)
    }
}

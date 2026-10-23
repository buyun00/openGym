import SwiftUI
import UIKit

// Read public UITabBar geometry only; the system still owns all tab items, layout and selection.
// The raised SwiftUI button remains in RootView's hierarchy, underneath normal sheet presentation.
struct NativeTabBarAnchor: UIViewRepresentable {
    var onChange: (CGRect?) -> Void

    func makeUIView(context: Context) -> TabBarAnchorView { TabBarAnchorView(frame: .zero) }

    func updateUIView(_ view: TabBarAnchorView, context: Context) {
        view.onChange = onChange
        view.scheduleMeasurement()
    }
}

final class TabBarAnchorView: UIView {
    var onChange: ((CGRect?) -> Void)?
    private var lastFrame: CGRect?
    private var measurementPending = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleMeasurement()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleMeasurement()
    }

    func scheduleMeasurement() {
        guard !measurementPending else { return }
        measurementPending = true
        // Publish after UIKit layout, never mutate SwiftUI state during updateUIView/layoutSubviews.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.measurementPending = false
            let frame = self.centerActionFrame()
            guard frame != self.lastFrame else { return }
            self.lastFrame = frame
            self.onChange?(frame)
        }
    }

    private func centerActionFrame() -> CGRect? {
        guard let window, bounds.width > 0, bounds.height > 0,
              let controller = findTabController(in: window.rootViewController),
              controller.isViewLoaded else { return nil }
        let bar = controller.tabBar
        guard bar.window === window, !bar.isHidden, bar.alpha > 0.01 else { return nil }
        let rect = bar.convert(bar.bounds, to: self)
        // iPad may place its native tabs at the top. Keep its regular middle tab in that layout.
        guard rect.width > 0, rect.height > 0, rect.midY > bounds.midY, rect.intersects(bounds) else { return nil }
        let contentHeight = max(0, rect.height - bar.safeAreaInsets.bottom)
        guard contentHeight >= 32 else { return nil }
        let diameter = min(60, rect.width / 5 - 8)
        guard diameter >= 44 else { return nil }
        let centerY = rect.minY + contentHeight / 2 - 16
        return CGRect(x: bounds.midX - diameter / 2, y: centerY - diameter / 2,
                      width: diameter, height: diameter)
    }

    private func findTabController(in controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tabs = controller as? UITabBarController { return tabs }
        for child in controller.children {
            if let tabs = findTabController(in: child) { return tabs }
        }
        return nil
    }
}

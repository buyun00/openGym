import SwiftUI
import UIKit
import Capacitor
import Combine

// UIKit owns this app's scene. Forward its lifecycle to the hosted SwiftUI tree
// so animation clocks and foreground tasks do not depend on a SwiftUI App scene.
@MainActor
private final class NativeSceneLifecycle: ObservableObject {
    @Published var phase: ScenePhase = .inactive
}

private struct NativeSceneRoot: View {
    @ObservedObject var lifecycle: NativeSceneLifecycle

    var body: some View {
        RootView().environment(\.scenePhase, lifecycle.phase)
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private let lifecycle = NativeSceneLifecycle()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // Store the launch route before SwiftUI first evaluates the root view.
        if let url = connectionOptions.urlContexts.first?.url { _ = GymRoutes.shared.receive(url) }
        switch windowScene.activationState {
        case .foregroundActive: lifecycle.phase = .active
        case .background: lifecycle.phase = .background
        default: lifecycle.phase = .inactive
        }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: NativeSceneRoot(lifecycle: lifecycle))
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) { lifecycle.phase = .active }

    func sceneWillResignActive(_ scene: UIScene) { lifecycle.phase = .inactive }

    func sceneWillEnterForeground(_ scene: UIScene) { lifecycle.phase = .inactive }

    func sceneDidEnterBackground(_ scene: UIScene) { lifecycle.phase = .background }

    func sceneDidDisconnect(_ scene: UIScene) { lifecycle.phase = .background }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        if GymRoutes.shared.receive(url) { return }
        _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, open: url, options: [:])
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, continue: userActivity) { _ in }
    }
}

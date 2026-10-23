// swift-tools-version: 5.9
import PackageDescription

// Pure Foundation checks, independent of CocoaPods, SwiftUI, notification permissions and signing.
// Run: swift test --package-path frontend/ios
let package = Package(
    name: "OpenGymWellnessChecks",
    products: [],
    targets: [
        .target(name: "WellnessCore", path: "App/App/Native",
                exclude: ["RootView.swift", "GymModels.swift", "GymStore.swift", "Catalogue.swift", "TodayView.swift",
                          "PlanView.swift", "WorkoutView.swift", "BodyView.swift", "WaterView.swift", "LibraryView.swift",
                          "EquipmentView.swift", "RoutineEditorView.swift", "exercises.json", "WaterMotion.swift",
                          "WaterBackground.swift", "WaterScene.metal", "NativeTabBarAnchor.swift", "WellnessNotifications.swift", "WellnessStore.swift",
                          "WellnessSettingsSheet.swift", "WaterThirdPartyNotices.txt"],
                sources: ["WellnessModels.swift", "WellnessPersistence.swift", "WaterPhysics.swift"]),
        .testTarget(name: "WellnessCoreTests", dependencies: ["WellnessCore"], path: "Tests/WellnessCoreTests")
    ]
)

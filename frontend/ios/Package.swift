// swift-tools-version: 5.9
import PackageDescription

// Pure Foundation checks, independent of CocoaPods, SwiftUI, notification permissions and signing.
// Run: swift test --package-path frontend/ios
let package = Package(
    name: "OpenGymWellnessChecks",
    products: [],
    targets: [
        .target(name: "WellnessCore", path: "App/App/Native",
                exclude: ["GymCloudSync.swift", "GymConnectionView.swift", "GymSyncBridge.js", "WorkoutLogic.swift", "WorkoutStore.swift", "WorkoutCatalogue.swift", "WorkoutSheets.swift", "WorkoutExerciseCard.swift", "WorkoutExerciseOptions.swift", "WorkoutMediaView.swift", "WorkoutRestAlerts.swift", "workout-catalogue.json", "RootView.swift", "GymModels.swift", "GymStore.swift", "Catalogue.swift", "TodayView.swift",
                          "PlanView.swift", "WorkoutView.swift", "BodyView.swift", "WaterView.swift", "LibraryView.swift",
                          "EquipmentView.swift", "RoutineEditorView.swift", "exercises.json", "WaterMotion.swift",
                          "WaterBackground.swift", "WaterScene.metal", "WellnessNotifications.swift", "WellnessStore.swift",
                          "WellnessSettingsSheet.swift", "WaterThirdPartyNotices.txt", "BodyAnalytics.swift",
                          "BodyCalendarView.swift", "BodyEntrySheet.swift", "BodyMuscleMap.swift", "BodyRecordsSection.swift", "BodyMapNotices.txt"],
                sources: ["WellnessModels.swift", "WellnessPersistence.swift", "WaterPhysics.swift"]),
        .testTarget(name: "WellnessCoreTests", dependencies: ["WellnessCore"], path: "Tests/WellnessCoreTests"),
        .target(name: "BodyCore", path: "App/App/Native",
                exclude: ["GymCloudSync.swift", "GymConnectionView.swift", "GymSyncBridge.js", "WorkoutStore.swift", "WorkoutCatalogue.swift", "WorkoutSheets.swift", "WorkoutExerciseCard.swift", "WorkoutExerciseOptions.swift", "WorkoutMediaView.swift", "WorkoutRestAlerts.swift", "workout-catalogue.json", "RootView.swift", "GymStore.swift", "Catalogue.swift", "TodayView.swift", "PlanView.swift",
                          "WorkoutView.swift", "BodyView.swift", "WaterView.swift", "LibraryView.swift", "EquipmentView.swift",
                          "RoutineEditorView.swift", "exercises.json", "WaterMotion.swift", "WaterBackground.swift", "WaterScene.metal",
                          "WellnessModels.swift", "WellnessPersistence.swift", "WaterPhysics.swift",
                          "WellnessNotifications.swift", "WellnessStore.swift", "WellnessSettingsSheet.swift", "WaterThirdPartyNotices.txt",
                          "BodyCalendarView.swift", "BodyEntrySheet.swift", "BodyMuscleMap.swift", "BodyRecordsSection.swift", "BodyMapNotices.txt"],
                sources: ["GymModels.swift", "BodyAnalytics.swift", "WorkoutLogic.swift"]),
        .testTarget(name: "BodyCoreTests", dependencies: ["BodyCore"], path: "Tests/BodyCoreTests"),
        .testTarget(name: "WorkoutCoreTests", dependencies: ["BodyCore"], path: "Tests/WorkoutCoreTests")
    ]
)

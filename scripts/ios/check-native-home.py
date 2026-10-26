"""Static checks only. Requires tree-sitter, tree-sitter-swift and openstep-parser.
Does not typecheck Swift, compile Metal or run the iOS app.
"""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
import sys
import tree_sitter
import tree_sitter_swift
from openstep_parser import OpenStepDecoder

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / "frontend/ios"
NATIVE = IOS / "App/App/Native"
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
arguments = argparse.ArgumentParser(description=__doc__)
arguments.add_argument("--swift-file", action="append", help="Limit Swift syntax parsing to these repository-relative files; project/source-wiring checks still run")
arguments.add_argument("--report", default="docs/dev/water-home-static-checks-2026-10-23.json", help="Repository-relative output report; use a new path to preserve historical evidence")
options = arguments.parse_args()
errors = []
files = sorted(NATIVE.glob("*.swift")) + sorted((IOS / "Tests").rglob("*.swift")) + [IOS / "Package.swift", IOS / "App/App/SceneDelegate.swift"]
if options.swift_file:
    files = [ROOT / name for name in options.swift_file]
for file in files:
    data = file.read_bytes()
    tree = parser.parse(data)
    def walk(node):
        if node.type == "ERROR" or node.is_missing:
            errors.append({"file": file.relative_to(ROOT).as_posix(), "line": node.start_point.row + 1,
                           "type": node.type, "text": data[node.start_byte:node.end_byte].decode("utf8")[:180]})
        for child in node.children:
            walk(child)
    walk(tree.root_node)

pbx = OpenStepDecoder.ParseFromString((IOS / "App/App.xcodeproj/project.pbxproj").read_text("utf8"))
objects = pbx["objects"]
def phase_names(isa):
    phase = next(v for v in objects.values() if v.get("isa") == isa)
    return [objects[objects[id]["fileRef"]].get("path") for id in phase["files"]]

sources = phase_names("PBXSourcesBuildPhase")
resources = phase_names("PBXResourcesBuildPhase")
missing = [p.name for p in NATIVE.iterdir() if p.suffix in [".swift", ".metal"] and p.name not in sources]
plist = plistlib.loads((IOS / "App/App/Info.plist").read_bytes())
today = (NATIVE / "TodayView.swift").read_text("utf8").split("struct WeighInSheet")[0]
root = (NATIVE / "RootView.swift").read_text("utf8")
scene = (IOS / "App/App/SceneDelegate.swift").read_text("utf8")
motion = (NATIVE / "WaterMotion.swift").read_text("utf8")
background = (NATIVE / "WaterBackground.swift").read_text("utf8")
tab_order = re.findall(r'\.init\(tab: \.(\w+), title:', root)
checks = {
    "swift_syntax": not errors,
    "project_object_identifiers": all(len(key) == 24 for key in objects),
    "all_native_sources_in_build": not missing,
    "metal_in_sources": "WaterScene.metal" in sources,
    "license_in_resources": "WaterThirdPartyNotices.txt" in resources,
    "motion_usage_description": bool(plist.get("NSMotionUsageDescription")),
    "four_navigation_tabs": tab_order == ["today", "plan", "body", "water"],
    "native_tab_control": all(token in root for token in ["-> UITabBar", "UITabBar(frame:", "UITabBarItem(", "UITabBarDelegate", "didSelect item:", "bar.selectedItem"]),
    "native_tab_interaction_unmodified": all(token not in root for token in ["HomeDock", "selectionIndicatorImage", "UITapGestureRecognizer", "UIPanGestureRecognizer", "DragGesture", ".toolbar(.hidden, for: .tabBar)", "Capsule().fill", "bar.standardAppearance", "bar.backgroundImage"]),
    "independent_start_button": 'workoutRequest += 1' in root and 'store.tab = .workout' in root and 'WorkoutView().id(workoutRequest)' in root and 'accessibilityIdentifier("start-workout-action")' in root and "workout" not in tab_order,
    "restrained_glass_action": '.buttonBorderShape(.circle)' in root and '.buttonStyle(.glass)' in root and '.tint(.green)' not in root,
    "home_safe_area_reservation": '.safeAreaInset(edge: .bottom, spacing: 0)' in root,
    "home_single_screen_source": 'ScrollView' not in today and 'ViewThatFits(in: .vertical)' in today and '.navigationBarTitleDisplayMode(.inline)' in today,
    "home_no_goal_or_receipt": all(token not in today for token in ['waterGoalML', '未设目标', '设置每日饮水目标', 'lastAddedWaterID', 'Text("已记录']),
    "home_confirmation_only_water_write": today.count('wellness.addWater(') == 1 and 'private func confirmWater()' in today and 'Button(action: confirmWater)' in today and 'selection: $pendingWaterML' in today and '.pickerStyle(.wheel)' in today,
    "home_sync_symbol_and_details": 'NavigationLink { GymConnectionView() }' in today and 'Image(systemName: syncSymbol)' in today and '.accessibilityValue(store.cloud.status)' in today and all(token in today for token in ['store.cloud.busy', 'store.cloud.errorMessage', 'store.cloud.lastSync']) and 'Label(store.cloud.status' not in today,
    "custom_center_button_removed": "NativeTabBarAnchor" not in root and "NativeTabBarAnchor.swift" not in sources and not (NATIVE / "NativeTabBarAnchor.swift").exists(),
    "scene_lifecycle_source_wiring": all(token in scene for token in [r'.environment(\.scenePhase, lifecycle.phase)', "sceneDidBecomeActive", "sceneWillResignActive", "sceneDidEnterBackground"]),
    "published_water_frame_source_wiring": "@Published private(set) var frame" in motion and "@StateObject private var motion" in background and background.index("let frame = motion.frame") < background.index("GeometryReader" + " {"),
    "sensor_callback_source_wiring": "startDeviceMotionUpdates(to: .main)" in motion and "sensorGeneration == generation" in motion,
    "distributed_surface_source_wiring": '.floatArray(frame.depths' in background and '.floatArray(frame.velocities' in background and 'frame.tilt' not in background and 'tiltSpring' not in (NATIVE / 'WaterPhysics.swift').read_text('utf8'),
    "home_scope": all(token not in today for token in ["weekStrip", "DatePicker", "showWeighIn", "store.openToday", "store.startToday"]),
    "no_webview_home": all(token not in today for token in ["WKWebView", "UIViewRepresentable", "HTML"]),
    "separate_persistence": 'wellness-state.json' in (NATIVE / 'WellnessStore.swift').read_text('utf8')
}
evidence_files = list(dict.fromkeys(files + [NATIVE / "RootView.swift", NATIVE / "TodayView.swift", NATIVE / "WellnessStore.swift", IOS / "App/App/SceneDelegate.swift", NATIVE / "WaterScene.metal", NATIVE / "WaterThirdPartyNotices.txt", IOS / "App/App.xcodeproj/project.pbxproj", IOS / "App/App/Info.plist"]))
report = {
    "scope": "Windows static syntax and project/source wiring only; NOT Swift typecheck, Metal compilation, Swift tests, iOS layout, native gestures or device runtime",
    "swift_files_parsed": len(files), "checks": checks, "syntax_errors": errors, "missing_build_sources": missing,
    "syntax_scope": [file.relative_to(ROOT).as_posix() for file in files],
    "existing_generated_prerequisites_missing": [p for p in ["App/App/public", "App/App/config.xml", "App/App/capacitor.config.json", "App/Pods"] if not (IOS / p).exists()],
    "sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in evidence_files}
}
out = ROOT / options.report
out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
print(json.dumps({key: value for key, value in report.items() if key != "sha256"}, ensure_ascii=False, indent=2))
sys.exit(0 if all(checks.values()) else 1)

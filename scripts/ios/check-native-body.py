"""Static iOS body-page checks. This is not a Swift typecheck or an iOS UI test.

Requires tree-sitter==0.26.0, tree-sitter-swift==0.7.4, openstep-parser==2.0.3.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
import tree_sitter
import tree_sitter_swift
from openstep_parser import OpenStepDecoder

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[2]
arguments = argparse.ArgumentParser(description=__doc__)
arguments.add_argument("--report", default="docs/dev/body-page-static-checks-2026-10-23.json",
                       help="Output path relative to the repository; use a new path for a new validation run.")
arguments.add_argument("--paging", action="store_true", help="Also check the four-page body refinement structure.")
options = arguments.parse_args()
IOS = ROOT / "frontend/ios"
NATIVE = IOS / "App/App/Native"
OWNED = ["BodyView.swift", "BodyAnalytics.swift", "BodyCalendarView.swift", "BodyEntrySheet.swift",
         "BodyMuscleMap.swift", "BodyRecordsSection.swift", "GymModels.swift", "GymStore.swift", "Catalogue.swift", "WorkoutView.swift"]
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
files = [NATIVE / name for name in OWNED] + sorted((IOS / "Tests/BodyCoreTests").glob("*.swift")) + [IOS / "Package.swift"]
errors = []
for file in files:
    data = file.read_bytes()
    tree = parser.parse(data)
    stack = [tree.root_node]
    while stack:
        node = stack.pop()
        if node.type == "ERROR" or node.is_missing:
            errors.append({"file": file.relative_to(ROOT).as_posix(), "line": node.start_point.row + 1,
                           "type": node.type, "text": node.text.decode("utf8")[:160]})
        stack.extend(node.children)

project_file = IOS / "App/App.xcodeproj/project.pbxproj"
project = OpenStepDecoder.ParseFromString(project_file.read_text("utf8"))
objects = project["objects"]
def phase_names(isa):
    return [objects[objects[entry]["fileRef"]].get("path", objects[objects[entry]["fileRef"]].get("name"))
            for phase in objects.values() if phase.get("isa") == isa for entry in phase["files"]]

sources = phase_names("PBXSourcesBuildPhase")
resources = phase_names("PBXResourcesBuildPhase")
missing = [name for name in OWNED if name not in sources]
all_missing = [path.name for path in NATIVE.glob("*.swift") if path.name not in sources]
asset_root = IOS / "App/App/Assets.xcassets/BodyMap"
geometry_source = (ROOT / "frontend/src/lib/body-paths.js").read_text("utf8").split("export default ", 1)[1].strip().rstrip(";")
geometry = json.loads(geometry_source)["male"]
muscles = re.search(r"static let muscleOrder = \[(.*?)\]", (NATIVE / "Catalogue.swift").read_text("utf8"), re.S)
muscles = re.findall(r'"([^"]+)"', muscles.group(1))
asset_errors = []
asset_files = []
for side in ["front", "back"]:
    for name in ["silhouette"] + muscles:
        asset = f"BodyMap-{side}-{name}"
        folder = asset_root / f"{asset}.imageset"
        svg_path, json_path = folder / f"{asset}.svg", folder / "Contents.json"
        asset_files.extend([svg_path, json_path])
        try:
            svg = ET.parse(svg_path).getroot()
            config = json.loads(json_path.read_text("utf8"))
            actual = [node.attrib["d"] for node in svg]
            source = geometry[side]
            expected = source["p"].get(name, []) if name != "silhouette" else [d for key, values in source["p"].items() if key not in muscles for d in values]
            if actual != expected or svg.attrib["viewBox"] != source["vb"]:
                asset_errors.append(f"{asset}: geometry drift")
            if config["properties"]["template-rendering-intent"] != "template" or not config["properties"]["preserves-vector-representation"]:
                asset_errors.append(f"{asset}: not a native vector template")
        except Exception as error:
            asset_errors.append(f"{asset}: {error}")

body = "\n".join((NATIVE / name).read_text("utf8") for name in OWNED if name.startswith("Body"))
tests = (IOS / "Tests/BodyCoreTests/BodyAnalyticsTests.swift").read_text("utf8")
checks = {
    "swift_syntax_only": not errors,
    "project_identifiers": all(len(key) == 24 for key in objects),
    "body_sources_in_build": not missing,
    "all_current_native_sources_in_build": not all_missing,
    "body_attribution_bundled": "BodyMapNotices.txt" in resources,
    "asset_catalog_bundled": "Assets.xcassets" in resources,
    "vector_geometry_matches_existing_source": not asset_errors,
    "native_controls_present": all(token in body for token in ["List {", "DisclosureGroup", "Picker(", "Chart(", "UICalendarView()", ".buttonStyle(.bordered)", ".buttonStyle(.borderedProminent)"]),
    "body_content_has_no_explicit_glass": all(token not in body for token in [".buttonStyle(.glass)", ".buttonStyle(.glassProminent)", ".glassEffect(", "GlassEffectContainer"]),
    "no_simulated_glass_or_web_ui": all(token not in body for token in ["WKWebView", ".blur(", "UIVisualEffectView", "Canvas {", "DragGesture", "LinearGradient", "RadialGradient"]),
    "native_calendar_not_custom_grid": "LazyVGrid" not in body and "UICalendarSelectionSingleDate" in body,
    "no_screenshot_or_mockup_in_production": all(token not in body for token in ["IMG_130", "generated_images", "85.5", "25.6", "63.6"]),
}
if options.paging:
    view = (NATIVE / "BodyView.swift").read_text("utf8")
    main = view.split("struct BodyView: View {", 1)[1].split("private struct BodyDetailSheet: View {", 1)[0]
    navigation = main.split("private var pageNavigation: some View {", 1)[1].split("@ViewBuilder private func pageContent", 1)[0]
    detail = view.split("private struct BodyDetailSheet: View {", 1)[1]
    records = (NATIVE / "BodyRecordsSection.swift").read_text("utf8")
    checks.update({
        "exactly_four_page_cases": 'case weight = "体重", muscle = "肌肉", intensity = "强度", records = "记录"' in view,
        "native_viewport_paging": all(token in main for token in ["LazyVStack(spacing: 0)", r"ForEach(BodySection.allCases, id: \.self)",
            ".scrollTargetLayout()", ".scrollTargetBehavior(.paging)"]),
        "one_safe_viewport_sizes_scroll_and_pages": main.count("GeometryReader { viewport in") == 1
            and main.index("GeometryReader { viewport in") < main.index("ScrollView(.vertical)")
            and main.count(".frame(width: viewport.size.width, height: viewport.size.height)") == 2
            and "containerRelativeFrame" not in main,
        "bidirectional_page_navigation": '.scrollPosition(id: $visibleSection, anchor: .top)' in main
            and 'get: { visibleSection ?? .weight }' in main and 'visibleSection = section' in main
            and 'selection: pageSelection' in main and 'pageSelection.wrappedValue = section' in navigation,
        "inline_toolbar_navigation": '.navigationBarTitleDisplayMode(.inline)' in main
            and 'ToolbarItem(placement: .principal) { pageNavigation }' in main
            and all(token not in main for token in ["safeAreaBar", "ScrollViewReader"]),
        "prominent_title_and_plain_text_navigation": 'Text("身体").font(.title2.bold())' in main
            and main.count(".sharedBackgroundVisibility(.hidden)") == 2
            and all(token in navigation for token in [".buttonStyle(.plain)", ".underline(selected)", ".accessibilityAddTraits(selected ? .isSelected : [])"])
            and ".pickerStyle(.segmented)" not in navigation,
        "main_pages_do_not_expand_or_ignore_safe_area": all(token not in main for token in
            ["List {", "DisclosureGroup", "BodyCalendarView(", ".ignoresSafeArea", "UIScreen", ".clipped()", ".clipShape(", ".mask(", ".scrollClipDisabled(", ".minimumScaleFactor", ".lineLimit("]),
        "compact_and_accessibility_detail_fallback": all(token in main for token in
            ["ViewThatFits(in: .vertical)", "typeSize.isAccessibilitySize", "minimalContent(section)", ".sheet(item: $detail)"]),
        "record_date_handoff": "recordDate: selectedRecordDate, recordMonth: visibleMonth" in main
            and "selectedRecordDate = day" in main
            and "BodyRecordsSection(selectedDate: recordDate, visibleMonth: recordMonth)" in detail
            and "_selectedDate = State(initialValue: selectedDate)" in records,
        "detail_edits_and_errors_remain_native": all(token in detail for token in
            ["List {", ".sheet(item: $entry)", 'Button("完成")', 'get: { store.saveError != nil && entry == nil }',
             "store.deleteWeighIn", "store.setTarget", "exerciseChart", "measurementSection"])
            and all(token in records for token in ["store.setRIR", "store.deleteWorkout", "WorkoutHealthUploadSheet"]),
        "record_list_only_contains_workouts": "workouts: workouts, weights: [], measurements: []" in records
            and all(token not in records for token in ["RecordFilter", "store.bodyMeasurements", "store.weighIns", "onEntry", 'Picker("记录类型"']),
    })
report = {
    "scope": "Windows static syntax, project and source/asset checks ONLY; NOT Swift typechecking, XCTest execution, Xcode build or iOS runtime",
    "checks": checks, "swift_files_parsed": len(files), "syntax_errors": errors,
    "missing_build_sources": missing, "other_missing_native_sources": all_missing,
    "vector_template_assets_checked": len(asset_files) // 2, "asset_errors": asset_errors,
    "swift_tests_defined_but_not_executed": len(re.findall(r"func test\w+\(", tests)),
    "unverified": ["Swift typecheck and Swift XCTest", "Xcode build and asset catalog compilation", "iPhone/iPad runtime, native Liquid Glass and calendar layout", "VoiceOver, Dynamic Type and light/dark screenshots",
                   "Paging gestures, toolbar selection synchronization and safe-area fit on device"],
    "sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files + asset_files + [project_file, NATIVE / "BodyMapNotices.txt"]}
}
output = ROOT / options.report
output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
print(json.dumps({key: value for key, value in report.items() if key != "sha256"}, ensure_ascii=False, indent=2))
sys.exit(0 if all(checks.values()) else 1)

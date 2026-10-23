"""Static checks only. Requires tree-sitter, tree-sitter-swift and openstep-parser.
Does not typecheck Swift, compile Metal or run the iOS app.
"""
from pathlib import Path
import hashlib
import json
import plistlib
import sys
import tree_sitter
import tree_sitter_swift
from openstep_parser import OpenStepDecoder

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / "frontend/ios"
NATIVE = IOS / "App/App/Native"
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
errors = []
files = sorted(NATIVE.glob("*.swift")) + sorted((IOS / "Tests").rglob("*.swift")) + [IOS / "Package.swift"]
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
checks = {
    "swift_syntax": not errors,
    "project_object_identifiers": all(len(key) == 24 for key in objects),
    "all_native_sources_in_build": not missing,
    "metal_in_sources": "WaterScene.metal" in sources,
    "license_in_resources": "WaterThirdPartyNotices.txt" in resources,
    "motion_usage_description": bool(plist.get("NSMotionUsageDescription")),
    "system_tab_view": "TabView(selection:" in root and root.count('Tab("') == 5,
    "home_scope": all(token not in today for token in ["weekStrip", "DatePicker", "showWeighIn", "store.openToday", "store.startToday"]),
    "no_webview_home": all(token not in today for token in ["WKWebView", "UIViewRepresentable", "HTML"]),
    "separate_persistence": 'wellness-state.json' in (NATIVE / 'WellnessStore.swift').read_text('utf8')
}
evidence_files = files + [NATIVE / "WaterScene.metal", NATIVE / "WaterThirdPartyNotices.txt", IOS / "App/App.xcodeproj/project.pbxproj", IOS / "App/App/Info.plist"]
report = {
    "scope": "Windows static syntax and project structure only; NOT Swift typecheck, Metal compilation, Swift test execution or iOS runtime",
    "swift_files_parsed": len(files), "checks": checks, "syntax_errors": errors, "missing_build_sources": missing,
    "existing_generated_prerequisites_missing": [p for p in ["App/App/public", "App/App/config.xml", "App/App/capacitor.config.json", "App/Pods"] if not (IOS / p).exists()],
    "sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in evidence_files}
}
out = ROOT / "docs/dev/water-home-static-checks-2026-10-23.json"
out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
print(json.dumps({key: value for key, value in report.items() if key != "sha256"}, ensure_ascii=False, indent=2))
sys.exit(0 if all(checks.values()) else 1)

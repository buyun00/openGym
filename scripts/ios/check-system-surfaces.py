"""Windows syntax + target wiring validation; NOT an Apple SDK typecheck or device test.
Requires tree-sitter, tree-sitter-swift, openstep-parser.
"""
from pathlib import Path
import json
import plistlib
import sys
import tree_sitter
import tree_sitter_swift
from openstep_parser import OpenStepDecoder

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "frontend/ios/App"
objects = OpenStepDecoder.ParseFromString((APP / "App.xcodeproj/project.pbxproj").read_text("utf8"))["objects"]
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
errors = []
files = list((APP / "App").rglob("*.swift")) + list((APP / "Shared").glob("*.swift")) + list((APP / "GymWidgets").glob("*.swift"))
for path in files:
    stack = [parser.parse(path.read_bytes()).root_node]
    while stack:
        node = stack.pop()
        if node.type == "ERROR" or node.is_missing:
            errors.append(f"{path.relative_to(ROOT)}:{node.start_point.row + 1}")
        stack.extend(node.children)

targets = {o["name"]: o for o in objects.values() if o.get("isa") == "PBXNativeTarget"}
def paths(target, phase):
    return [objects[objects[f]["fileRef"]]["path"] for p in target["buildPhases"]
            if objects[p]["isa"] == phase for f in objects[p]["files"]]
def configurations(target):
    return [objects[k]["buildSettings"] for k in objects[target["buildConfigurationList"]]["buildConfigurations"]]
def plist(path):
    return plistlib.loads((APP / path).read_bytes())

main, widget = targets["App"], targets["GymWidgets"]
app_sources, widget_sources = paths(main, "PBXSourcesBuildPhase"), paths(widget, "PBXSourcesBuildPhase")
group = ["group.org.lin0.opengym"]
checks = {
    "swift_syntax": not errors,
    "valid_object_ids": all(len(key) == 24 for key in objects),
    "shared_models_in_both_targets": "Shared/GymWidgetData.swift" in app_sources and "Shared/GymWidgetData.swift" in widget_sources,
    "app_services_compiled": all(name in app_sources for name in ["GymSystemSurfaces.swift", "BodyHealthSync.swift"]),
    "widget_has_only_extension_safe_sources": set(widget_sources) == {"Shared/GymWidgetData.swift", "GymWidgets/GymWidgets.swift"},
    "extension_embedded": "GymWidgets.appex" in paths(main, "PBXCopyFilesBuildPhase"),
    "extension_target_dependency": any(objects[objects[d]["target"]] == widget for d in main["dependencies"]),
    "extension_plist": plist("GymWidgets/Info.plist")["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension",
    "matching_groups": all(plist(p)["com.apple.security.application-groups"] == group for p in ["App/App.entitlements", "GymWidgets/GymWidgets.entitlements"]),
    "live_activity_enabled": plist("App/Info.plist").get("NSSupportsLiveActivities") is True,
    "deep_link_registered": "opengym" in plist("App/Info.plist")["CFBundleURLTypes"][0]["CFBundleURLSchemes"],
    "widget_build_settings": all(c.get("APPLICATION_EXTENSION_API_ONLY") == "YES" and c.get("SKIP_INSTALL") == "YES"
                                  and c.get("CODE_SIGN_ENTITLEMENTS") == "GymWidgets/GymWidgets.entitlements" for c in configurations(widget)),
    "no_background_delivery_entitlement": "com.apple.developer.healthkit.background-delivery" not in plist("App/App.entitlements"),
}
report = {"scope": "Syntax and Xcode wiring only; Xcode compile/signing and device acceptance pending",
          "swift_files": len(files), "checks": checks, "syntax_errors": errors}
print(json.dumps(report, indent=2))
sys.exit(0 if all(checks.values()) else 1)

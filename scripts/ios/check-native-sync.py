"""Syntax/build-reference checks only. Does not replace Xcode or device validation."""
from pathlib import Path
import hashlib
import json
import sys
import tree_sitter
import tree_sitter_swift
from openstep_parser import OpenStepDecoder

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / "frontend/ios/App/App/Native"
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
errors = []
for path in list(NATIVE.glob("*.swift")) + [ROOT / "frontend/ios/Package.swift"]:
    todo = [parser.parse(path.read_bytes()).root_node]
    while todo:
        node = todo.pop()
        if node.type == "ERROR" or node.is_missing:
            errors.append({"file": path.name, "line": node.start_point.row + 1})
        todo.extend(node.children)
project = OpenStepDecoder.ParseFromString((ROOT / "frontend/ios/App/App.xcodeproj/project.pbxproj").read_text("utf8"))
objects = project["objects"]
def names(phase):
    return [objects[objects[entry]["fileRef"]].get("path", objects[objects[entry]["fileRef"]].get("name"))
            for obj in objects.values() if obj.get("isa") == phase for entry in obj["files"]]
sources = names("PBXSourcesBuildPhase")
resources = names("PBXResourcesBuildPhase")
personal_phase = objects.get("A52000000000000000000001", {})
personal_in_build = any("A52000000000000000000001" in obj.get("buildPhases", []) for obj in objects.values())
missing = [p.name for p in NATIVE.glob("*.swift") if p.name not in sources]
result = {
    "scope": "Swift syntax and Xcode project references ONLY; not typechecking, build or iPhone runtime",
    "swift_syntax_errors": errors,
    "missing_sources": missing,
    "bridge_in_resources": "GymSyncBridge.js" in resources,
    "personal_config_build_phase": personal_in_build and personal_phase.get("isa") == "PBXShellScriptBuildPhase"
        and "$(SRCROOT)/Private/GymPersonalConnection.json" in personal_phase.get("inputPaths", [])
        and (ROOT / "scripts/ios/embed-personal-connection.sh").is_file(),
    "sha256": {name: hashlib.sha256((NATIVE / name).read_bytes()).hexdigest()
               for name in ["GymCloudSync.swift", "GymConnectionView.swift", "GymSyncBridge.js", "GymStore.swift"]},
}
print(json.dumps(result, indent=2))
if errors or missing or not result["bridge_in_resources"] or not result["personal_config_build_phase"]:
    sys.exit(1)

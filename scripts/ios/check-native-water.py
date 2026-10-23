"""Scoped drink-page syntax/project checks; not Swift typechecking or iOS runtime.

Requires tree-sitter, tree-sitter-swift and openstep-parser.
"""
from pathlib import Path
import hashlib
import json
import sys
import tree_sitter
import tree_sitter_swift
from openstep_parser import OpenStepDecoder

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / "frontend/ios"
NATIVE = IOS / "App/App/Native"
OWNED = ["WaterView.swift", "WellnessModels.swift", "WellnessStore.swift"]
DEPENDENCIES = ["TodayView.swift", "RootView.swift", "WaterBackground.swift",
                "WaterMotion.swift", "WellnessPersistence.swift", "WellnessNotifications.swift"]
files = [NATIVE / name for name in OWNED + DEPENDENCIES]
files += sorted((IOS / "Tests/WellnessCoreTests").glob("*.swift"))
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
errors = []
for file in files:
    data = file.read_bytes()
    stack = [parser.parse(data).root_node]
    while stack:
        node = stack.pop()
        if node.type == "ERROR" or node.is_missing:
            errors.append({"file": file.relative_to(ROOT).as_posix(), "line": node.start_point.row + 1,
                           "type": node.type, "text": node.text.decode("utf8")[:180]})
        stack.extend(node.children)

project = IOS / "App/App.xcodeproj/project.pbxproj"
objects = OpenStepDecoder.ParseFromString(project.read_text("utf8"))["objects"]
sources = [objects[objects[entry]["fileRef"]].get("path")
           for phase in objects.values() if phase.get("isa") == "PBXSourcesBuildPhase"
           for entry in phase["files"]]
missing = [name for name in OWNED if name not in sources]
checks = {
    "scoped_swift_syntax": not errors,
    "changed_native_sources_already_in_xcode_build": not missing,
    "water_shader_remains_in_build": "WaterScene.metal" in sources,
}
report = {
    "scope": "Windows tree-sitter syntax and existing Xcode source membership ONLY",
    "not_verified": ["Swift typechecking", "XCTest execution", "Xcode / Metal compilation",
                     "iOS layout, accessibility and interaction", "iPhone motion and performance"],
    "changed_sources": OWNED,
    "swift_files_parsed": len(files),
    "checks": checks,
    "syntax_errors": errors,
    "missing_build_sources": missing,
    "sha256": {file.relative_to(ROOT).as_posix(): hashlib.sha256(file.read_bytes()).hexdigest()
               for file in files + [project, IOS / "Package.swift"]},
}
out = ROOT / "docs/dev/water-page-static-checks-2026-10-23.json"
out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8", newline="\n")
print(json.dumps({k: v for k, v in report.items() if k != "sha256"}, ensure_ascii=False, indent=2))
sys.exit(0 if all(checks.values()) else 1)

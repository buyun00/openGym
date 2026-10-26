"""Windows checks for the native training flow; NOT a Swift typecheck or iOS run.

Requires tree-sitter==0.26.0, tree-sitter-swift==0.7.4, openstep-parser==2.0.3.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys
import tree_sitter
import tree_sitter_swift
from openstep_parser import OpenStepDecoder

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[2]
arguments = argparse.ArgumentParser(description=__doc__)
arguments.add_argument("--output", type=Path, default=ROOT / "docs/dev/workout-page-static-checks-2026-10-23.json",
                       help="Write this run's static evidence without replacing an earlier report.")
options = arguments.parse_args()
IOS = ROOT / "frontend/ios"
NATIVE = IOS / "App/App/Native"
sources = sorted(NATIVE.glob("Workout*.swift")) + [NATIVE / name for name in ["GymModels.swift", "GymStore.swift", "Catalogue.swift", "RoutineEditorView.swift"]]
tests = sorted((IOS / "Tests/WorkoutCoreTests").glob("*.swift"))
files = sources + tests + [IOS / "Package.swift"]
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
errors = []
for file in files:
    stack = [parser.parse(file.read_bytes()).root_node]
    while stack:
        node = stack.pop()
        if node.type == "ERROR" or node.is_missing:
            errors.append({"file": file.relative_to(ROOT).as_posix(), "line": node.start_point.row + 1, "type": node.type})
        stack.extend(node.children)

project_path = IOS / "App/App.xcodeproj/project.pbxproj"
project = OpenStepDecoder.ParseFromString(project_path.read_text("utf8"))
objects = project["objects"]
def phase_paths(kind):
    return [objects[objects[entry]["fileRef"]].get("path", objects[objects[entry]["fileRef"]].get("name")) for phase in objects.values()
            if phase.get("isa") == kind for entry in phase["files"]]
build_sources = phase_paths("PBXSourcesBuildPhase")
build_resources = phase_paths("PBXResourcesBuildPhase")
metadata_path = NATIVE / "workout-catalogue.json"
metadata = json.loads(metadata_path.read_text("utf8"))
catalogue = json.loads((NATIVE / "exercises.json").read_text("utf8"))
missing_ids = [record["id"] for record in catalogue if record["id"] not in metadata]
media_errors = []
for key, record in metadata.items():
    for field, folder in [("clip", "clip"), ("still", "still")]:
        filename = record.get(field)
        if filename and (Path(filename).name != filename or not (ROOT / "catalogue/media" / folder / filename).is_file()):
            media_errors.append(f"{key}: {field} {filename}")

view_source = "\n".join(file.read_text("utf8") for file in sources if file.name not in ["GymModels.swift", "GymStore.swift", "Catalogue.swift", "WorkoutLogic.swift", "WorkoutStore.swift"])
explicit_glass = [
    {"file": file.relative_to(ROOT).as_posix(), "line": line_number}
    for file in sources if file.name.startswith("Workout")
    for line_number, line in enumerate(file.read_text("utf8").splitlines(), 1)
    if re.search(r"\.\s*(?:glass(?:Prominent)?\b|glassEffect\b)|\bGlassEffectContainer\b", line)
]
native_missing = [p.name for p in NATIVE.glob("*.swift") if p.name not in build_sources]
stale_sources = [name for name in build_sources if name.endswith(".swift") and not (NATIVE / name).is_file() and not (IOS / "App/App" / name).is_file()]
media_reference = [obj for obj in objects.values() if obj.get("isa") == "PBXFileReference" and obj.get("path") == "../../../catalogue/media"]
checks = {
    "swift_syntax_only": not errors,
    "project_object_identifiers": all(len(key) == 24 for key in objects),
    "all_current_native_sources_registered": not native_missing,
    "registered_swift_sources_exist": not stale_sources,
    "workout_metadata_bundled": "workout-catalogue.json" in build_resources,
    "actual_media_folder_bundled": "../../../catalogue/media" in build_resources and len(media_reference) == 1 and media_reference[0].get("sourceTree") == "SOURCE_ROOT",
    "media_source_path_resolves": (IOS / "App" / "../../../catalogue/media").resolve() == (ROOT / "catalogue/media").resolve(),
    "media_notice_available_in_bundled_folder": (ROOT / "catalogue/media/NOTICE.md").is_file(),
    "metadata_covers_existing_native_ids": not missing_ids,
    "all_declared_media_files_exist": not media_errors,
    "reference_treadmill_is_cardio_with_incline": metadata["2259"]["mode"] == "cardio" and metadata["2259"]["incline"] is True,
    "native_controls_and_system_presentations": all(token in view_source for token in [".buttonStyle(.bordered)", ".buttonStyle(.borderedProminent)", "NavigationStack", ".sheet(", "TextField(", "Picker(", "Toggle("]),
    "no_explicit_glass_in_workout_sources": not explicit_glass,
    "native_video_api_references": "AVPlayerLooper" in view_source and "AVPlayerLayer" in view_source,
    "no_web_ui_or_screenshot_substitution": all(token not in view_source for token in ["WKWebView", ".blur(", "IMG_131", "generated_images"]),
}
report = {
    "scope": "Static Swift syntax / Xcode project / catalogue-media checks ONLY. NOT Swift typechecking, XCTest execution, Xcode compilation or iOS visual acceptance.",
    "checks": checks,
    "swift_files_parsed": len(files),
    "syntax_errors": errors,
    "missing_build_sources": native_missing,
    "stale_build_sources": stale_sources,
    "metadata_ids": len(metadata),
    "missing_metadata_ids": missing_ids,
    "media_errors": media_errors,
    "explicit_glass_usages": explicit_glass,
    "swift_tests_defined_but_not_executed": sum(len(re.findall(r"func test\w+\(", p.read_text("utf8"))) for p in tests),
    "unverified": ["Swift typecheck and XCTest on a Swift host", "Xcode 26+ simulator build", "iPhone button materials, visuals and all interactions", "background notification delivery and AVPlayer looping", "Dynamic Type, VoiceOver, light/dark and orientation"],
    "sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files + [project_path, metadata_path]},
}
output = options.output
output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
print(json.dumps({k: v for k, v in report.items() if k != "sha256"}, ensure_ascii=False, indent=2))
sys.exit(0 if all(checks.values()) else 1)

"""Measure the indigo action and visible tab capsule in an original R3 screenshot.

Read-only image analysis (Pillow + NumPy), not an iOS layout test or a runtime
offset generator. Coordinates refer to original pixel centers, never a resized
preview. The footer/color assumptions are specific to the supplied R3 evidence.
"""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np
from PIL import Image


def circle_measurement(pixels, threshold):
    height, width, _ = pixels.shape
    red, green, blue = pixels.transpose(2, 0, 1)
    mask = (blue - red > 50) & (blue - green > threshold) & (blue > 180)
    mask[:int(height * 0.84)] = False
    mask[:, int(width * 0.2):] = False
    ys, xs = np.where(mask)
    if len(xs) < 100:
        raise ValueError("No sufficiently large indigo action in the lower-left region")
    points = []
    # Outer edges only: the white training glyph must not bias the centroid.
    for y in np.unique(ys):
        row = np.flatnonzero(mask[y])
        points.extend(((row[0], y), (row[-1], y)))
    for x in np.unique(xs):
        column = np.flatnonzero(mask[:, x])
        points.extend(((x, column[0]), (x, column[-1])))
    x, y = np.asarray(points, dtype=float).T
    coefficients = np.linalg.lstsq(
        np.column_stack((2 * x, 2 * y, np.ones(len(x)))), x * x + y * y, rcond=None
    )[0]
    cx, cy, constant = coefficients
    radius = float(np.sqrt(constant + cx * cx + cy * cy))
    return {
        "blue_minus_green_threshold": threshold,
        "inclusive_pixel_bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
        "fitted_center_px": [float(cx), float(cy)],
        "fitted_radius_px": radius,
    }


def strongest_edge(profile, start, stop):
    strengths = np.linalg.norm(np.diff(profile, axis=0), axis=1)
    start = max(0, start)
    stop = min(len(strengths), stop)
    if start >= stop:
        raise ValueError("Empty edge-search interval")
    index = start + int(np.argmax(strengths[start:stop]))
    if strengths[index] < 30:
        raise ValueError("Capsule edge is not strong enough for this measurement method")
    return {"boundary_px": index + 0.5, "rgb_jump_magnitude": float(strengths[index])}


def measure(path):
    with Image.open(path) as image:
        pixels = np.asarray(image.convert("RGB"), dtype=float)
    height, width, _ = pixels.shape
    circles = [circle_measurement(pixels, threshold) for threshold in (60, 70, 90, 110)]
    action = circles[1]
    cy = action["fitted_center_px"][1]
    radius = action["fitted_radius_px"]
    vertical = []
    # Three independent central bands suppress labels/icons and water texture.
    for left, right in ((0.40, 0.80), (0.48, 0.72), (0.32, 0.88)):
        x1, x2 = int(width * left), int(width * right)
        profile = np.median(pixels[:, x1:x2], axis=1)
        top = strongest_edge(profile, int(cy - radius * 1.25), int(cy))
        bottom = strongest_edge(profile, int(cy), int(cy + radius * 1.7))
        vertical.append({"x_band_exclusive_end": [x1, x2], "top": top, "bottom": bottom,
                         "center_y_px": (top["boundary_px"] + bottom["boundary_px"]) / 2})
    capsule_cy = float(np.median([band["center_y_px"] for band in vertical]))
    center_row = round(capsule_cy)
    profile = np.median(pixels[center_row - 6:center_row + 7], axis=0)
    left = strongest_edge(profile, action["inclusive_pixel_bbox"][2] + 1, int(width * 0.5))
    right = strongest_edge(profile, int(width * 0.82), width - 1)
    top = float(np.median([band["top"]["boundary_px"] for band in vertical]))
    bottom = float(np.median([band["bottom"]["boundary_px"] for band in vertical]))
    differences = [capsule_cy - entry["fitted_center_px"][1] for entry in circles]
    difference = capsule_cy - cy
    conclusion = ("Start action is above the visible tab capsule center" if difference > 1 else
                  "Start action is below the visible tab capsule center" if difference < -1 else
                  "Within measurement tolerance")
    return {
        "scope": "Measurement of supplied pre-R3 device screenshot only; NOT a post-fix visual pass",
        "image": str(path.resolve()),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "resolution_px": [width, height],
        "coordinate_convention": "Zero-based original pixel centers; edge boundaries midway between adjacent samples",
        "action": action,
        "action_threshold_sensitivity": circles,
        "capsule": {
            "edge_definition": "Strongest outer-outline to inner-material RGB transition; excludes outside shadow",
            "bounds_px": [left["boundary_px"], top, right["boundary_px"], bottom],
            "center_px": [(left["boundary_px"] + right["boundary_px"]) / 2, capsule_cy],
            "vertical_band_crosschecks": vertical,
            "horizontal_center_rows_exclusive_end": [center_row - 6, center_row + 7],
            "left": left, "right": right,
        },
        "capsule_minus_action_center_y_px": difference,
        "threshold_sensitivity_delta_range_px": [min(differences), max(differences)],
        "edge_definition_tolerance_px": 1.0,
        "conclusion": conclusion,
        "limitations": [
            "No UIKit runtime frames or R2 diagnostic branch were supplied",
            "Screenshot pixel scale is not assumed; no pixel value is used as an app layout offset",
            "This color/edge method is tailored to this screenshot, not arbitrary screenshots",
        ],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    report = measure(args.image)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("resolution_px", "capsule_minus_action_center_y_px", "conclusion")}, ensure_ascii=False))

"""Windows numerical/shader diagnostic, NOT an iOS screenshot or Metal build.

Uses a Python reference of the fluid equations and translates the production
Metal shader's arithmetic to GLSL. Swift, SwiftUI and Core Motion are not run.
pip install numpy moderngl glcontext pillow
python scripts/ios/render-water-diagnostic.py OUTPUT_DIRECTORY
"""
from pathlib import Path
import hashlib
import json
import re
import sys
import moderngl
import numpy as np
from PIL import Image, ImageDraw
from water_fluid_reference import Fluid, check_reference

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(sys.argv[1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)
metal_path = ROOT / "frontend/ios/App/App/Native/WaterScene.metal"
source = metal_path.read_text("utf8")
source = re.sub(r"#include[^\n]+|using namespace metal;|\[\[ stitchable \]\]", "", source)
source = source.replace("fast::", "").replace("static ", "").replace("fmod(", "mod(")
source = re.sub(r"device const float \*(\w+)", r"const float \1[64]", source)
for old, new in [("half4", "vec4"), ("half3", "vec3"), ("float4", "vec4"), ("float3", "vec3"), ("float2", "vec2")]:
    source = source.replace(old, new)
source = re.sub(r"(?<=\d)[hf]\b", "", source)
fragment = """#version 430
#define M_PI_F 3.141592653589793
uniform vec2 resolution;
uniform float clockTime, waterRipple, waterFill, darkMode;
uniform float waterDepths[64], waterVelocities[64], waterFoam[64];
out vec4 outColor;
""" + source + """
void main() {
    outColor = opengymWater(vec2(gl_FragCoord.x, resolution.y-gl_FragCoord.y), vec4(1), resolution,
                            clockTime, waterDepths, 64, waterVelocities, 64, waterFoam, 64,
                            waterRipple, waterFill, darkMode);
}
"""
vertex = """#version 430
void main() {
    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
"""
ctx = moderngl.create_standalone_context(require=430)
program = ctx.program(vertex_shader=vertex, fragment_shader=fragment)
vao = ctx.vertex_array(program, [])
size = (280, 600)
fbo = ctx.simple_framebuffer(size)
fbo.use()
program["resolution"].value = size


def render(fluid, phase, dark=0):
    program["clockTime"].value = phase
    program["waterRipple"].value = min(0.0018, max(0, min(fluid.depths.min(), 1-fluid.depths.max()) * 0.25))
    program["waterFill"].value = fluid.fill
    program["waterDepths"].value = tuple(float(x) for x in fluid.depths)
    program["waterVelocities"].value = tuple(float(x) for x in fluid.velocities)
    program["waterFoam"].value = tuple(float(x) for x in fluid.foam)
    program["darkMode"].value = dark
    vao.render(vertices=3)
    return Image.frombytes("RGB", size, fbo.read(components=3)).transpose(Image.Transpose.FLIP_TOP_BOTTOM)


fps = 24
fluid = Fluid(height=size[1] / size[0])
frames, captures = [], []
capture_indices = [0, 16, 23, 34, 44, 57, 77, 108]
max_volume_error = 0
for index in range(fps * 8):
    t = index / fps
    ax = 0.95 if 0.5 <= t < 0.8 else (-1.25 if 1.6 <= t < 1.9 else 0)
    gx = 0.25 if 1.2 <= t < 1.6 else (0.12 if 1.9 <= t < 3 else 0)
    fluid.advance(1 / fps, gx=gx, ax=ax)
    max_volume_error = max(max_volume_error, abs(fluid.depths.mean() - fluid.fill))
    picture = render(fluid, t)
    frame = Image.new("RGB", (size[0], size[1] + 54), "#172b35")
    frame.paste(picture, (0, 54))
    draw = ImageDraw.Draw(frame)
    draw.text((8, 5), "FLUID REFERENCE / NOT iOS", font_size=15, fill="white")
    event = "MOVE RIGHT" if ax > 0 else ("MOVE LEFT" if ax < 0 else ("HOLD TILT" if gx else "RELEASE / SETTLE"))
    draw.text((8, 28), f"{t:04.2f}s  {event}", font_size=15, fill="#9ee2ef")
    frames.append(frame)
    if index in capture_indices:
        captures.append(frame.copy())
sheet = Image.new("RGB", (size[0]*4, (size[1]+54)*2))
for index, picture in enumerate(captures):
    sheet.paste(picture, ((index % 4) * size[0], (index // 4) * (size[1]+54)))
sheet.save(OUT / "water-slosh-frames.png")
frames[0].save(OUT / "water-slosh-diagnostic.webp", save_all=True, append_images=frames[1:],
               duration=round(1000/fps), loop=0, quality=78, method=4)
difference = np.abs(np.asarray(frames[0]).astype(float) - np.asarray(frames[23]).astype(float))
assert difference.mean() > 1
# Retain the still diagnostic coverage for empty/full and appearance modes.
cases = [("0%", 0, 0, 0), ("25%", .25, 0, 0), ("50%", .5, 0, 0), ("75%", .75, 0, 0),
         ("100% / overflow", 1, 0, 0), ("Left wall impact", .5, 1, 0),
         ("Right wall impact", .5, -1, 0), ("50% / dark", .5, 0, 1)]
still = Image.new("RGB", (size[0]*4, (size[1]+40)*2), "#172b35")
draw = ImageDraw.Draw(still)
for index, (label, fill, impulse, dark) in enumerate(cases):
    sample = Fluid(fill, size[1]/size[0])
    if impulse:
        for _ in range(8):
            sample.advance(1/30, ax=impulse)
    x, y = index % 4 * size[0], index // 4 * (size[1]+40)
    draw.text((x+8, y+10), label + " / reference", font_size=15, fill="white")
    still.paste(render(sample, 2.7, dark), (x, y+40))
still.save(OUT / "water-shader-diagnostic.png")

result = {
    "scope": "Python fluid reference and production shader arithmetic translated to GLSL; NOT Swift execution, Metal compilation, native UI or device motion validation",
    "renderer": ctx.info["GL_RENDERER"], "opengl": ctx.info["GL_VERSION"],
    "frames": len(frames), "reference_fps": fps, "volume_error_during_trace": float(max_volume_error),
    "changed_pixel_mean": float(difference.mean()), "reference_checks": check_reference(),
    "swift_tests_executed": False, "metal_compiled": False, "swiftui_rendered": False, "device_motion_tested": False,
    "sha256": {str(p.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest()
               for p in [metal_path, ROOT/"frontend/ios/App/App/Native/WaterPhysics.swift",
                         Path(__file__), Path(__file__).with_name("water_fluid_reference.py")]}
}
(OUT / "shader-diagnostic.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf8")
print(json.dumps(result, indent=2))

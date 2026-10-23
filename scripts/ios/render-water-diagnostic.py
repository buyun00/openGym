"""Windows shader diagnostic, NOT an iOS screenshot or a Metal build.

pip install moderngl glcontext pillow
python scripts/ios/render-water-diagnostic.py OUTPUT_DIRECTORY

Compiles the production water shader's arithmetic through GLSL type aliases in an
offscreen OpenGL context. SwiftUI, native materials and Core Motion are not involved.
"""
from pathlib import Path
import json
import math
import re
import sys
import time
import moderngl
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(sys.argv[1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)
source = (ROOT / "frontend/ios/App/App/Native/WaterScene.metal").read_text("utf8")
source = re.sub(r"#include[^\n]+|using namespace metal;|\[\[ stitchable \]\]", "", source)
source = source.replace("fast::", "").replace("static ", "").replace("fmod(", "mod(")
for old, new in [("half4", "vec4"), ("half3", "vec3"), ("float4", "vec4"), ("float3", "vec3"), ("float2", "vec2")]:
    source = source.replace(old, new)
source = re.sub(r"(?<=\d)[hf]\b", "", source)
fragment = """#version 430
#define M_PI_F 3.141592653589793
uniform vec2 resolution;
uniform float clockTime, waterBase, waterSlope, waterSwell, waterRipple, darkMode;
out vec4 outColor;
""" + source + """
void main() {
    outColor = opengymWater(vec2(gl_FragCoord.x, resolution.y-gl_FragCoord.y), vec4(1), resolution,
                            clockTime, waterBase, waterSlope, waterSwell, waterRipple, darkMode);
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
size = (320, 680)
fbo = ctx.simple_framebuffer(size)
fbo.use()
program['resolution'].value = size
phase = 2.7
program['clockTime'].value = phase
program['waterRipple'].value = 0.0025
program['waterSwell'].value = 0.02

def base_for(fill, slope):
    offsets = [slope * (i/4096 - .5) + .02 * math.cos(math.pi*i/4096)
               + .0025 * math.sin(4*math.pi*i/4096 + phase*1.7)
               + .0025*.45 * math.cos(7*math.pi*i/4096 - phase*1.2) for i in range(4097)]
    low, high = -max(offsets)-1, 2-min(offsets)
    for _ in range(30):
        middle = (low+high)/2
        area = sum(min(1,max(0,1-middle-o)) for o in offsets)/len(offsets)
        if area > min(1, fill): low = middle
        else: high = middle
    return (low+high)/2

cases = [("0%",0,0,0),("25%",.25,0,0),("50%",.5,0,0),("75%",.75,0,0),
         ("100% / overflow",1,0,0),("50% / tilt left",.5,-.65,0),
         ("50% / tilt right",.5,.65,0),("50% / dark",.5,0,1)]
sheet = Image.new('RGB', (size[0]*4, (size[1]+46)*2+55), '#1b2830')
draw = ImageDraw.Draw(sheet)
draw.text((14,12), 'SHADER ARITHMETIC DIAGNOSTIC / Windows OpenGL / NOT iOS UI', fill='white', font_size=22)
for index, (label, fill, slope, dark) in enumerate(cases):
    program['waterBase'].value = base_for(fill, slope)
    program['waterSlope'].value = slope
    program['darkMode'].value = dark
    vao.render(vertices=3)
    img = Image.frombytes('RGB', size, fbo.read(components=3)).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    x, y = index%4*size[0], index//4*(size[1]+46)+55
    draw.text((x+12,y+10), label, fill='white', font_size=20)
    sheet.paste(img, (x,y+46))
sheet.save(OUT/'water-shader-diagnostic.png')
result = {'scope':'Production Metal shader arithmetic translated to GLSL; NOT Metal compilation or iOS UI/runtime validation',
          'renderer':ctx.info['GL_RENDERER'], 'opengl':ctx.info['GL_VERSION'], 'cases':[x[0] for x in cases],
          'metal_compiled':False,'swiftui_rendered':False,'device_motion_tested':False}
(OUT/'shader-diagnostic.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
print(json.dumps(result,indent=2))

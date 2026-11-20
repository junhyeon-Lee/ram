"""Ram 의 출근길 — 돌 이글루 마을에서 회사까지 일자 길

실행:  python build_commute.py <shot> <out> [samples=64] [width=1280]
  shot: export  게임용 모델로 내보낸다 (out = assets/environments/commute/commute.glb). Ram·조명·카메라는 빼고,
                돌마다 다른 색은 재질 여러 개로 나눠 담는다(절차적 재질은 glTF 로 못 나간다).
  shot: start   ① 집을 막 나섬. 카메라가 Ram 등 뒤에 가깝고 낮다. 회사는 멀리 작게.
        arrive  ② 회사 앞. 카메라가 위로 올라가며 줌 아웃 → 9층 건물 전체가 보인다.
좌표: Z 위. 길은 +Y 로 곧게 뻗는다(집 문 앞 y=7 → 회사 정문 y=TY). 달려서 10초쯤. Ram 은 +Y 를 보고 간다.
"""
import math
import os
import random
import sys

import bpy
import bmesh  # bpy 다음
from mathutils import Matrix, Vector

ARGS = sys.argv[1:]
SHOT, OUT = ARGS[0], ARGS[1]
SAMPLES = int(ARGS[2]) if len(ARGS) > 2 else 64
WIDTH = int(ARGS[3]) if len(ARGS) > 3 else 1280
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EXPORT = SHOT == "export"
random.seed(11)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
col = sc.collection
I3 = Matrix.Identity(3)
TY = 40.0                 # 회사 정문 쪽 면의 y (game/commute/commute.gd 의 TOWER_Y 와 같아야 한다)
PLAZA = 16.0              # 회사 앞 광장 길이
VY = TY - PLAZA           # 마을 돌길이 끝나는 곳


def srgb(c):
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def mat(name, color, rough=0.9, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(color), 1)
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*srgb(emit), 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


def tint_mat(name, colors, mottle=0.2, scale=1.4):
    """물체마다 색이 조금씩 다르고 면에 얼룩이 있는 재질. 내보낼 때는 색마다 단색 재질 하나씩(목록)으로 바꾼다."""
    if EXPORT:
        return [mat(f"{name}{i}", c) for i, c in enumerate(colors)]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.93
    info = nt.nodes.new("ShaderNodeObjectInfo")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, (*srgb(colors[0]), 1)
    els[1].position, els[1].color = 1.0, (*srgb(colors[-1]), 1)
    for i, c in enumerate(colors[1:-1], 1):
        els.new(i / (len(colors) - 1)).color = (*srgb(c), 1)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 2.5
    rng = nt.nodes.new("ShaderNodeMapRange")
    rng.inputs[1].default_value, rng.inputs[2].default_value = 0.32, 0.68
    rng.inputs[3].default_value, rng.inputs[4].default_value = 1.0 - mottle, 1.0 + mottle
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    nt.links.new(info.outputs["Random"], ramp.inputs[0])
    nt.links.new(noise.outputs[0], rng.inputs[0])
    nt.links.new(ramp.outputs[0], mix.inputs[6])
    nt.links.new(rng.outputs[0], mix.inputs[7])
    nt.links.new(mix.outputs[2], b.inputs["Base Color"])
    return m


def pick(m):
    return random.choice(m) if isinstance(m, list) else m


def block(mat_, loc, size, rot_z=0.0, bevel=0.03, jitter=0.0, basis=None):
    me = bpy.data.meshes.new("b")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if jitter:
            v.co += Vector((random.uniform(-jitter, jitter), random.uniform(-jitter, jitter), random.uniform(-jitter, jitter)))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect="EDGES")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("b", me)
    m4 = (basis if basis is not None else Matrix.Rotation(rot_z, 3, "Z")).to_4x4()
    m4.translation = Vector(loc)
    o.matrix_world = m4
    me.materials.append(pick(mat_))
    col.objects.link(o)
    return o


# ---------------------------------------------------------------- 재질
M_STONE = tint_mat("stone", [(0.40, 0.37, 0.34), (0.50, 0.46, 0.41), (0.58, 0.53, 0.46), (0.46, 0.44, 0.42), (0.54, 0.49, 0.43)])
STONE_FACES = [mat(f"sf{i}", c) for i, c in enumerate([(0.44, 0.41, 0.37), (0.52, 0.48, 0.42), (0.58, 0.53, 0.46), (0.48, 0.45, 0.42)])]
M_SLAB = tint_mat("slab", [(0.36, 0.33, 0.30), (0.44, 0.40, 0.35), (0.40, 0.37, 0.33), (0.47, 0.43, 0.38)], mottle=0.24)
M_MORTAR = tint_mat("mortar", [(0.27, 0.24, 0.21), (0.31, 0.28, 0.25)], mottle=0.1)
M_PAVE = tint_mat("pave", [(0.52, 0.53, 0.54), (0.58, 0.59, 0.60), (0.48, 0.49, 0.51)], mottle=0.12)
M_GRASS = tint_mat("grass", [(0.36, 0.44, 0.27), (0.42, 0.48, 0.30)], mottle=0.22, scale=0.25)
M_PLAZA = tint_mat("plaza", [(0.50, 0.51, 0.52), (0.54, 0.55, 0.56)], mottle=0.1, scale=0.4)
M_DARK = mat("dark", (0.02, 0.02, 0.025))
M_CONC = tint_mat("concrete", [(0.60, 0.62, 0.65), (0.66, 0.68, 0.70)], mottle=0.07, scale=0.5)
M_CONC2 = tint_mat("concrete2", [(0.50, 0.53, 0.58), (0.56, 0.58, 0.62)], mottle=0.07, scale=0.5)
M_GLASS = mat("glass", (0.16, 0.24, 0.32), 0.15, emit=(0.35, 0.55, 0.75), strength=0.25)
M_GLASS_LIT = mat("glass_lit", (0.9, 0.75, 0.45), 0.3, emit=(1.0, 0.78, 0.42), strength=2.2)
GLASSES = [M_GLASS, mat("glass2", (0.13, 0.20, 0.28), 0.15, emit=(0.30, 0.48, 0.68), strength=0.18),
           mat("glass3", (0.20, 0.29, 0.36), 0.15, emit=(0.42, 0.60, 0.78), strength=0.3)]
M_HR = mat("hr_floor", (1.0, 0.7, 0.2), 0.3, emit=(1.0, 0.62, 0.12), strength=4.5)
M_METAL = mat("metal", (0.22, 0.24, 0.27), 0.5)
M_TRUNK = mat("trunk", (0.30, 0.22, 0.16))
LEAVES = [mat(f"leaf{i}", c) for i, c in enumerate([(0.24, 0.38, 0.22), (0.30, 0.44, 0.24), (0.22, 0.34, 0.24)])]

# ---------------------------------------------------------------- 땅·길
bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 60, 0))
bpy.context.active_object.data.materials.append(pick(M_GRASS))
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 60, 0.01))
pl = bpy.context.active_object
pl.location = (0, TY + 12, 0.01)
pl.scale = (76, 56, 1)                                     # 회사 앞 광장
pl.data.materials.append(pick(M_PLAZA))

# 마을 길: 줄눈 위에 촘촘히 깐 돌판 (y -6 ~ VY), 회사 쪽은 넓은 보도블록 (y VY ~ TY)
block(M_MORTAR, (0, (VY - 6) / 2, 0.012), (3.7, VY + 6.2, 0.02), bevel=0.0)
GAP = 0.04
y = -6.0
while y < VY:
    rh = random.uniform(0.62, 0.82)
    x = -1.8
    while x < 1.8 - 0.3:
        tw = min(random.uniform(0.7, 1.3), 1.8 - x)
        block(M_SLAB, (x + tw / 2, y + rh / 2, 0.03), (tw - GAP, rh - GAP, 0.08), bevel=0.018, jitter=0.006)
        x += tw
    y += rh
block(M_MORTAR, (0, VY + PLAZA / 2, 0.014), (5.3, PLAZA, 0.02), bevel=0.0)
y = VY
while y < TY - 0.1:
    for i in range(4):
        block(M_PAVE, (-1.95 + i * 1.3, y + 0.65, 0.03), (1.3 - GAP, 1.3 - GAP, 0.08), bevel=0.015)
    y += 1.3

# 집 문 앞에서 길까지 샛길
for px_, py_, pr_ in [(-2.55, 7.15, 0.5), (-2.0, 7.7, 0.75), (-1.5, 8.3, 0.75)]:
    block(M_SLAB, (px_, py_, 0.03), (0.86, 0.66, 0.08), rot_z=pr_, bevel=0.018, jitter=0.006)

# 마을 길 양옆 경계석, 돌 등롱 (도시의 가로등과 짝)
yy = -6.0
while yy < VY:
    ln = random.uniform(1.0, 1.6)
    for s in (-1, 1):
        if s == -1 and 5.6 < yy + ln / 2 < 10.2:
            continue                                      # 집 문 앞: 길로 나오는 자리는 비운다
        block(M_STONE, (1.98 * s, yy + ln / 2, 0.07), (0.24, ln - 0.04, 0.17), bevel=0.03, jitter=0.01)
    yy += ln
M_LANT = mat("lantern", (1.0, 0.8, 0.5), 0.5, emit=(1.0, 0.72, 0.35), strength=2.5)
for i, yy in enumerate(range(12, int(VY) - 1, 8)):
    lx = 2.8 * (1 if i % 2 else -1)
    block(M_STONE, (lx, yy, 0.35), (0.40, 0.40, 0.70), bevel=0.04, jitter=0.01)
    block(M_STONE, (lx, yy, 0.78), (0.62, 0.62, 0.14), bevel=0.03, jitter=0.01)
    block(M_LANT, (lx, yy, 1.03), (0.34, 0.34, 0.36), bevel=0.02)
    block(M_STONE, (lx, yy, 1.29), (0.70, 0.70, 0.15), bevel=0.04, jitter=0.01)
    block(M_STONE, (lx, yy, 1.44), (0.30, 0.30, 0.16), bevel=0.04, jitter=0.01)

# 광장 바닥: 큰 타일 (가운데 보도는 비워 둔다)
M_TILE = tint_mat("tile", [(0.50, 0.51, 0.53), (0.56, 0.57, 0.58), (0.47, 0.48, 0.50)], mottle=0.1, scale=0.6)
block(mat("grout", (0.36, 0.37, 0.39)), (0, VY + PLAZA / 2, 0.012), (52.0, PLAZA, 0.02), bevel=0.0)
for i in range(-10, 10):
    for j in range(int(PLAZA // 2.8) + 1):
        tx, ty = i * 2.6 + 1.3, VY + j * 2.8 + 1.4
        if abs(tx) < 3.2:
            continue
        block(M_TILE, (tx, ty, 0.025), (2.6 - 0.06, 2.8 - 0.06, 0.07), bevel=0.012)


# ---------------------------------------------------------------- 돌 이글루 (바깥 모습)
def igloo(cx, cy, r, door_dir):
    """각진 돌 돔. 면마다 돌색을 달리해 틈 없이 쌓은 돌처럼 보이게 한다. door_dir: 문이 향하는 방향(라디안)."""
    me = bpy.data.meshes.new("igloo")
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=r)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z < -0.05 * r], context="FACES")
    for v in bm.verts:
        v.co *= 1.0 + random.uniform(-0.025, 0.025)
        v.co.z *= 0.92
    for f in bm.faces:
        f.material_index = random.randrange(len(STONE_FACES))
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("igloo", me)
    o.location = (cx, cy, 0)
    for m in STONE_FACES:
        me.materials.append(m)
    col.objects.link(o)
    d = Vector((math.cos(door_dir), math.sin(door_dir), 0))
    t = Vector((-d.y, d.x, 0))
    basis = Matrix((t, Vector((0, 0, 1)), d)).transposed()   # 열: 가로·위·바깥
    # 현관: 고르게 쌓은 아치 돌 9개 + 양쪽 기둥 돌 2단 + 아치 모양의 어두운 입구
    c = Vector((cx, cy, 0)) + d * (r * 0.90)
    ar, spring, depth = 0.30 * r, 0.26 * r, 0.42 * r
    ro = ar + 0.08 * r                                        # 아치 돌 가운데가 놓이는 반지름
    n_st = 9
    sw = math.pi * ro / n_st * 0.97
    for k in range(n_st):
        th = math.pi * (k + 0.5) / n_st
        block(M_STONE, c + t * ro * math.cos(th) + Vector((0, 0, spring + ro * math.sin(th))),
              (sw, 0.16 * r, depth), basis=basis @ Matrix.Rotation(th - math.pi / 2, 3, "Z"), bevel=0.03, jitter=0.008)
    for s in (-1, 1):
        for zz in (0.25, 0.75):
            block(M_STONE, c + t * ro * s + Vector((0, 0, spring * zz)), (0.16 * r, spring * 0.5 * 0.97, depth), basis=basis, bevel=0.03, jitter=0.008)
    pts = [(-ar, 0.0)] + [(ar * math.cos(a), spring + ar * math.sin(a)) for a in [math.pi * (1 - i / 12) for i in range(13)]] + [(ar, 0.0)]
    me2 = bpy.data.meshes.new("opening")
    bm2 = bmesh.new()
    o0 = c + d * (depth / 2 - 0.05)
    bm2.faces.new([bm2.verts.new(o0 + t * u + Vector((0, 0, v))) for u, v in pts])
    bm2.to_mesh(me2)
    bm2.free()
    op = bpy.data.objects.new("opening", me2)
    me2.materials.append(M_DARK)
    col.objects.link(op)


HOME = (-6.2, 7.0, 3.0)
igloo(*HOME, door_dir=0.0)                                    # Ram 의 집: 문이 길(+X) 쪽
for cx, cy, r, dd in [(7.0, 11.5, 2.5, math.pi), (-7.8, 18.0, 2.8, 0.0), (7.8, 23.5, 3.0, math.pi), (-6.8, 29.5, 2.4, 0.0),
                      (8.8, 34.5, 2.2, math.pi), (-14.5, 9.0, 2.6, 0.3), (15.5, 16.0, 2.9, 2.8), (-16.0, 24.0, 3.1, 0.2),
                      (16.5, 29.0, 2.4, 3.0), (-8.0, 40.0, 2.6, 0.0), (7.4, 45.0, 2.4, math.pi), (-7.2, 51.5, 2.2, 0.0),
                      (8.6, 56.0, 2.0, math.pi), (-15.0, 36.0, 2.8, 0.3), (16.0, 42.0, 2.6, 2.9), (-14.0, 48.0, 2.4, 0.2)]:
    if cy < VY - 1.5:
        igloo(cx, cy, r, dd)


# ---------------------------------------------------------------- 나무
def tree(x, y, h):
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.14 * h / 3, depth=h * 0.4, location=(x, y, h * 0.2))
    bpy.context.active_object.data.materials.append(M_TRUNK)
    for k, (zr, rr) in enumerate([(0.55, 0.42), (0.80, 0.30)]):
        bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=h * rr, radius2=0.0, depth=h * 0.55, location=(x, y, h * zr),
                                        rotation=(0, 0, random.uniform(0, 3.14)))
        bpy.context.active_object.data.materials.append(random.choice(LEAVES))


for x, y, h in [(-5.4, 14.0, 2.6), (5.6, 18.0, 3.0), (-5.6, 24.0, 2.6), (5.8, 29.5, 2.8), (-5.2, 35.0, 2.7), (11.5, 6.0, 4.2), (-11.0, 13.5, 4.0),
                (12.0, 21.5, 3.6), (-11.5, 30.5, 4.4), (20.0, 20.0, 4.6), (-20.0, 17.0, 4.2), (6.0, 3.0, 2.6), (-19.0, 32.0, 3.8), (21.0, 34.0, 4.0),
                (5.4, 40.0, 2.6), (-5.6, 46.0, 2.8), (5.6, 51.0, 2.5), (-5.4, 57.0, 2.6), (12.0, 49.0, 3.8), (-11.5, 55.0, 4.0), (13.0, 60.0, 3.4)]:
    if y < VY - 1.0:
        tree(x, y, h)

# ---------------------------------------------------------------- 회사 건물 (9층)
FH, NF = 2.0, 9                                            # 층 높이, 층 수
TW, TD = 16.0, 12.0
DY = TY - 60.0                                             # 도시 쪽 물건들의 y 옮김 (목록은 TY=60 기준으로 적혀 있다)
TOP = FH * NF + 0.6
block(M_CONC, (0, TY + TD / 2, TOP / 2), (TW, TD, TOP), bevel=0.08)
lit = {(1, 2), (2, 5), (4, 1), (5, 4), (6, 0), (3, 6)}        # 벌써 불 켜진 창
for f in range(NF):
    z = 0.5 + FH * f + FH * 0.52
    for i in range(7):
        x = -6.0 + i * 2.0
        if f == 0 and 2 <= i <= 4:
            continue                                         # 정문 자리
        m = M_HR if f == NF - 1 else (M_GLASS_LIT if (f, i) in lit else random.choice(GLASSES))
        block(m, (x, TY - 0.02, z), (1.55, 0.12, FH * 0.62), bevel=0.0)
        block(M_METAL, (x, TY - 0.10, z), (0.06, 0.06, FH * 0.62), bevel=0.0)                 # 창살
        block(M_CONC2, (x, TY - 0.16, z - FH * 0.33), (1.7, 0.22, 0.08), bevel=0.0)           # 창턱
    block(M_CONC2, (0, TY - 0.10, 0.5 + FH * f + 0.08), (TW + 0.1, 0.26, 0.2), bevel=0.0)   # 층 사이 띠
for i in range(8):                                           # 창 사이 세로 기둥: 창이 안으로 들어가 보이게
    block(M_CONC, (-7.0 + i * 2.0, TY - 0.17, TOP / 2), (0.36, 0.36, TOP), bevel=0.03)
# 정문 계단, 깃대, 벤치
block(M_CONC2, (0, TY - 2.6, 0.06), (8.0, 1.6, 0.12), bevel=0.02)
block(M_CONC2, (0, TY - 1.6, 0.14), (7.2, 1.6, 0.28), bevel=0.02)
for k, fc in enumerate([(1.0, 0.62, 0.12), (0.92, 0.92, 0.9), (0.2, 0.45, 0.75)]):
    fx = -9.0 - k * 1.3
    block(M_METAL, (fx, TY - 3.0, 3.2), (0.09, 0.09, 6.4), bevel=0.0)
    block(mat(f"flag{k}", fc, 0.7), (fx + 0.62, TY - 3.0, 5.9), (1.15, 0.04, 0.72), bevel=0.0)
for bx, by2 in [(9.5, TY - 13.0), (-9.5, TY - 7.0), (9.5, TY - 4.5)]:
    block(M_TRUNK, (bx, by2, 0.46), (0.5, 2.2, 0.1), bevel=0.02)
    for e in (-0.9, 0.9):
        block(M_METAL, (bx, by2 + e, 0.22), (0.4, 0.1, 0.44), bevel=0.0)
# 정문·차양·시계
block(mat("door_glass", (0.85, 0.8, 0.6), 0.2, emit=(1.0, 0.85, 0.55), strength=1.6), (0, TY - 0.03, 1.25), (4.6, 0.14, 2.3), bevel=0.0)
block(M_METAL, (0, TY - 0.05, 1.25), (0.08, 0.2, 2.3), bevel=0.0)
block(M_CONC2, (0, TY - 1.0, 2.62), (6.0, 2.2, 0.22), bevel=0.04)
for s in (-1, 1):
    block(M_METAL, (2.7 * s, TY - 1.9, 1.3), (0.14, 0.14, 2.6), bevel=0.0)
block(M_CONC2, (0, TY + TD / 2, TOP + 0.25), (TW + 0.4, TD + 0.4, 0.5), bevel=0.05)        # 옥상 난간
block(M_CONC2, (0, TY + 0.6, TOP + 2.0), (4.4, 0.9, 3.4), bevel=0.06)                      # 시계탑
CZ = TOP + 2.2
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=1.45, depth=0.16, location=(0, TY + 0.12, CZ), rotation=(math.radians(90), 0, 0))
bpy.context.active_object.data.materials.append(mat("clock_face", (0.97, 0.95, 0.88), 0.5, emit=(1.0, 0.95, 0.8), strength=0.9))
for ang, ln, wd in [(300.0, 1.15, 0.12), (265.0, 0.75, 0.16)]:          # 8:50 — 분침, 시침 (12시에서 시계 방향 각도)
    a = math.radians(ang)
    dx, dz = math.sin(a), math.cos(a)                                    # 정면(카메라)에서 본 방향
    o = block(M_DARK, (dx * ln / 2, TY + 0.0, CZ + dz * ln / 2), (wd, 0.06, ln), bevel=0.0)
    o.rotation_euler = (0, -a, 0)
for x, w, d, h in [(-5.0, 2.2, 2.0, 1.2), (4.5, 3.0, 2.4, 1.0), (6.5, 0.2, 0.2, 4.5)]:    # 옥상 설비·안테나
    block(M_METAL, (x, TY + TD - 3.0, TOP + 0.5 + h / 2), (w, d, h), bevel=0.03)

# 옆·뒤 건물 (도시 배경)
for x, yb, w, d, h, m in [(-17.5, 58.0, 11.0, 10.0, 9.5, M_CONC2), (18.0, 57.0, 12.0, 11.0, 12.5, M_CONC2), (-30.0, 66.0, 10.0, 12.0, 15.0, M_CONC),
                          (31.0, 68.0, 11.0, 12.0, 11.0, M_CONC), (-12.0, 80.0, 14.0, 10.0, 14.0, M_CONC2), (14.0, 84.0, 16.0, 10.0, 15.5, M_CONC2),
                          (-44.0, 74.0, 12.0, 12.0, 20.0, M_CONC2), (46.0, 78.0, 12.0, 12.0, 18.0, M_CONC2)]:
    yb += DY
    block(m, (x, yb + d / 2, h / 2), (w, d, h), bevel=0.06)
    nx, nz = max(2, int(w // 2.2)), max(2, int(h // 2.6))
    for a in range(nx):
        for b in range(nz):
            block(M_GLASS, (x - w / 2 + (a + 0.5) * w / nx, yb - 0.02, 1.4 + b * (h - 1.6) / nz), (w / nx * 0.62, 0.1, 1.3), bevel=0.0)

# 가로등·화단·버스 정류장
M_LAMP = mat("lamp", (1, 1, 0.9), 0.4, emit=(1.0, 0.95, 0.8), strength=0.6)
M_PLANTER = tint_mat("planter", [(0.46, 0.47, 0.49), (0.52, 0.53, 0.55)], mottle=0.08)
for yy in (TY - 12.5, TY - 6.0):
    for s in (-1, 1):
        block(M_METAL, (3.3 * s, yy, 1.6), (0.1, 0.1, 3.2), bevel=0.0)
        block(M_METAL, (2.95 * s, yy, 3.17), (0.7, 0.08, 0.08), bevel=0.0)
        block(M_LAMP, (2.7 * s, yy, 3.1), (0.34, 0.18, 0.08), bevel=0.0)
        block(M_PLANTER, (6.2 * s, yy + 3.0, 0.3), (2.4, 1.2, 0.6), bevel=0.04)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.75, location=(6.2 * s, yy + 3.0, 1.05))
        bpy.context.active_object.scale = (1.3, 0.8, 0.8)
        bpy.context.active_object.data.materials.append(random.choice(LEAVES))
BY = TY - 11.0
for px in (-8.6, -6.4):
    block(M_METAL, (px, BY, 1.2), (0.1, 0.1, 2.4), bevel=0.0)
block(M_CONC2, (-7.5, BY, 2.45), (2.8, 1.5, 0.12), bevel=0.02)
block(M_TRUNK, (-7.5, BY + 0.3, 0.45), (2.0, 0.4, 0.1), bevel=0.02)
block(M_METAL, (-5.9, BY - 1.4, 1.4), (0.08, 0.08, 2.8), bevel=0.0)
block(mat("sign", (0.2, 0.45, 0.75), 0.5), (-5.9, BY - 1.4, 2.6), (0.6, 0.06, 0.6), bevel=0.02)


# ---------------------------------------------------------------- 캐릭터
def place_glb(name, loc, rot_z, height):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(REPO, "assets", "characters", "helpers", name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    bpy.context.view_layer.update()
    zs = [(o.matrix_world @ Vector(c)).z for o in new if o.type == "MESH" for c in o.bound_box]
    s = height / max(max(zs) - min(zs), 1e-4)
    for o in roots:
        o.matrix_world = Matrix.Translation(Vector(loc)) @ Matrix.Rotation(rot_z, 4, "Z") @ Matrix.Scale(s, 4) @ Matrix.Translation(Vector((0, 0, -min(zs)))) @ o.matrix_world


RAM_Y = {"start": 9.6, "arrive": TY - 20.0}.get(SHOT, 9.6)
if not EXPORT:
    with bpy.data.libraries.load(os.path.join(REPO, "assets", "characters", "ram", "ram_rigged.blend")) as (src, dst):
        dst.objects = list(src.objects)
        dst.actions = list(src.actions)
    for o in dst.objects:
        col.objects.link(o)
    rig = bpy.data.objects["RamRig"]
    rig.location = (0.0, RAM_Y, 0.04)
    rig.rotation_euler = (0, 0, math.pi)                       # 모델 정면(-Y)을 +Y 로
    run = bpy.data.actions.get("Run-loop")
    if run and rig.animation_data:
        rig.animation_data.action = run
        try:
            rig.animation_data.action_slot = run.slots[0]
        except Exception:
            pass
        sc.frame_set(5)

# 출근하는 직원들 (조력자 모델): 길 위에서 회사 쪽으로
for name, loc, h in [("crane", (1.3, 15.0, 0.03), 1.9), ("sheep", (-1.1, 21.0, 0.03), 1.25), ("sheep", (1.0, TY - 6.0, 0.03), 1.25),
                     ("crane", (-1.5, TY - 3.5, 0.03), 1.9)]:
    place_glb(name, loc, math.pi, h)

# ---------------------------------------------------------------- 하늘·해
world = bpy.data.worlds.new("World")
sc.world = world
world.use_nodes = True
wn = world.node_tree
bg = wn.nodes["Background"]
tc = wn.nodes.new("ShaderNodeTexCoord")
sep = wn.nodes.new("ShaderNodeSeparateXYZ")
ramp = wn.nodes.new("ShaderNodeValToRGB")
els = ramp.color_ramp.elements
els[0].position, els[0].color = 0.0, (*srgb((0.98, 0.86, 0.70)), 1)     # 지평선: 아침 살구빛
els[1].position, els[1].color = 0.45, (*srgb((0.45, 0.68, 0.92)), 1)    # 위: 맑은 파랑
wn.links.new(tc.outputs["Generated"], sep.inputs[0])
wn.links.new(sep.outputs["Z"], ramp.inputs[0])
wn.links.new(ramp.outputs[0], bg.inputs["Color"])
bg.inputs["Strength"].default_value = 1.0
M_CLOUD = mat("cloud", (0.98, 0.96, 0.93), 1.0)
for cx_, cy_, cz_, s_ in [(-70, 200, 55, 1.2), (40, 230, 62, 1.5), (110, 190, 48, 1.0), (-130, 170, 44, 0.9), (-10, 260, 75, 1.8)]:
    for k in range(3):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=6.0 * s_, location=(cx_ + (k - 1) * 8.0 * s_, cy_, cz_ + (1.5 if k == 1 else 0)))
        cl = bpy.context.active_object
        cl.scale = (1.5, 0.8, 0.45)
        cl.data.materials.append(M_CLOUD)
if EXPORT:
    # 게임용: 메시를 한 덩어리로 합쳐(재질별 면) 그리기 횟수를 줄이고 GLB 로 내보낸다
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        wm = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = wm
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    env = bpy.context.active_object
    env.name = env.data.name = "Commute"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in [o for o in bpy.data.objects if o is not env]:
        bpy.data.objects.remove(o)
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    env.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(OUT), export_format="GLB", use_selection=True)
    tris = sum(len(p.vertices) - 2 for p in env.data.polygons)
    print(f"[commute] export -> {os.path.abspath(OUT)} (triangles {tris}, materials {len(env.data.materials)})")
    sys.exit(0)

sun = bpy.data.lights.new("sun", "SUN")
sun.energy = 4.2
sun.color = (1.0, 0.86, 0.68)
sun.angle = math.radians(2.5)
so = bpy.data.objects.new("sun", sun)
so.rotation_euler = Vector((-0.62, 0.58, -0.42)).to_track_quat("-Z", "Y").to_euler()      # 오른쪽 뒤에서 비추는 낮은 아침 해
col.objects.link(so)

# ---------------------------------------------------------------- 카메라·렌더
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
col.objects.link(cam)
sc.camera = cam
if SHOT == "start":      # 등 뒤 가깝고 낮게
    cam.data.lens = 24
    cam.location = (1.0, RAM_Y - 5.2, 2.3)
    target = Vector((-0.2, RAM_Y + 10.0, 1.3))
else:                    # 위로 올라가며 줌 아웃: 건물 전체
    cam.data.lens = 18
    cam.location = (0.0, RAM_Y - 13.0, 7.0)
    target = Vector((0.0, TY, 6.2))
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
cam.data.clip_end = 600

sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 5
sc.render.resolution_x = WIDTH
sc.render.resolution_y = WIDTH * 9 // 16
for vt in ("AgX", "Filmic", "Standard"):
    try:
        sc.view_settings.view_transform = vt
        break
    except TypeError:
        pass
for look in ("AgX - Medium High Contrast", "Medium High Contrast"):
    try:
        sc.view_settings.look = look
        break
    except TypeError:
        pass
sc.render.filepath = os.path.abspath(OUT)
bpy.ops.render.render(write_still=True)
print(f"[commute] {SHOT} -> {sc.render.filepath} ({SAMPLES} samples, {WIDTH}px)")

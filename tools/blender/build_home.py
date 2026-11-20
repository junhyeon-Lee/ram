"""Ram 의 집 — 돌 이글루 방

실행:  python build_home.py <mood> <out> [samples=64] [width=1280]
  mood: export  게임용 모델로 내보낸다 (out = assets/environments/home/home.glb). Ram·조명·안개·카메라는 뺀다.
  mood: stone (돌색이 그대로 보이는 아침빛)  ·  warm (따뜻한 햇살)  ·  cold (차가운 새벽)
좌표: Z 위, 카메라는 -Y 쪽에서 +Y(뒷벽)를 본다. Ram 정면은 -Y.
방은 반지름 R 의 반구에 돌 블록을 층층이 쌓아 만든다. 블록 사이 틈 뒤에는 줄눈 껍질을 대서
검은 구멍이 아니라 메움 돌로 보이게 한다. 바닥 판석도 줄눈 위에 촘촘히 깐다.
"""
import math
import os
import random
import sys

import bpy
import bmesh  # bpy 다음
from mathutils import Matrix, Vector

ARGS = sys.argv[1:]
MOOD, OUT = ARGS[0], ARGS[1]
SAMPLES = int(ARGS[2]) if len(ARGS) > 2 else 64
WIDTH = int(ARGS[3]) if len(ARGS) > 3 else 1280
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EXPORT = MOOD == "export"
R = 4.0
random.seed(7)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
col = sc.collection


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


def stone_mat(name, colors, mottle=0.24):
    """돌 재질 하나를 모든 돌이 같이 쓴다. 돌마다 색이 다르고(물체별 난수), 면에는 얼룩. 내보낼 때는 색마다 단색 재질(목록)."""
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
        e = els.new(i / (len(colors) - 1))
        e.color = (*srgb(c), 1)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.4
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


def block(mat_, loc, basis, size, bevel=0.035, jitter=0.02):
    """모서리를 깎은 각진 돌 하나. basis: 3×3 (열 = 가로·세로·두께 방향)."""
    me = bpy.data.meshes.new("stone")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        v.co += Vector((random.uniform(-jitter, jitter), random.uniform(-jitter, jitter), random.uniform(-jitter, jitter)))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect="EDGES")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("stone", me)
    m4 = basis.to_4x4()
    m4.translation = Vector(loc)
    o.matrix_world = m4
    me.materials.append(pick(mat_))
    col.objects.link(o)
    return o


def sph(az, el, r=R):
    a, e = math.radians(az), math.radians(el)
    return Vector((r * math.cos(e) * math.cos(a), r * math.cos(e) * math.sin(a), r * math.sin(e)))


def sph_basis(az, el):
    a, e = math.radians(az), math.radians(el)
    n = Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))
    t = Vector((-math.sin(a), math.cos(a), 0))
    return Matrix((t, n.cross(t), n)).transposed()


# ---------------------------------------------------------------- 재질 (돌색)
M_STONE = stone_mat("stone", [(0.40, 0.37, 0.34), (0.50, 0.46, 0.41), (0.58, 0.53, 0.46), (0.46, 0.44, 0.42), (0.54, 0.49, 0.43)])
M_FLOOR = stone_mat("floor", [(0.30, 0.28, 0.26), (0.38, 0.35, 0.31), (0.34, 0.31, 0.28), (0.42, 0.38, 0.33)], mottle=0.28)
M_MORTAR = stone_mat("mortar", [(0.27, 0.24, 0.21), (0.31, 0.28, 0.25)], mottle=0.1)
M_DARK = mat("dark", (0.015, 0.015, 0.02))

WIN_AZ, WIN_EL = 118.0, 34.0     # 둥근 창 (뒷벽 왼쪽 위)
DOOR_AZ = 40.0                   # 현관 굴 (오른쪽 뒤)
ARCH_R, ARCH_SPRING = 0.86, 0.62  # 아치 반지름, 아치가 시작되는 높이
win_dir = sph(WIN_AZ, WIN_EL, 1.0)
db = sph_basis(DOOR_AZ, 0.0)          # 열: 가로(t)·위(u)·바깥(n)


def door_dist(d):
    """방향 d 의 벽 위 점이 현관 아치 가운데에서 얼마나 떨어졌나 (m). 문 반대쪽이면 큰 값."""
    if d.dot(db.col[2]) < 0.3:
        return 99.0
    p = d * R
    x = p.dot(db.col[0])
    return abs(x) if p.z < ARCH_SPRING else math.hypot(x, p.z - ARCH_SPRING)


# ---------------------------------------------------------------- 줄눈 껍질: 블록 뒤를 받쳐 틈이 구멍으로 보이지 않게
me = bpy.data.meshes.new("shell")
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=96, v_segments=48, radius=R + 0.16)
kill = []
for f in bm.faces:
    c = f.calc_center_median().normalized()
    if c.z < -0.02 or math.degrees(c.angle(win_dir)) < 7.8 or door_dist(c) < ARCH_R - 0.1:
        kill.append(f)
bmesh.ops.delete(bm, geom=kill, context="FACES")
bm.to_mesh(me)
bm.free()
shell = bpy.data.objects.new("shell", me)
me.materials.append(pick(M_MORTAR))
col.objects.link(shell)

# ---------------------------------------------------------------- 돔: 층층이 쌓은 돌
DE = 11.0
for ring in range(8):
    el = DE * (ring + 0.5)
    n = max(5, round(2 * math.pi * R * math.cos(math.radians(el)) / 0.80))
    w = 2 * math.pi * R * math.cos(math.radians(el)) / n
    h = R * math.radians(DE)
    for k in range(n):
        az = 360.0 * (k + (0.5 if ring % 2 else 0.0)) / n
        d = sph(az, el, 1.0)
        if math.degrees(d.angle(win_dir)) < 10.5 or door_dist(d) < ARCH_R + 0.30:
            continue
        size = (w * random.uniform(0.95, 0.985), h * random.uniform(0.95, 0.985), random.uniform(0.40, 0.50))
        block(M_STONE, sph(az, el, R + size[2] * 0.5 - 0.1 + random.uniform(-0.025, 0.025)), sph_basis(az, el), size, bevel=0.04, jitter=0.015)
block(M_STONE, (0, 0, R + 0.12), Matrix.Identity(3), (0.95, 0.95, 0.42))

# 창 테두리 돌 10개 (빛에 묻히지 않게 방 안쪽으로 조금 내민다)
for k in range(10):
    th = 2 * math.pi * k / 10
    b = sph_basis(WIN_AZ, WIN_EL)
    c = sph(WIN_AZ, WIN_EL, R - 0.16) + b.col[0] * 0.66 * math.cos(th) + b.col[1] * 0.66 * math.sin(th)
    block(M_STONE, c, b @ Matrix.Rotation(th, 3, "Z"), (0.34, 0.44, 0.46), bevel=0.04)

# 현관: 아치 돌 + 기둥 돌 + 굴
dc = sph(DOOR_AZ, 0.0, R - 0.06)
for k in range(9):
    th = math.pi * k / 8
    c = dc + db.col[0] * ARCH_R * math.cos(th) + db.col[1] * (ARCH_SPRING + ARCH_R * math.sin(th))
    block(M_STONE, c, db @ Matrix.Rotation(th - math.pi / 2, 3, "Z"), (0.345, 0.32, 0.56), bevel=0.035)
for s in (-1, 1):
    for zz in (0.16, 0.47):
        block(M_STONE, dc + db.col[0] * ARCH_R * s + db.col[1] * zz, db, (0.32, 0.30, 0.56), bevel=0.035)
for i in range(1, 4):                                    # 굴 안쪽 벽
    for k in range(7):
        th = math.pi * k / 6
        c = dc + db.col[2] * (0.5 * i) + db.col[0] * (ARCH_R - 0.05) * math.cos(th) + db.col[1] * (ARCH_SPRING + (ARCH_R - 0.05) * math.sin(th))
        block(M_MORTAR, c, db @ Matrix.Rotation(th - math.pi / 2, 3, "Z"), (0.46, 0.30, 0.5), bevel=0.03)
    for s in (-1, 1):
        block(M_MORTAR, dc + db.col[2] * (0.5 * i) + db.col[0] * (ARCH_R - 0.05) * s + db.col[1] * 0.31, db, (0.3, 0.62, 0.5), bevel=0.03)
block(M_DARK, dc + db.col[2] * 2.1 + db.col[1] * 0.8, db, (2.4, 2.4, 0.1), bevel=0.0, jitter=0.0)

# ---------------------------------------------------------------- 바닥: 줄눈 위에 촘촘히 깐 판석
bpy.ops.mesh.primitive_plane_add(size=14, location=(0, 0, 0.012))
bpy.context.active_object.data.materials.append(pick(M_MORTAR))
GAP = 0.035
y = -(R + 0.4)
while y < R + 0.4:
    rh = random.uniform(0.56, 0.72)
    x = -(R + 0.6) + random.uniform(0.0, 0.5)
    while x < R + 0.4:
        tw = random.uniform(0.58, 1.08)
        cx, cy = x + tw / 2, y + rh / 2
        if math.hypot(cx, cy) < R + 0.35:
            block(M_FLOOR, (cx, cy, 0.0), Matrix.Identity(3), (tw - GAP, rh - GAP, 0.08 + random.uniform(-0.006, 0.006)), bevel=0.018, jitter=0.006)
        x += tw
    y += rh

# ---------------------------------------------------------------- 알: Ram 이 통째로 들어가 자는 큰 알
# 아래쪽 껍질(EggBase)은 깨진 뒤에도 남는 잠자리, 위쪽은 조각(Shard_00…)으로 나뉜다. 게임은 시작할 때 조각을 날려 알을 깬다.
# 내보낼 때는 알만 따로 egg.glb 로 (알 바닥 가운데가 원점), 방석은 방 모델에 남는다.
EGG_C = Vector((-1.5, 1.1, 0.0))      # game/commute/commute.gd 의 EGG_POS 와 같아야 한다 (거기서는 (x, 0, -y))
EGG_H, EGG_R, EGG_LIFT = 2.6, 0.98, 0.10                 # 높이, 가장 굵은 곳의 반지름, 방석에 묻힌 바닥 높이
CRACK_Z, CRACK_AMP, CRACK_TEETH = 1.05, 0.17, 7          # 깨지는 높이, 톱니 깊이, 톱니 수
M_CUSHION = mat("cushion", (0.44, 0.47, 0.54), 0.95)
for rad, depth, zz in [(1.36, 0.14, 0.09), (1.16, 0.10, 0.19)]:
    bpy.ops.mesh.primitive_cylinder_add(vertices=22, radius=rad, depth=depth, location=EGG_C + Vector((0, 0, zz)))
    bpy.context.active_object.data.materials.append(M_CUSHION)


def egg_point(az, h):
    """알 겉면에서 방위 az(도)·높이 h 인 점 (알 좌표)."""
    zu = (h - EGG_LIFT) * 2.0 / EGG_H - 1.0
    r = math.sqrt(max(0.0, 1.0 - zu * zu)) * EGG_R * (1.0 - 0.17 * zu)
    return Vector((r * math.cos(math.radians(az)), r * math.sin(math.radians(az)), h))


bm = bmesh.new()
bmesh.ops.create_icosphere(bm, subdivisions=4, radius=1.0)
for v in bm.verts:                                       # 알 모양: 위가 조금 좁다
    k = EGG_R * (1.0 - 0.17 * v.co.z)
    v.co = Vector((v.co.x * k, v.co.y * k, EGG_LIFT + (v.co.z + 1.0) * EGG_H / 2))
seeds = [egg_point(0, EGG_H + EGG_LIFT - 0.05)]          # 조각의 씨앗: 꼭대기 뚜껑 하나 + 옆으로 큼직하게 다섯 (적고 커야 귀엽다)
seeds += [egg_point(20 + 72 * i + random.uniform(-12, 12), 1.70 + random.uniform(-0.12, 0.12)) for i in range(5)]
pieces = {}
for f in bm.faces:
    c = f.calc_center_median()
    u = math.atan2(c.y, c.x) / (2 * math.pi) * CRACK_TEETH
    tooth = 4.0 * abs(u - math.floor(u + 0.5)) - 1.0     # -1 ~ 1 톱니
    key = -1 if c.z < CRACK_Z + CRACK_AMP * tooth else min(range(len(seeds)), key=lambda i: (seeds[i] - c).length)
    pieces.setdefault(key, []).append(f)
M_EGG = mat("egg", (0.93, 0.91, 0.86), 0.8)
egg_objs = []
for key in sorted(pieces):
    idx, verts, polys = {}, [], []
    for f in pieces[key]:
        poly = []
        for v in f.verts:
            if v.index not in idx:
                idx[v.index] = len(verts)
                verts.append(v.co.copy())
            poly.append(idx[v.index])
        polys.append(poly)
    center = Vector((0, 0, 0)) if key < 0 else sum(verts, Vector((0, 0, 0))) / len(verts)   # 조각은 제 가운데를 중심으로 돈다
    me = bpy.data.meshes.new("egg")
    me.from_pydata([v - center for v in verts], [], polys)
    me.update()
    me.materials.append(M_EGG)
    o = bpy.data.objects.new("EggBase" if key < 0 else f"Shard_{key:02d}", me)
    o.location = center
    col.objects.link(o)
    sol = o.modifiers.new("Solidify", "SOLIDIFY")
    sol.thickness, sol.offset = 0.07, -1.0
    egg_objs.append(o)
bm.free()
bpy.ops.object.select_all(action="DESELECT")
for o in egg_objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = egg_objs[0]
bpy.ops.object.convert(target="MESH")                    # 두께를 굽는다
for o in egg_objs:                                       # 겉·안은 매끈하게, 깨진 단면만 각지게
    for p in o.data.polygons:
        c = o.location + p.center
        radial = Vector((c.x, c.y, (c.z - 1.2) * 0.55)).normalized()
        p.use_smooth = abs(p.normal.dot(radial)) > 0.55
if EXPORT:
    egg_out = os.path.join(os.path.dirname(os.path.abspath(OUT)), "egg.glb")
    bpy.ops.export_scene.gltf(filepath=egg_out, export_format="GLB", use_selection=True)
    print(f"[home] export -> {egg_out} (pieces {len(egg_objs)})")
    for o in egg_objs:
        bpy.data.objects.remove(o, do_unlink=True)
else:                                                    # 그림: 이미 깨고 나온 뒤. 아래 껍질은 제자리, 조각은 방 가운데 쪽 바닥에
    to_mid = math.atan2(-EGG_C.y, -EGG_C.x)
    for o in egg_objs:
        if o.name == "EggBase":
            o.location = EGG_C
            continue
        n = Vector((o.location.x, o.location.y, 0.3)).normalized()
        a, d = to_mid + random.uniform(-1.7, 1.7), random.uniform(1.6, 2.4)
        o.rotation_euler = n.rotation_difference(Vector((0, 0, random.choice((-1, 1))))).to_euler()
        o.location = EGG_C + Vector((math.cos(a) * d, math.sin(a) * d, 0.12))

# ---------------------------------------------------------------- 자명종: 몸통 + 밝은 문자판 + 바늘 + 종 두 개 + 다리
clock_c = Vector((-1.0, -0.6, 0.0))
face_n = Vector((0.35, -1.0, 0.45)).normalized()         # 문자판이 카메라 쪽 위를 본다
crot = Vector((0, 0, 1)).rotation_difference(face_n).to_euler()
GLOW = {"cold": 7.0, "stone": 2.5}.get(MOOD, 1.2)
cc = clock_c + Vector((0, 0, 0.20))
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.15, depth=0.10, location=cc, rotation=crot)
bpy.context.active_object.data.materials.append(mat("clock_body", (0.62, 0.16, 0.12), 0.5))
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.118, depth=0.012, location=cc + face_n * 0.052, rotation=crot)
bpy.context.active_object.data.materials.append(mat("clock_face", (0.98, 0.9, 0.7), 0.6, emit=(1.0, 0.72, 0.35), strength=GLOW))
side = face_n.cross(Vector((0, 0, 1))).normalized()
up = side.cross(face_n).normalized()
hand_m = mat("hand", (0.05, 0.05, 0.06))
hb3 = Matrix((side, up, face_n)).transposed()
block(hand_m, cc + face_n * 0.062 + up * 0.04, hb3, (0.014, 0.085, 0.006), bevel=0.0, jitter=0.0)
block(hand_m, cc + face_n * 0.062 + side * 0.028, hb3, (0.06, 0.014, 0.006), bevel=0.0, jitter=0.0)
for s in (-1, 1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.05, location=cc + up * 0.17 + side * 0.09 * s)
    bpy.context.active_object.data.materials.append(mat("bell", (0.80, 0.62, 0.25), 0.35))
    block(hand_m, clock_c + Vector((0, 0, 0.05)) + side * 0.08 * s, Matrix.Identity(3), (0.025, 0.025, 0.1), bevel=0.0, jitter=0.0)

# ---------------------------------------------------------------- 문 옆 고리: 넥타이·사원증
hb = sph_basis(DOOR_AZ - 24, 20)
hc = sph(DOOR_AZ - 24, 20, R - 0.42)
block(mat("hook", (0.25, 0.2, 0.15)), hc, hb, (0.5, 0.05, 0.06), bevel=0.01, jitter=0.0)
block(mat("tie", (0.55, 0.12, 0.12), 0.7), hc + Vector((0, 0, -0.34)) - hb.col[0] * 0.12, hb, (0.09, 0.56, 0.015), bevel=0.004, jitter=0.0)
block(mat("tie_knot", (0.48, 0.10, 0.10), 0.7), hc + Vector((0, 0, -0.06)) - hb.col[0] * 0.12, hb, (0.11, 0.08, 0.03), bevel=0.01, jitter=0.0)
block(mat("badge", (0.92, 0.92, 0.88), 0.6), hc + Vector((0, 0, -0.30)) + hb.col[0] * 0.14, hb, (0.13, 0.18, 0.012), bevel=0.004, jitter=0.0)
block(mat("strap", (0.12, 0.3, 0.5), 0.7), hc + Vector((0, 0, -0.12)) + hb.col[0] * 0.14, hb, (0.02, 0.22, 0.008), bevel=0.002, jitter=0.0)

# ---------------------------------------------------------------- Ram (저장소의 실제 모델)
if not EXPORT:
    with bpy.data.libraries.load(os.path.join(REPO, "assets", "characters", "ram", "dino.blend")) as (src, dst):
        dst.objects = [n for n in src.objects if n == "Dino"]
    ram = dst.objects[0]
    col.objects.link(ram)
    ram.location = (0.75, 0.95, 0.04)
    ram.rotation_euler = (0, 0, math.radians(28))

if EXPORT:
    # 게임용: 수정자를 굽고 메시를 한 덩어리로 합쳐 GLB 로 내보낸다
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    room = bpy.context.active_object
    room.name = room.data.name = "Home"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(OUT), export_format="GLB", use_selection=True)
    tris = sum(len(p.vertices) - 2 for p in room.data.polygons)
    print(f"[home] export -> {os.path.abspath(OUT)} (triangles {tris}, materials {len(room.data.materials)})")
    sys.exit(0)

# ---------------------------------------------------------------- 조명
world = bpy.data.worlds.new("World")
sc.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
LOOK = {
    "stone": dict(world=(0.12, 0.16, 0.24), wstr=1.0, win=(1.0, 0.89, 0.72), wpow=950, sky=(0.80, 0.88, 1.0), skystr=1.6,
                  lamp=(1.0, 0.55, 0.2), lpow=16, door=(0.55, 0.70, 0.95), dpow=60, exposure=0.2, fog=0.012, fpow=110),
    "warm": dict(world=(0.16, 0.10, 0.06), wstr=0.12, win=(1.0, 0.76, 0.42), wpow=2000, sky=(1.0, 0.85, 0.6), skystr=1.8,
                 lamp=(1.0, 0.6, 0.25), lpow=5, door=(1.0, 0.8, 0.55), dpow=30, exposure=-0.2, fog=0.016),
    "cold": dict(world=(0.03, 0.06, 0.10), wstr=0.12, win=(0.5, 0.75, 1.0), wpow=1300, sky=(0.4, 0.68, 1.0), skystr=1.4,
                 lamp=(1.0, 0.5, 0.15), lpow=34, door=(0.3, 0.5, 0.8), dpow=16, exposure=-0.1, fog=0.014),
}[MOOD]
bg.inputs["Color"].default_value = (*LOOK["world"], 1)
bg.inputs["Strength"].default_value = LOOK["wstr"]

# 창: 밖의 하늘 판 + 안으로 좁게 드는 빛 (알 이불과 Ram 사이 바닥을 향한다)
wb = sph_basis(WIN_AZ, WIN_EL)
block(mat("sky", (0, 0, 0), emit=LOOK["sky"], strength=LOOK["skystr"]), sph(WIN_AZ, WIN_EL, R + 0.9), wb, (2.6, 2.6, 0.05), bevel=0.0, jitter=0.0)
ld = bpy.data.lights.new("window", "AREA")
ld.shape = "DISK"
ld.size = 0.75
ld.spread = math.radians(30)
ld.energy = LOOK["wpow"]
ld.color = LOOK["win"]
lo = bpy.data.objects.new("window", ld)
lo.location = sph(WIN_AZ, WIN_EL, R + 0.45)
lo.rotation_euler = (Vector((-0.55, 0.35, 0.0)) - lo.location).to_track_quat("-Z", "Y").to_euler()
col.objects.link(lo)

for name, loc, color, power, radius in [("lamp", cc + face_n * 0.25, LOOK["lamp"], LOOK["lpow"], 0.06),
                                        ("door", dc + db.col[2] * 1.3 + Vector((0, 0, 0.8)), LOOK["door"], LOOK["dpow"], 0.3)]:
    d = bpy.data.lights.new(name, "POINT")
    d.energy, d.color, d.shadow_soft_size = power, color, radius
    o = bpy.data.objects.new(name, d)
    o.location = loc
    col.objects.link(o)

# 보조광: 닫힌 돔 안에는 바깥빛이 못 들어와 그늘이 새까매진다. 차가운 색으로 은은하게 채운다
fd = bpy.data.lights.new("fill", "POINT")
fd.energy = LOOK.get("fpow", 40)
fd.color = LOOK.get("fill", (0.55, 0.68, 0.95))
fd.shadow_soft_size = 1.4
fo2 = bpy.data.objects.new("fill", fd)
fo2.location = (0.4, -1.3, 3.0)
col.objects.link(fo2)

# 옅은 안개: 창으로 드는 빛이 줄기로 보이게
bpy.ops.mesh.primitive_cube_add(size=2 * R + 3, location=(0, 0, R / 2))
fog = bpy.context.active_object
fm = bpy.data.materials.new("fog")
fm.use_nodes = True
fm.node_tree.nodes.clear()
fo = fm.node_tree.nodes.new("ShaderNodeOutputMaterial")
fv = fm.node_tree.nodes.new("ShaderNodeVolumePrincipled")
fv.inputs["Density"].default_value = LOOK["fog"]
fv.inputs["Anisotropy"].default_value = 0.45
fm.node_tree.links.new(fv.outputs[0], fo.inputs["Volume"])
fog.data.materials.append(fm)

# ---------------------------------------------------------------- 카메라·렌더
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
col.objects.link(cam)
sc.camera = cam
cam.data.lens = 18
cam.location = (0.3, -3.05, 2.25)
cam.rotation_euler = (Vector((-0.25, 1.3, 0.75)) - cam.location).to_track_quat("-Z", "Y").to_euler()

sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 6
sc.cycles.volume_bounces = 0
sc.cycles.caustics_reflective = False
sc.cycles.caustics_refractive = False
sc.render.resolution_x = WIDTH
sc.render.resolution_y = WIDTH * 9 // 16
sc.view_settings.exposure = LOOK["exposure"]
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
print(f"[home] {MOOD} -> {sc.render.filepath} ({SAMPLES} samples, {WIDTH}px)")

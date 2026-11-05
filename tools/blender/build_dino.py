"""박치기 공룡 주인공 — 로우폴리 모델 (v2)

실행:  python build_dino.py [출력폴더]
  - 출력폴더/dino.blend, dino.glb, render_*.png 를 만든다.

좌표: Blender 기준 Z 위, 캐릭터 정면은 -Y. 단위는 미터(키 약 1.35m).
만드는 법: 몸통·목·머리·돌머리·꼬리·다리를 타원체로 겹쳐 놓고 복셀 리메시로
한 덩어리로 녹인 뒤 면 수를 줄여(Decimate) 각진 로우폴리 느낌을 낸다.
돌머리는 몸과 한 덩어리이고 색(재질)으로만 구분한다.
눈(반달 동심원)·돌머리 돌기·발톱은 따로 만든 조각이며, 눈과 혹은 몸 겉면을 레이캐스트해 붙인다.

색: 바탕은 회색·검정. "accent" 슬롯(등 줄무늬·혹)은 빌드에 따라 게임에서 바꿀 색이다.
"""
import math
import os
import sys

import bpy
import bmesh  # bpy 다음에 불러와야 한다
from mathutils import Matrix, Vector

OUT = os.path.abspath(sys.argv[-1]) if len(sys.argv) > 1 and not sys.argv[-1].endswith(".py") else os.path.abspath("out")
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- 색 (sRGB)
PALETTE = {
    "body":   (0.22, 0.22, 0.24),   # 차콜
    "accent": (0.40, 0.40, 0.43),   # 빌드 색 자리(기본은 밝은 회색)
    "belly":  (0.52, 0.52, 0.54),   # 밝은 회색 배
    "dome":   (0.68, 0.67, 0.64),   # 돌 같은 회백
    "claw":   (0.85, 0.83, 0.78),
    "sclera": (1.00, 1.00, 1.00),
    "iris":   (1.00, 0.70, 0.12),   # 호박색
    "pupil":  (0.02, 0.02, 0.02),
    "lid":    (0.05, 0.05, 0.06),   # 눈 테두리
}

# 머리 배율: 머리·주둥이·돌머리·눈·입선·돌기를 목 끝(HEAD_PIVOT) 기준으로 함께 키운다
HEAD_PIVOT = Vector((0, -0.44, 0.97))
HEAD_SCALE = 1.3


def H(p):
    """머리 쪽 좌표: 목 끝 기준으로 HEAD_SCALE 만큼 키운 위치."""
    return tuple(HEAD_PIVOT + (Vector(p) - HEAD_PIVOT) * HEAD_SCALE)


def HS(v):
    """머리 쪽 크기(반지름·길이)."""
    return tuple(x * HEAD_SCALE for x in v) if isinstance(v, (tuple, list)) else v * HEAD_SCALE


# 다리 좌우 간격 (발은 이보다 12% 바깥)
LEG_X = 0.20

# 돌머리 타원체 (몸과 함께 리메시된다)
# 가장 넓은 높이(적도)를 테두리 높이 아래에 둔다: 테두리부터 위로 갈수록 좁아지기만 해서
# 위로 넓어졌다 좁아지는 버섯 모양이 생기지 않는다. 꼭대기 높이는 그대로(1.26).
DOME_C = Vector(H((0, -0.64, 1.02)))
# 머리보다 좁고 짧게: 모자처럼 얹히지 않고 정수리가 솟은 모양
DOME_R = Vector(HS((0.18, 0.24, 0.24)))


def srgb_to_linear(c):
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def make_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    col = srgb_to_linear(PALETTE[name])
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.35 if name in ("sclera", "iris", "pupil") else 0.85
    m.diffuse_color = (*col, 1.0)
    return m


# ---------------------------------------------------------------- 몸 (타원체 → 리메시)
def blob(co, semi, store):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=14, radius=1.0, location=co)
    o = bpy.context.active_object
    o.scale = semi
    store.append(o)


def chain(pts, semis, store, steps=6):
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i]), Vector(pts[i + 1])
        sa, sb = Vector(semis[i]), Vector(semis[i + 1])
        for k in range(steps):
            t = k / steps
            blob(tuple(a.lerp(b, t)), tuple(sa.lerp(sb, t)), store)
    blob(pts[-1], semis[-1], store)


def build_body():
    s = []
    blob((0, 0.00, 0.78), (0.26, 0.38, 0.28), s)   # 몸통
    blob((0, -0.05, 0.68), (0.23, 0.28, 0.22), s)  # 배
    blob((0, 0.28, 0.82), (0.23, 0.25, 0.24), s)   # 엉덩이
    chain([(0, -0.26, 0.88), (0, -0.44, 0.97)], [(0.17, 0.17, 0.18), (0.19, 0.17, 0.20)], s)  # 목 (큰 머리를 받치게 굵게)
    blob(H((0, -0.62, 1.00)), HS((0.20, 0.23, 0.19)), s)  # 머리
    # 주둥이: 넓은 뿌리 + 좁은 코끝 → 앞으로 갈수록 가늘어지는 뭉툭한 코
    blob(H((0, -0.76, 0.93)), HS((0.14, 0.09, 0.10)), s)  # 주둥이 뿌리
    blob(H((0, -0.84, 0.90)), HS((0.09, 0.06, 0.07)), s)  # 코끝
    blob(tuple(DOME_C), tuple(DOME_R), s)          # 돌머리 (머리와 한 덩어리)
    # 꼬리: 뿌리를 굵게, 길이는 짧게 → 듬직한 하체와 무게를 맞춘다
    chain([(0, 0.45, 0.86), (0, 0.74, 0.90), (0, 1.01, 0.87), (0, 1.26, 0.81)],
          [(0.19, 0.19, 0.18), (0.13, 0.13, 0.12), (0.075, 0.075, 0.075), (0.03, 0.035, 0.03)], s)
    for side in (-1, 1):
        # 듬직한 다리: 기둥처럼 곧고 굵게, 넓은 발을 무게중심(큰 머리 쪽) 아래에, 양발 간격 넓게
        x = LEG_X * side
        blob((x, 0.10, 0.60), (0.16, 0.22, 0.27), s)  # 허벅지
        chain([(x, 0.13, 0.45), (x * 1.08, 0.19, 0.28), (x * 1.12, 0.06, 0.10)],
              [(0.12, 0.12, 0.12), (0.09, 0.09, 0.09), (0.058, 0.058, 0.058)], s)  # 종아리 → 가는 발목
        blob((x * 1.12, -0.05, 0.05), (0.10, 0.16, 0.05), s)  # 발 (넓고 길게)
        # 팔: 짧지만 굵게(약 1.4배), 끝에 주먹 같은 손
        chain([(0.19 * side, -0.24, 0.72), (0.235 * side, -0.33, 0.58), (0.225 * side, -0.42, 0.52)],
              [(0.063, 0.063, 0.063), (0.046, 0.046, 0.046), (0.04, 0.04, 0.04)], s)
        blob((0.225 * side, -0.45, 0.50), (0.048, 0.042, 0.038), s)  # 손

    bpy.ops.object.select_all(action="DESELECT")
    for o in s:
        o.select_set(True)
    bpy.context.view_layer.objects.active = s[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = "Body"
    # 기준점을 원점으로: 색칠·레이캐스트가 월드 좌표와 같아야 한다
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    rm = body.modifiers.new("Remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.012
    sm = body.modifiers.new("Smooth", "SMOOTH")
    sm.factor = 0.6
    sm.iterations = 6
    for m in list(body.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return body


def to_lowpoly(obj, target_tris):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    cur = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = min(1.0, target_tris / cur)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in obj.data.polygons:
        p.use_smooth = False
    obj.select_set(False)
    return obj


# ---------------------------------------------------------------- 색 칠하기
SLOTS = ["body", "accent", "belly", "dome"]


def dome_dist(c):
    d = c - DOME_C
    return (d.x / DOME_R.x) ** 2 + (d.y / DOME_R.y) ** 2 + (d.z / DOME_R.z) ** 2


def dome_rim_z(y):
    # 돌머리 테두리 높이: 앞(이마)은 눈 바로 위까지 내려오고 뒤는 조금 높다
    return H((0, 0, 1.035))[2] + (y - DOME_C.y) * 0.18  # 기존 테두리 높이 그대로


def paint_body(body, mats):
    for n in SLOTS:
        body.data.materials.append(mats[n])
    for p in body.data.polygons:
        c, n = p.center, p.normal
        idx = 0
        # 돌머리 겉면에 가까운 면만 (주둥이 윗면까지 번지지 않게)
        if dome_dist(c) < 1.15 and c.z > dome_rim_z(c.y):
            idx = 3
        elif n.z < -0.3 and -1.2 < c.y < 0.45 and c.z > 0.35:
            idx = 2
        elif n.z > 0.45 and -0.30 < c.y < 1.15 and c.z > 0.75:
            # 등 줄무늬: 굵은 띠 몇 개 (빌드 색)
            if (c.y + 0.30) % 0.30 < 0.11:
                idx = 1
        p.material_index = idx


# ---------------------------------------------------------------- 조각 만들기 도우미
def ellipsoid(name, semi, subdiv=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=1.0, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.scale = semi
    bpy.ops.object.transform_apply(scale=True)
    return o


def cone(name, loc, radius, depth, direction, verts=5):
    d = Vector(direction).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(d).to_euler()
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=0.0, depth=depth,
                                    location=Vector(loc) + d * depth * 0.5, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    return o


def stroke(name, a, b, normal, width):
    """겉면 위 두 점을 잇는 가는 선 조각 (납작한 타원체)."""
    seg = b - a
    o = ellipsoid(name, (seg.length / 2 + width * 0.6, width, width * 0.8), subdiv=1)
    xa = seg.normalized()
    za = (normal - xa * normal.dot(xa)).normalized()
    ya = za.cross(xa)
    m = Matrix((xa, ya, za)).transposed().to_4x4()
    m.translation = (a + b) / 2 + za * 0.002
    o.matrix_world = m
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def surface_hit(body, origin, toward):
    origin = Vector(origin)
    ok, loc, nrm, _ = body.ray_cast(origin, (Vector(toward) - origin).normalized())
    if not ok:
        raise RuntimeError(f"ray missed body from {tuple(origin)}")
    return loc, nrm.normalized()


# ---------------------------------------------------------------- 눈 (만화풍)
def half_disc(name, rx, ry, z0, z1, seg=14, dx=0.0):
    """앞쪽(로컬 +X)이 곧은 세로선이고 뒤쪽이 둥근 반달 판. 로컬 Z 방향으로 z0~z1 두께."""
    pts = [(dx - rx * math.sin(math.pi * i / seg), ry * math.cos(math.pi * i / seg)) for i in range(seg + 1)]
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, z0)) for x, y in pts]
    top = [bm.verts.new((x, y, z1)) for x, y in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return o


def build_eye(body, side, parts):
    """반달 눈: 위쪽은 곧은 선(앞이 조금 낮게), 아래쪽은 둥글다. 테두리·흰자·홍채·동공이 같은 중심의 반달로 겹친다.
    단순하지만 단단한 인상. 하이라이트는 넣지 않는다."""
    hit, nrm = surface_hit(body, H((0.6 * side, -0.95, 0.97)), H((0.0, -0.66, 0.97)))
    # 바깥·약간 앞을 보게 (정면에서도 눈이 보이도록)
    out = (nrm * 0.55 + Vector((side, -0.75, 0.05)).normalized() * 0.45).normalized()
    fwd = Vector((0, -1, 0))
    fwd = (fwd - out * fwd.dot(out)).normalized()          # 눈 평면 안의 '앞'
    up = out.cross(fwd).normalized()
    if up.z < 0:
        up = -up

    RX, RY = HS(0.066), HS(0.066)       # 반달 크기 (RX: 곧은 선에서 둥근 끝까지 = 세로, RY: 곧은 선 반길이 = 가로)
    # 곧은 선이 위로 오도록 60° 돌린다(옆에서 볼 때 반시계). 곧은 윗선은 앞쪽이 조금 낮아 강한 인상
    TILT = math.radians(-60)
    xa = fwd * math.cos(TILT) - up * math.sin(TILT)
    ya = out.cross(xa).normalized()
    if ya.dot(up) < 0:
        ya = -ya
    # 곧은 선 쪽으로 반쯤 옮겨 눈 전체가 접점 둘레에 놓이게 한다
    c = hit + xa * (RX * 0.45)

    def put(o):
        m = Matrix((xa, ya, out)).transposed().to_4x4()
        m.translation = c
        o.matrix_world = m
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        return o

    # (슬롯, 크기 비율, 바깥으로 올라온 높이) — 안쪽 층일수록 조금씩 더 튀어나와 겹쳐 보인다
    layers = [("lid", 1.00, 0.010), ("sclera", 0.82, 0.014), ("iris", 0.60, 0.018), ("pupil", 0.34, 0.022)]
    for slot, k, h in layers:
        # 안쪽 층은 살짝 뒤로: 곧은 앞선에도 검은 테두리 선이 보이게
        dx = 0.0 if slot == "lid" else HS(-0.007)
        parts[slot].append(put(half_disc(f"Eye_{slot}{side}", RX * k, RY * k, HS(-0.03), HS(h), dx=dx)))


def build_parts(body):
    parts = {k: [] for k in ("accent", "claw", "sclera", "iris", "pupil", "lid")}
    # 돌머리 뒤쪽 테두리 혹 (빌드 색)
    for i in range(9):
        a = math.radians(-80 + i * (160 / 8))
        y = DOME_C.y + DOME_R.y * 0.92 * math.cos(a)
        z = dome_rim_z(y) - 0.005
        origin = (0.6 * math.sin(a), DOME_C.y + 0.6 * math.cos(a), z)
        hit, nrm = surface_hit(body, origin, (0, DOME_C.y, z))
        parts["accent"].append(cone(f"Knob{i}", hit - nrm * HS(0.012), HS(0.042), HS(0.115), nrm + Vector((0, 0, 0.5)), verts=5))
    # 입선: 코끝 아래에서 뒤로 짧게 (눈 테두리와 같은 색)
    for s in (-1, 1):
        pts = []
        for y, z in [(-0.875, 0.875), (-0.83, 0.865), (-0.78, 0.86), (-0.73, 0.862)]:
            hit, nrm = surface_hit(body, H((0.6 * s, y, z)), H((0, y, z)))
            pts.append((hit, nrm))
        for k in range(len(pts) - 1):
            (a, na), (b, nb) = pts[k], pts[k + 1]
            parts["lid"].append(stroke(f"Mouth{s}{k}", a, b, (na + nb).normalized(), HS(0.009)))
    # 발톱·손톱
    for s in (-1, 1):
        fx = LEG_X * 1.12 * s
        for k, dx in enumerate((-0.07, 0.0, 0.07)):
            parts["claw"].append(cone(f"Toe{s}{k}", (fx + dx * s, -0.19, 0.04), 0.035, 0.09, (dx, -1, -0.15), verts=4))
        for k, dx in enumerate((-0.025, 0.0, 0.025)):
            parts["claw"].append(cone(f"Hand{s}{k}", (0.225 * s + dx, -0.48, 0.48), 0.017, 0.05, (0, -0.7, -1), verts=4))
    for s in (-1, 1):
        build_eye(body, s, parts)
    return parts


def join_parts(objs, mat, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        for poly in o.data.polygons:
            poly.use_smooth = False
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.materials.clear()
    o.data.materials.append(mat)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


# ---------------------------------------------------------------- 렌더
def setup_render():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.render.resolution_x = 900
    sc.render.resolution_y = 900
    sc.view_settings.view_transform = "Standard"

    world = bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.82, 0.84, 0.88, 1)
    bg.inputs["Strength"].default_value = 1.0

    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0.3, 0))
    floor = bpy.context.active_object
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.6, 0.62, 0.66, 1)
    floor.data.materials.append(fm)

    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(-35)))
    sun = bpy.context.active_object
    sun.data.energy = 3.0
    sun.data.angle = math.radians(8)

    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def look_at(cam, target, pos, lens):
    cam.data.lens = lens
    cam.location = Vector(pos)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()


VIEWS = {
    # 이름: (대상, 카메라 위치, 렌즈)
    "front34": ((0, 0.05, 0.72), (-2.6, -3.4, 1.7), 50),
    "side":    ((0, 0.05, 0.72), (-4.4, 0.25, 0.95), 50),
    "front":   ((0, 0.05, 0.72), (0.0, -4.4, 1.0), 50),
    "back34":  ((0, 0.05, 0.72), (2.8, 3.6, 1.8), 50),
    "face":    ((0, -0.80, 1.04), (-1.20, -2.05, 1.28), 60),
}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = {k: make_mat(k) for k in PALETTE}

    body = to_lowpoly(build_body(), target_tris=2000)
    paint_body(body, mats)

    pieces = [body]
    for key, objs in build_parts(body).items():
        pieces.append(join_parts(objs, mats[key], key.capitalize()))

    bpy.ops.object.select_all(action="DESELECT")
    for o in pieces:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    dino = bpy.context.active_object
    dino.name = "Dino"

    tris = sum(len(p.vertices) - 2 for p in dino.data.polygons)
    print(f"[dino] triangles: {tris}")
    print(f"[dino] materials: {[m.name for m in dino.data.materials]}")

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "dino.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "dino.glb"), export_format="GLB", use_selection=True)

    cam = setup_render()
    for name, (target, pos, lens) in VIEWS.items():
        look_at(cam, target, pos, lens)
        bpy.context.scene.render.filepath = os.path.join(OUT, f"render_{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[dino] rendered {name}")


main()

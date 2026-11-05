"""Ram 조력자 4인 — 첫 디자인 (로우폴리)

실행:  python build_helpers.py [출력폴더]
  - 출력폴더/<이름>.glb·.blend, render_<이름>.png, lineup.png (Ram 과 나란히) 를 만든다.
  - Ram 과 크기를 비교하려면 assets/characters/ram/dino.blend 가 있어야 한다.

조력자 (빌드 · 합체 필살기)
  crane   두루미  — 1번 빌드 · 두루치기
  sheep   양      — 2번 빌드 · 양치기
  catfish 메기    — 3번 빌드 · 메치기
  flyfish 날치    — 4번 빌드 · 날치기

만드는 법은 build_dino.py 와 같다: 몸은 타원체를 겹쳐 리메시한 뒤 면을 줄이고,
가는 부분(다리·부리·수염·지느러미)은 따로 만든 조각을 붙인다. 눈은 Ram 과 같은 반달 동심원.
좌표: Z 위, 정면 -Y.
"""
import math
import os
import random
import sys

import bpy
import bmesh  # bpy 다음에 불러와야 한다
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_dino as D  # 도구 함수만 쓴다 (main 은 실행되지 않음)

OUT = os.path.abspath(sys.argv[-1]) if len(sys.argv) > 1 and not sys.argv[-1].endswith(".py") else os.path.abspath("out_helpers")
os.makedirs(OUT, exist_ok=True)
RAM_BLEND = os.path.join(HERE, "..", "..", "assets", "characters", "ram", "dino.blend")


# ---------------------------------------------------------------- 공통 도구
def mat(name, rgb, rough=0.85):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    col = D.srgb_to_linear(rgb)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*col, 1.0)
    return m


def melt(blobs, voxel=0.012, target_tris=1800):
    """타원체 목록 [(중심, 반지름)] 을 한 덩어리로 녹여 로우폴리로."""
    store = []
    for co, semi in blobs:
        D.blob(co, semi, store)
    bpy.ops.object.select_all(action="DESELECT")
    for o in store:
        o.select_set(True)
    bpy.context.view_layer.objects.active = store[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    rm = body.modifiers.new("Remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    sm = body.modifiers.new("Smooth", "SMOOTH")
    sm.factor = 0.6
    sm.iterations = 6
    for m in list(body.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return D.to_lowpoly(body, target_tris)


def chain_blobs(pts, semis, steps=6):
    out = []
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i]), Vector(pts[i + 1])
        sa, sb = Vector(semis[i]), Vector(semis[i + 1])
        for k in range(steps):
            t = k / steps
            out.append((tuple(a.lerp(b, t)), tuple(sa.lerp(sb, t))))
    out.append((pts[-1], semis[-1]))
    return out


def rod(name, pts, radius, verts=6):
    """가는 막대(다리·수염): 점을 잇는 원뿔대 조각들. 리메시하지 않아 가늘어도 끊기지 않는다."""
    objs = []
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i]), Vector(pts[i + 1])
        r0 = radius[i] if isinstance(radius, (list, tuple)) else radius
        r1 = radius[i + 1] if isinstance(radius, (list, tuple)) else radius
        d = b - a
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1, depth=d.length,
                                        location=(a + b) / 2,
                                        rotation=Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler())
        o = bpy.context.active_object
        o.name = f"{name}{i}"
        objs.append(o)
        # 관절 이음매를 메우는 작은 공
        objs.append(D.ellipsoid(f"{name}J{i}", (r1, r1, r1), subdiv=1))
        objs[-1].location = b
    return objs


def flat(name, center, semi, rot_deg=(0, 0, 0)):
    """납작한 판(지느러미·날개·귀)."""
    o = D.ellipsoid(name, semi, subdiv=2)
    o.rotation_euler = tuple(math.radians(v) for v in rot_deg)
    o.location = center
    return o


def eye_pair(body, parts, origin, toward, size, tilt_deg, out_bias=(1, -0.75, 0.05), sides=(-1, 1)):
    """Ram 과 같은 반달 동심원 눈. tilt_deg: 곧은 선 방향 (-90=곧은 선이 위, 졸린 눈매)."""
    for s in sides:
        o = Vector((origin[0] * s, origin[1], origin[2]))
        t = Vector((toward[0] * s, toward[1], toward[2]))
        hit, nrm = D.surface_hit(body, o, t)
        out = (nrm * 0.55 + Vector((s * out_bias[0], out_bias[1], out_bias[2])).normalized() * 0.45).normalized()
        fwd = Vector((0, -1, 0))
        fwd = (fwd - out * fwd.dot(out)).normalized()
        up = out.cross(fwd).normalized()
        if up.z < 0:
            up = -up
        T = math.radians(tilt_deg)
        xa = fwd * math.cos(T) - up * math.sin(T)
        ya = out.cross(xa).normalized()
        if ya.dot(up) < 0:
            ya = -ya
        c = hit + xa * (size * 0.45)
        for slot, k, h in [("eye_rim", 1.0, 0.010), ("sclera", 0.82, 0.014), ("iris", 0.60, 0.018), ("pupil", 0.34, 0.022)]:
            dx = 0.0 if slot == "eye_rim" else -0.007 * size / 0.066
            o2 = D.half_disc(f"Eye_{slot}{s}", size * k, size * k, -0.03 * size / 0.066, h * size / 0.066, dx=dx)
            m = Matrix((xa, ya, out)).transposed().to_4x4()
            m.translation = c
            o2.matrix_world = m
            parts.setdefault(slot, []).append(o2)


def finish(name, body, paint, slots, parts, mats):
    """몸 색칠 + 조각 붙이기 → 한 오브젝트."""
    for sl in slots:
        body.data.materials.append(mats[sl])
    for p in body.data.polygons:
        p.material_index = slots.index(paint(p.center, p.normal))
    pieces = [body]
    for slot, objs in parts.items():
        if not objs:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        j = bpy.context.active_object
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        for poly in j.data.polygons:
            poly.use_smooth = False
        j.data.materials.clear()
        j.data.materials.append(mats[slot])
        pieces.append(j)
    bpy.ops.object.select_all(action="DESELECT")
    for o in pieces:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"[helper] {name}: {tris} tris")
    return obj


EYE_MATS = {"eye_rim": (0.05, 0.05, 0.06), "sclera": (1, 1, 1), "pupil": (0.02, 0.02, 0.02)}


# ---------------------------------------------------------------- 1. 두루미 (두루치기)
def build_crane():
    """키 큰 스승. 흰 몸, 검은 목·꼬리깃, 정수리 붉은 점. 졸린 반달 눈."""
    mats = {k: mat(f"crane_{k}", v) for k, v in {
        "white": (0.92, 0.91, 0.88), "black": (0.12, 0.12, 0.13), "crown": (0.80, 0.16, 0.14),
        "beak": (0.62, 0.60, 0.45), "leg": (0.20, 0.20, 0.21), "iris": (0.95, 0.75, 0.30), **EYE_MATS}.items()}
    blobs = [((0, 0.00, 1.05), (0.22, 0.36, 0.24)),          # 몸통
             ((0, 0.34, 1.08), (0.18, 0.18, 0.14)),          # 꼬리깃(접은 날개 끝)
             ((0, 0.52, 1.02), (0.10, 0.12, 0.08))]
    blobs += chain_blobs([(0, -0.24, 1.18), (0, -0.34, 1.50), (0, -0.30, 1.78)],
                         [(0.075, 0.075, 0.08), (0.055, 0.055, 0.06), (0.05, 0.05, 0.05)])  # 긴 목
    blobs += [((0, -0.33, 1.86), (0.08, 0.105, 0.085))]     # 머리
    body = melt(blobs, voxel=0.009, target_tris=1600)

    def paint(c, n):
        if c.z > 1.915 and c.y > -0.40:
            return "crown"                                   # 정수리 붉은 점
        if c.y > 0.22 or (1.22 < c.z < 1.80 and c.y < -0.2):
            return "black"                                   # 꼬리깃, 목
        return "white"

    parts = {"beak": [], "leg": []}
    bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.03, radius2=0.004, depth=0.24,
                                    location=(0, -0.53, 1.85),
                                    rotation=Vector((0, 0, 1)).rotation_difference(Vector((0, -1, -0.12)).normalized()).to_euler())
    parts["beak"].append(bpy.context.active_object)
    for s in (-1, 1):
        x = 0.07 * s
        parts["leg"] += rod(f"Leg{s}", [(x, 0.02, 0.92), (x, 0.08, 0.50), (x, 0.0, 0.05)], [0.028, 0.02, 0.018])
        for dx, dy in ((-0.05, -0.10), (0, -0.12), (0.05, -0.10), (0, 0.06)):
            parts["leg"] += rod(f"Toe{s}{dx}{dy}", [(x, 0.0, 0.03), (x + dx, dy, 0.015)], 0.012, verts=4)
    eye_pair(body, parts, origin=(0.5, -0.37, 1.87), toward=(0, -0.37, 1.87), size=0.038, tilt_deg=-90)
    return finish("Crane", body, paint, ["white", "black", "crown"], parts, mats)


# ---------------------------------------------------------------- 2. 양 (양치기)
def build_sheep():
    """작고 동글한 털뭉치. 검은 얼굴·다리, 옆으로 말린 뿔(숫양)."""
    mats = {k: mat(f"sheep_{k}", v) for k, v in {
        "wool": (0.93, 0.88, 0.76), "face": (0.20, 0.19, 0.19), "horn": (0.78, 0.70, 0.52),
        "hoof": (0.12, 0.12, 0.12), "iris": (0.90, 0.68, 0.20), **EYE_MATS}.items()}
    rnd = random.Random(7)
    blobs = [((0, 0.02, 0.62), (0.32, 0.40, 0.30))]          # 털 몸통
    for _ in range(26):                                      # 몽글몽글한 털
        th, ph = rnd.uniform(0, 2 * math.pi), rnd.uniform(-0.2, 1.3)
        p = Vector((0.30 * math.cos(th) * math.cos(ph), 0.38 * math.sin(th) * math.cos(ph) + 0.02, 0.62 + 0.28 * math.sin(ph)))
        blobs.append((tuple(p), (0.11, 0.11, 0.10)))
    blobs += [((0, -0.42, 0.78), (0.12, 0.15, 0.13)),        # 얼굴
              ((0, -0.52, 0.72), (0.09, 0.09, 0.08)),        # 주둥이
              ((0, -0.36, 0.93), (0.12, 0.10, 0.08))]        # 정수리 털 뭉치
    body = melt(blobs, voxel=0.011, target_tris=1900)

    def near(c, cen, semi, k):
        d = c - Vector(cen)
        return (d.x / semi[0]) ** 2 + (d.y / semi[1]) ** 2 + (d.z / semi[2]) ** 2 < k

    def paint(c, n):
        if c.z < 0.88 and (near(c, (0, -0.42, 0.78), (0.12, 0.15, 0.13), 1.3) or near(c, (0, -0.52, 0.72), (0.09, 0.09, 0.08), 1.4)):
            return "face"
        return "wool"

    parts = {"horn": [], "hoof": [], "face": []}
    for s in (-1, 1):
        # 귀 옆으로 말린 뿔: 나선을 따라 점점 가늘게
        pts, rads = [], []
        for i in range(10):
            t = i / 9
            a = math.radians(-40 + 300 * t)
            r = 0.10 * (1 - 0.55 * t)
            pts.append((s * (0.13 + 0.05 * t), -0.34 + r * math.cos(a), 0.86 - r * math.sin(a)))
            rads.append(0.045 * (1 - 0.6 * t))
        parts["horn"] += rod(f"Horn{s}", pts, rads)
        parts["face"].append(flat(f"Ear{s}", (s * 0.15, -0.36, 0.80), (0.07, 0.03, 0.025), (0, s * 20, s * -20)))
        for y in (-0.20, 0.22):
            parts["face"] += rod(f"LegS{s}{y}", [(s * 0.17, y, 0.40), (s * 0.17, y, 0.06)], [0.04, 0.032])
            parts["hoof"].append(D.ellipsoid(f"Hoof{s}{y}", (0.05, 0.06, 0.035), subdiv=1))
            parts["hoof"][-1].location = (s * 0.17, y - 0.01, 0.035)
    eye_pair(body, parts, origin=(0.5, -0.47, 0.81), toward=(0, -0.40, 0.81), size=0.036, tilt_deg=-70)
    return finish("Sheep", body, paint, ["wool", "face"], parts, mats)


# ---------------------------------------------------------------- 3. 메기 (메치기)
def build_catfish():
    """공중에 떠 있는 넓적한 메기. 긴 수염 두 쌍으로 잡아 메친다."""
    mats = {k: mat(f"catfish_{k}", v) for k, v in {
        "back": (0.22, 0.36, 0.34), "belly": (0.78, 0.80, 0.70), "fin": (0.16, 0.27, 0.26),
        "whisker": (0.10, 0.12, 0.12), "iris": (0.95, 0.80, 0.30), **EYE_MATS}.items()}
    blobs = [((0, -0.38, 0.80), (0.30, 0.26, 0.17)),         # 넓적한 머리
             ((0, -0.08, 0.80), (0.24, 0.30, 0.17))]
    blobs += chain_blobs([(0, 0.15, 0.80), (0, 0.45, 0.82), (0, 0.70, 0.84)],
                         [(0.18, 0.18, 0.15), (0.11, 0.12, 0.11), (0.05, 0.06, 0.07)])
    body = melt(blobs, voxel=0.012, target_tris=1700)

    def paint(c, n):
        return "belly" if n.z < -0.2 and c.z < 0.80 else "back"

    parts = {"fin": [], "whisker": []}
    parts["fin"].append(flat("TailFin", (0, 0.82, 0.86), (0.015, 0.14, 0.13), (0, 0, 0)))
    parts["fin"].append(flat("Dorsal", (0, 0.05, 0.98), (0.012, 0.12, 0.07), (-15, 0, 0)))
    for s in (-1, 1):
        parts["fin"].append(flat(f"Pec{s}", (s * 0.30, -0.18, 0.70), (0.16, 0.08, 0.012), (0, s * -20, s * -25)))
        # 긴 수염 (입꼬리에서 늘어져 앞으로 휘어 오름) + 짧은 수염
        # 긴 수염: 입꼬리에서 옆·앞으로 뻗다가 콧수염처럼 늘어짐 (잡아 메칠 때 쓰는 '손')
        parts["whisker"] += rod(f"WhL{s}", [(s * 0.20, -0.58, 0.77), (s * 0.34, -0.70, 0.75),
                                            (s * 0.45, -0.77, 0.68), (s * 0.50, -0.78, 0.58)], [0.018, 0.014, 0.010, 0.005])
        # 짧은 턱수염
        parts["whisker"] += rod(f"WhS{s}", [(s * 0.08, -0.60, 0.69), (s * 0.11, -0.66, 0.63)], [0.010, 0.004])
    eye_pair(body, parts, origin=(0.6, -0.48, 0.90), toward=(0, -0.40, 0.84), size=0.034, tilt_deg=-55,
             out_bias=(1, -0.4, 0.5))
    # 넓은 입선
    pts = []
    for x in (-0.20, -0.10, 0.0, 0.10, 0.20):
        hit, nrm = D.surface_hit(body, (x, -1.2, 0.74), (x, 0, 0.74))
        pts.append((hit, nrm))
    for k in range(len(pts) - 1):
        (a, na), (b, nb) = pts[k], pts[k + 1]
        parts["whisker"].append(D.stroke(f"Mouth{k}", a, b, (na + nb).normalized(), 0.010))
    return finish("Catfish", body, paint, ["back", "belly"], parts, mats)


# ---------------------------------------------------------------- 4. 날치 (날치기)
def build_flyfish():
    """작고 날렵한 물고기. 날개처럼 펼친 큰 가슴지느러미, 갈라진 꼬리."""
    mats = {k: mat(f"flyfish_{k}", v) for k, v in {
        "back": (0.20, 0.38, 0.62), "belly": (0.82, 0.86, 0.90), "wing": (0.55, 0.72, 0.88),
        "tail": (0.18, 0.32, 0.55), "iris": (0.95, 0.90, 0.55), **EYE_MATS}.items()}
    blobs = chain_blobs([(0, -0.38, 0.95), (0, -0.20, 0.96), (0, 0.10, 0.96), (0, 0.38, 0.95)],
                        [(0.08, 0.08, 0.08), (0.12, 0.12, 0.12), (0.10, 0.12, 0.10), (0.04, 0.05, 0.05)])
    body = melt(blobs, voxel=0.009, target_tris=1200)

    def paint(c, n):
        return "belly" if n.z < 0.1 and c.z < 0.96 else "back"

    parts = {"wing": [], "tail": []}
    for s in (-1, 1):
        parts["wing"].append(flat(f"Wing{s}", (s * 0.32, -0.02, 0.98), (0.30, 0.13, 0.008), (0, s * 8, s * -18)))
        parts["wing"].append(flat(f"Pelvic{s}", (s * 0.13, 0.20, 0.90), (0.10, 0.05, 0.006), (0, s * -10, s * -15)))
        parts["tail"].append(flat(f"Tail{s}", (0, 0.50, 0.95 + 0.08 * s), (0.008, 0.16, 0.05), (s * -28, 0, 0)))
    eye_pair(body, parts, origin=(0.5, -0.30, 0.99), toward=(0, -0.28, 0.97), size=0.036, tilt_deg=-70)
    return finish("FlyFish", body, paint, ["back", "belly"], parts, mats)


# ---------------------------------------------------------------- 렌더
def setup_scene(lens, cam_pos, target):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 32
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "Standard"
    if not sc.world:
        sc.world = bpy.data.worlds.new("World")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.82, 0.84, 0.88, 1)
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(-35)))
    bpy.context.active_object.data.energy = 3.0
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = lens
    cam.location = Vector(cam_pos)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    return sc


def render(sc, path, w, h):
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


BUILDERS = [("crane", build_crane), ("sheep", build_sheep), ("catfish", build_catfish), ("flyfish", build_flyfish)]


def main():
    # 하나씩: 모델 파일 + 3/4 렌더
    for key, fn in BUILDERS:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        obj = fn()
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, f"{key}.blend"))
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"{key}.glb"), export_format="GLB", use_selection=True)
        vs = [obj.matrix_world @ v.co for v in obj.data.vertices]
        lo = Vector((min(v.x for v in vs), min(v.y for v in vs), 0.0))
        hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        center, size = (lo + hi) / 2, (hi - lo).length
        cam = center + Vector((-0.55, -0.75, 0.32)).normalized() * size * 1.9
        sc = setup_scene(50, tuple(cam), tuple(center))
        render(sc, os.path.join(OUT, f"render_{key}.png"), 700, 700)

    # 한 줄로: 두루미 · 양 · Ram · 메기 · 날치
    bpy.ops.wm.read_factory_settings(use_empty=True)
    xs = {"crane": -2.4, "sheep": -1.2, "ram": 0.0, "catfish": 1.35, "flyfish": 2.55}
    for key, _ in BUILDERS:
        with bpy.data.libraries.load(os.path.join(OUT, f"{key}.blend")) as (src, dst):
            dst.objects = [n for n in src.objects]
        for o in dst.objects:
            if o and o.type == "MESH":
                bpy.context.collection.objects.link(o)
                o.location.x += xs[key]
    if os.path.exists(RAM_BLEND):
        with bpy.data.libraries.load(RAM_BLEND) as (src, dst):
            dst.objects = [n for n in src.objects if n == "Dino"]
        for o in dst.objects:
            bpy.context.collection.objects.link(o)
            o.location.x += xs["ram"]
    else:
        print(f"[helper] Ram 모델이 없어 줄 세우기에서 뺌: {RAM_BLEND}")
    sc = setup_scene(42, (-1.6, -7.6, 2.0), (0.1, 0, 0.85))
    render(sc, os.path.join(OUT, "lineup.png"), 1600, 800)
    print("[helper] done")


if __name__ == "__main__":
    main()

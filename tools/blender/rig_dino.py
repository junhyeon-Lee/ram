"""Ram 주인공 — 뼈대(리깅)와 기본 동작

실행:  python rig_dino.py <모델.blend> [출력폴더]
  - build_dino.py 가 만든 dino.blend 를 읽어 뼈대·가중치·동작을 넣고
    출력폴더/ram_rigged.blend, ram_rigged.glb, anim_*.png 를 만든다.

좌표: Z 위, 정면 -Y (build_dino.py 와 같다).

뼈대 (부모 → 자식)
  root ─ pelvis ─┬ spine ─ neck ─ head
                 │        └ arm.L/R ─ forearm.L/R
                 ├ thigh.L/R ─ shin.L/R ─ foot.L/R
                 └ tail.1 ─ tail.2 ─ tail.3

가중치: 몸(가장 큰 덩어리)은 꼭짓점마다 가까운 뼈 2~3개에 거리로 나눠 준다.
눈·돌기·입선·발톱처럼 따로 떨어진 조각은 통째로 가장 가까운 뼈 하나에 붙인다.
(Blender 자동 가중치는 떨어진 조각에서 실패하기 쉬워서 직접 계산한다.)

동작 (30fps). 이름 끝의 "-loop" 는 Godot 가 반복 재생으로 가져오라는 표시다.
  Idle-loop   대기: 숨쉬기, 꼬리 살랑
  Run-loop    달리기: 다리 교차, 몸 앞으로 기울임, 위아래 출렁
  Headbutt    박치기: 뒤로 젖혔다가 앞으로 내리꽂고 돌아온다
"""
import math
import os
import sys

import bpy
import bmesh  # bpy 다음에 불러와야 한다
from mathutils import Quaternion, Vector
from mathutils.geometry import intersect_point_line

args = [a for a in sys.argv[1:] if not a.endswith(".py")]
if "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
if not args:
    sys.exit("사용법: python rig_dino.py <모델.blend> [출력폴더]")
SRC = os.path.abspath(args[0])
OUT = os.path.abspath(args[1]) if len(args) > 1 else os.path.abspath("out_rig")
os.makedirs(OUT, exist_ok=True)

FPS = 30

# ---------------------------------------------------------------- 뼈 위치 (build_dino.py 의 몸 비율에 맞춤)
LEG_X = 0.20
BONES = {
    # 이름: (머리, 꼬리, 부모, 부모에 붙임)
    "root":   ((0, 0, 0), (0, 0.3, 0), None, False),
    "pelvis": ((0, 0.22, 0.80), (0, 0.0, 0.80), "root", False),
    "spine":  ((0, 0.0, 0.80), (0, -0.26, 0.88), "pelvis", True),
    "neck":   ((0, -0.26, 0.88), (0, -0.44, 0.97), "spine", True),
    "head":   ((0, -0.44, 0.97), (0, -1.00, 0.97), "neck", True),
    "tail.1": ((0, 0.30, 0.84), (0, 0.74, 0.90), "pelvis", False),
    "tail.2": ((0, 0.74, 0.90), (0, 1.01, 0.87), "tail.1", True),
    "tail.3": ((0, 1.01, 0.87), (0, 1.30, 0.80), "tail.2", True),
}
for side, sx in (("L", 1), ("R", -1)):
    x = LEG_X * sx
    BONES[f"thigh.{side}"] = ((x, 0.08, 0.70), (x * 1.08, 0.19, 0.30), "pelvis", False)
    BONES[f"shin.{side}"] = ((x * 1.08, 0.19, 0.30), (x * 1.12, 0.06, 0.08), f"thigh.{side}", True)
    BONES[f"foot.{side}"] = ((x * 1.12, 0.06, 0.08), (x * 1.12, -0.20, 0.04), f"shin.{side}", True)
    BONES[f"arm.{side}"] = ((0.19 * sx, -0.24, 0.72), (0.235 * sx, -0.33, 0.58), "spine", False)
    BONES[f"forearm.{side}"] = ((0.235 * sx, -0.33, 0.58), (0.225 * sx, -0.49, 0.48), f"arm.{side}", True)

DEFORM = [b for b in BONES if b != "root"]


# ---------------------------------------------------------------- 뼈대
def build_armature():
    arm_data = bpy.data.armatures.new("RamRig")
    arm = bpy.data.objects.new("RamRig", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    for name, (h, t, parent, connect) in BONES.items():
        b = eb.new(name)
        b.head, b.tail = Vector(h), Vector(t)
        b.roll = 0.0
    for name, (h, t, parent, connect) in BONES.items():
        if parent:
            eb[name].parent = eb[parent]
            eb[name].use_connect = connect
    eb["root"].use_deform = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# ---------------------------------------------------------------- 가중치
def islands(mesh):
    """연결된 꼭짓점 덩어리들 (꼭짓점 번호 목록), 큰 것부터."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    seen = [False] * len(bm.verts)
    out = []
    for v in bm.verts:
        if seen[v.index]:
            continue
        stack, comp = [v], []
        seen[v.index] = True
        while stack:
            cur = stack.pop()
            comp.append(cur.index)
            for e in cur.link_edges:
                o = e.other_vert(cur)
                if not seen[o.index]:
                    seen[o.index] = True
                    stack.append(o)
        out.append(comp)
    bm.free()
    out.sort(key=len, reverse=True)
    return out


def seg_dist(p, a, b):
    q, t = intersect_point_line(p, a, b)
    if t < 0:
        q = a
    elif t > 1:
        q = b
    return (p - q).length


def bone_dists(p):
    return {n: seg_dist(p, Vector(BONES[n][0]), Vector(BONES[n][1])) for n in DEFORM}


def skin(mesh_obj, arm):
    me = mesh_obj.data
    groups = {n: mesh_obj.vertex_groups.new(name=n) for n in DEFORM}
    comps = islands(me)
    body = comps[0]
    # 몸: 가까운 뼈 3개에 거리^-6 비율로 (멀수록 급격히 줄어 관절 근처에서만 섞인다)
    for vi in body:
        p = me.vertices[vi].co
        d = sorted(bone_dists(p).items(), key=lambda kv: kv[1])[:3]
        ws = [(n, 1.0 / (max(dist, 1e-4) ** 6)) for n, dist in d]
        tot = sum(w for _, w in ws)
        for n, w in ws:
            if w / tot > 0.02:
                groups[n].add([vi], w / tot, "REPLACE")
    # 떨어진 조각: 덩어리 중심에서 가장 가까운 뼈 하나에 통째로
    for comp in comps[1:]:
        c = sum((me.vertices[i].co for i in comp), Vector()) / len(comp)
        n = min(bone_dists(c).items(), key=lambda kv: kv[1])[0]
        groups[n].add(comp, 1.0, "REPLACE")
    # 확인: 가중치 없는 꼭짓점이 없어야 한다
    unweighted = [v.index for v in me.vertices if not v.groups]
    if unweighted:
        raise RuntimeError(f"가중치 없는 꼭짓점 {len(unweighted)}개")
    print(f"[rig] islands: {len(comps)} (body {len(body)} verts)")

    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    mesh_obj.parent = arm


# ---------------------------------------------------------------- 동작
# 각도는 '월드 축' 기준으로 적는다: X = 몸의 좌우 축(끄덕임·다리 앞뒤), Z = 위 축(좌우로 흔들기).
#   X 축 +각도: 앞을 보는 뼈는 아래로 숙이고, 아래를 보는 다리는 뒤로 차고, 뒤를 보는 꼬리는 위로 든다.
def local_rot(pb, axis, deg):
    m = pb.bone.matrix_local.to_3x3()
    q = Quaternion(Vector(axis), math.radians(deg)).to_matrix()
    return (m.inverted() @ q @ m).to_quaternion()


def compose(pb, rots):
    q = Quaternion()
    for axis, deg in rots:
        q = local_rot(pb, axis, deg) @ q
    return q


X, Z = (1, 0, 0), (0, 0, 1)


def key_pose(arm, frame, pose, root_loc=(0, 0, 0)):
    """pose: {뼈: [(축, 각도), ...]}. 적지 않은 뼈는 기본 자세로 키를 넣는다(동작마다 완결)."""
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = compose(pb, pose.get(pb.name, []))
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if pb.name == "root":
            pb.location = Vector(root_loc)
            pb.keyframe_insert("location", frame=frame)
        else:
            pb.location = Vector()


def make_action(arm, name, keys):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    for frame, pose, loc in keys:
        key_pose(arm, frame, pose, loc)
    print(f"[rig] action {name}: frames {keys[0][0]}-{keys[-1][0]}")
    return act


def idle_keys():
    rest = {}
    breathe = {"spine": [(X, -2.5)], "neck": [(X, 1.5)], "head": [(X, 1.0)],
               "tail.1": [(Z, 4)], "tail.2": [(Z, 5)], "tail.3": [(Z, 6)],
               "arm.L": [(X, -4)], "arm.R": [(X, -4)]}
    sway_back = {"tail.1": [(Z, -4)], "tail.2": [(Z, -5)], "tail.3": [(Z, -6)]}
    return [(1, rest, (0, 0, 0)), (21, breathe, (0, 0, 0)), (31, sway_back, (0, 0, 0)), (41, rest, (0, 0, 0))]


def run_keys():
    lean = [(X, 10)]
    def stride(s):
        # s=+1: 왼다리 앞(뒤로 찰 때 + 이므로 앞은 -), 오른다리 뒤
        return {
            "spine": lean, "neck": [(X, -6)], "head": [(X, -4)],
            "thigh.L": [(X, -32 * s)], "shin.L": [(X, 18 if s > 0 else 40)], "foot.L": [(X, -10 * s)],
            "thigh.R": [(X, 32 * s)], "shin.R": [(X, 40 if s > 0 else 18)], "foot.R": [(X, 10 * s)],
            "arm.L": [(X, 20 * s)], "arm.R": [(X, -20 * s)],
            "tail.1": [(X, 6), (Z, 6 * s)], "tail.2": [(Z, 8 * s)], "tail.3": [(Z, 10 * s)],
        }
    passing = {"spine": lean, "neck": [(X, -6)], "head": [(X, -4)],
               "thigh.L": [(X, 0)], "shin.L": [(X, 30)], "thigh.R": [(X, 0)], "shin.R": [(X, 30)],
               "tail.1": [(X, 6)]}
    up, down = (0, 0, 0.04), (0, 0, -0.02)
    return [(1, stride(1), down), (5, passing, up), (9, stride(-1), down), (13, passing, up), (17, stride(1), down)]


def headbutt_keys():
    rest = {}
    windup = {"spine": [(X, -14)], "neck": [(X, -10)], "head": [(X, -18)],
              "thigh.L": [(X, 8)], "thigh.R": [(X, 8)], "shin.L": [(X, 10)], "shin.R": [(X, 10)],
              "tail.1": [(X, -8)], "tail.2": [(X, -6)], "arm.L": [(X, -25)], "arm.R": [(X, -25)]}
    # 돌머리 앞면이 상대 가슴 높이를 향하도록: 너무 숙이면 땅을 박는다
    strike = {"spine": [(X, 14)], "neck": [(X, 10)], "head": [(X, 18)],
              "thigh.L": [(X, -28)], "shin.L": [(X, 20)], "thigh.R": [(X, 22)], "shin.R": [(X, 8)],
              "tail.1": [(X, 14)], "tail.2": [(X, 10)], "tail.3": [(X, 8)],
              "arm.L": [(X, 30)], "arm.R": [(X, 30)]}
    return [
        (1, rest, (0, 0, 0)),
        (8, windup, (0, 0.10, -0.02)),     # 뒤로 젖히며 힘 모으기
        (12, strike, (0, -0.32, -0.04)),   # 앞으로 내리꽂기 (가장 빠른 구간)
        (16, strike, (0, -0.34, -0.04)),   # 맞은 순간 잠깐 멈춤
        (28, rest, (0, 0, 0)),             # 돌아오기
    ]


# ---------------------------------------------------------------- 렌더 (확인용)
def setup_render():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = True
    sc.render.resolution_x = sc.render.resolution_y = 600
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.82, 0.84, 0.88, 1)
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0.3, 0))
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(-35)))
    bpy.context.active_object.data.energy = 3.0
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 50
    cam.location = Vector((-4.6, -0.6, 1.0))
    cam.rotation_euler = (Vector((0, -0.1, 0.7)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    return sc


def main():
    bpy.ops.wm.open_mainfile(filepath=SRC)
    sc = bpy.context.scene
    sc.render.fps = FPS
    mesh_obj = bpy.data.objects["Dino"]
    mesh_obj.name = "Ram"
    mesh_obj.data.name = "Ram"

    arm = build_armature()
    skin(mesh_obj, arm)
    arm.animation_data_create()

    acts = [
        make_action(arm, "Idle-loop", idle_keys()),
        make_action(arm, "Run-loop", run_keys()),
        make_action(arm, "Headbutt", headbutt_keys()),
    ]
    arm.animation_data.action = acts[0]

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "ram_rigged.blend"))
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    mesh_obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "ram_rigged.glb"), export_format="GLB",
                              use_selection=True, export_animations=True,
                              export_animation_mode="ACTIONS")

    # 확인용 렌더: 동작마다 주요 프레임
    setup_render()
    shots = [("Idle-loop", 21), ("Run-loop", 1), ("Run-loop", 9), ("Headbutt", 8), ("Headbutt", 12), ("Headbutt", 28)]
    by_name = {a.name: a for a in acts}
    for name, f in shots:
        arm.animation_data.action = by_name[name]
        sc.frame_set(f)
        sc.render.filepath = os.path.join(OUT, f"anim_{name.split('-')[0].lower()}_{f:02d}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[rig] rendered {name} @ {f}")


main()

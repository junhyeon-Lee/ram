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
  Idle-loop        대기: 숨쉬기, 꼬리 살랑
  Walk-loop        걷기
  Run-loop         달리기: 다리 교차, 몸 앞으로 기울임, 위아래 출렁
  Attack_Slam      박치기: 위로 들었다가 내리찍기
  Attack_Uppercut  박치기: 아래에서 위로 올려치기
  Attack_Hook      박치기: 오른쪽 위로 들었다가 왼쪽 아래로 후려치기
  Parry_Tail       패링: 한 바퀴 돌며 꼬리로 쓸어내기
  Backstep         앞다리로 밀며 뒤로 0.65m
  Dash             뒷다리로 차며 앞으로 1.0m
  Dash_Left/Right  옆으로 0.8m
root 뼈의 위치·회전이 캐릭터 전체 이동이다 (Godot 에서 root motion 으로 쓸 수 있다).
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


X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
# Z 축 +각도: 앞을 보는 뼈가 캐릭터의 왼쪽(+X)으로 돈다. 캐릭터의 오른쪽은 -X.
# Y 축: 앞을 보는 뼈(머리)를 옆으로 갸웃(롤)한다.


def key_pose(arm, frame, pose, root_loc=(0, 0, 0)):
    """pose: {뼈: [(축, 각도), ...]}. 적지 않은 뼈는 기본 자세로 키를 넣는다(동작마다 완결).
    root 의 회전·위치는 캐릭터 전체의 회전·이동이다 (Godot 에서 root motion 으로 쓸 수 있다)."""
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


def merge(*poses):
    """자세 여러 개를 합친다 (같은 뼈는 회전을 이어 붙인다)."""
    out = {}
    for p in poses:
        for k, v in p.items():
            out[k] = out.get(k, []) + list(v)
    return out


CROUCH = {"thigh.L": [(X, -12)], "thigh.R": [(X, -12)], "shin.L": [(X, 26)], "shin.R": [(X, 26)],
          "foot.L": [(X, -12)], "foot.R": [(X, -12)]}


# ---------------------------------------------------------------- 이동
def idle_keys():
    rest = {}
    breathe = {"spine": [(X, -2.5)], "neck": [(X, 1.5)], "head": [(X, 1.0)],
               "tail.1": [(Z, 4)], "tail.2": [(Z, 5)], "tail.3": [(Z, 6)],
               "arm.L": [(X, -4)], "arm.R": [(X, -4)]}
    sway_back = {"tail.1": [(Z, -4)], "tail.2": [(Z, -5)], "tail.3": [(Z, -6)]}
    return [(1, rest, (0, 0, 0)), (21, breathe, (0, 0, 0)), (31, sway_back, (0, 0, 0)), (41, rest, (0, 0, 0))]


def gait_keys(length, swing, lean, bob, arm_swing, tail_sway):
    """걷기·달리기 공통: 다리 교차 4박자 (앞 디딤 → 지나감 → 반대 디딤 → 지나감)."""
    lean_p = {"spine": [(X, lean)], "neck": [(X, -lean * 0.6)], "head": [(X, -lean * 0.4)]}

    def stride(s):
        return merge(lean_p, {
            "thigh.L": [(X, -swing * s)], "shin.L": [(X, swing * 0.55 if s > 0 else swing * 1.25)],
            "foot.L": [(X, -swing * 0.3 * s)],
            "thigh.R": [(X, swing * s)], "shin.R": [(X, swing * 1.25 if s > 0 else swing * 0.55)],
            "foot.R": [(X, swing * 0.3 * s)],
            "arm.L": [(X, arm_swing * s)], "arm.R": [(X, -arm_swing * s)],
            "tail.1": [(X, lean * 0.6), (Z, tail_sway * s)], "tail.2": [(Z, tail_sway * 1.3 * s)],
            "tail.3": [(Z, tail_sway * 1.6 * s)],
        })
    passing = merge(lean_p, {"thigh.L": [(X, 0)], "shin.L": [(X, swing * 0.9)],
                             "thigh.R": [(X, 0)], "shin.R": [(X, swing * 0.9)], "tail.1": [(X, lean * 0.6)]})
    q = length // 4
    up, down = (0, 0, bob), (0, 0, -bob * 0.5)
    return [(1, stride(1), down), (1 + q, passing, up), (1 + 2 * q, stride(-1), down),
            (1 + 3 * q, passing, up), (1 + length, stride(1), down)]


def walk_keys():
    return gait_keys(length=32, swing=18, lean=4, bob=0.015, arm_swing=8, tail_sway=5)


def run_keys():
    return gait_keys(length=16, swing=32, lean=10, bob=0.04, arm_swing=20, tail_sway=7)


# ---------------------------------------------------------------- 박치기 3종
def slam_keys():
    """위로 들었다가 내리찍기."""
    raise_ = {"spine": [(X, -20)], "neck": [(X, -16)], "head": [(X, -26)],
              "thigh.L": [(X, 8)], "thigh.R": [(X, 8)], "shin.L": [(X, 10)], "shin.R": [(X, 10)],
              "tail.1": [(X, -10)], "tail.2": [(X, -6)], "arm.L": [(X, -30)], "arm.R": [(X, -30)]}
    # 돌머리 앞면이 상대 가슴 높이를 향하도록: 너무 숙이면 땅을 박는다
    strike = {"spine": [(X, 16)], "neck": [(X, 12)], "head": [(X, 20)],
              "thigh.L": [(X, -28)], "shin.L": [(X, 20)], "thigh.R": [(X, 22)], "shin.R": [(X, 8)],
              "tail.1": [(X, 16)], "tail.2": [(X, 10)], "tail.3": [(X, 8)],
              "arm.L": [(X, 30)], "arm.R": [(X, 30)]}
    return [(1, {}, (0, 0, 0)),
            (9, raise_, (0, 0.10, 0.02)),      # 머리를 높이 들며 힘 모으기
            (13, strike, (0, -0.32, -0.04)),   # 내리찍기 (가장 빠른 구간)
            (17, strike, (0, -0.34, -0.04)),   # 맞은 순간 잠깐 멈춤
            (30, {}, (0, 0, 0))]


def uppercut_keys():
    """낮게 숙였다가 아래에서 위로 올려치기."""
    low = merge(CROUCH, {"spine": [(X, 16)], "neck": [(X, 14)], "head": [(X, 22)],
                         "tail.1": [(X, 8)], "arm.L": [(X, 20)], "arm.R": [(X, 20)]})
    strike = {"spine": [(X, -18)], "neck": [(X, -20)], "head": [(X, -30)],
              "thigh.L": [(X, -20)], "shin.L": [(X, 10)], "thigh.R": [(X, 18)], "shin.R": [(X, 4)],
              "tail.1": [(X, -12)], "tail.2": [(X, -8)], "arm.L": [(X, -25)], "arm.R": [(X, -25)]}
    return [(1, {}, (0, 0, 0)),
            (9, low, (0, 0.04, -0.07)),        # 웅크려 낮추기
            (13, strike, (0, -0.26, 0.05)),    # 아래에서 위로 올려치기
            (17, strike, (0, -0.28, 0.05)),
            (30, {}, (0, 0, 0))]


def hook_keys():
    """오른쪽 위로 머리를 들었다가 왼쪽 아래로 후려치기."""
    windup = {"spine": [(Z, -14), (X, -6)], "neck": [(Z, -16), (X, -10)],
              "head": [(Z, -14), (X, -16), (Y, -15)],
              "tail.1": [(Z, 14)], "tail.2": [(Z, 10)], "tail.3": [(Z, 8)],
              "arm.L": [(X, -20)], "arm.R": [(X, -10)],
              "thigh.R": [(X, -8)], "thigh.L": [(X, 8)]}
    strike = {"spine": [(Z, 18), (X, 8)], "neck": [(Z, 18), (X, 6)],
              "head": [(Z, 16), (X, 12), (Y, 15)],
              "tail.1": [(Z, -18)], "tail.2": [(Z, -14)], "tail.3": [(Z, -10)],
              "arm.L": [(X, 20)], "arm.R": [(X, 25)],
              "thigh.L": [(X, -20)], "shin.L": [(X, 15)], "thigh.R": [(X, 15)]}
    return [(1, {}, (0, 0, 0)),
            (10, windup, (-0.04, 0.06, 0.01)),  # 오른쪽(-X) 위로 비틀어 들기
            (14, strike, (0.05, -0.22, -0.03)), # 왼쪽 아래로 후려치기
            (18, strike, (0.05, -0.23, -0.03)),
            (30, {}, (0, 0, 0))]


# ---------------------------------------------------------------- 방어·회피
def parry_tail_keys():
    """한 바퀴 돌며 꼬리로 쓸어내기. 180°일 때 꼬리가 정면을 쓸고 지나간다."""
    def spin(deg, tail_bend, tail_lift):
        return merge(CROUCH if 0 < deg < 360 else {}, {
            "root": [(Z, deg)],
            "spine": [(Z, -tail_bend * 0.3)],
            "tail.1": [(Z, -tail_bend), (X, tail_lift)], "tail.2": [(Z, -tail_bend * 1.2)],
            "tail.3": [(Z, -tail_bend * 1.4)],
        })
    # 쿼터니언은 90° 넘게 한 번에 보간하면 반대로 돌 수 있어 60° 간격으로 키를 둔다
    return [(1, {}, (0, 0, 0)),
            (4, spin(60, 12, 6), (0, 0, -0.03)),
            (7, spin(120, 22, 12), (0, 0, -0.04)),
            (10, spin(180, 26, 14), (0, 0, -0.04)),   # 꼬리가 정면을 쓸고 지나감
            (14, spin(240, 22, 10), (0, 0, -0.04)),
            (18, spin(300, 14, 6), (0, 0, -0.03)),
            (22, spin(360, 0, 0), (0, 0, 0)),
            (28, {}, (0, 0, 0))]


def backstep_keys():
    """앞다리로 땅을 강하게 밀며 뒤로 뛰기. 끝에서 뒤(+Y)로 0.65m 물러나 있다."""
    push = merge(CROUCH, {"spine": [(X, -8)], "head": [(X, -6)], "thigh.L": [(X, -14)], "thigh.R": [(X, -14)]})
    air = {"spine": [(X, -10)], "neck": [(X, -4)], "thigh.L": [(X, -28)], "thigh.R": [(X, -22)],
           "shin.L": [(X, 30)], "shin.R": [(X, 34)], "tail.1": [(X, -10)], "arm.L": [(X, -20)], "arm.R": [(X, -20)]}
    land = merge(CROUCH, {"spine": [(X, 6)], "tail.1": [(X, 6)]})
    return [(1, {}, (0, 0, 0)),
            (4, push, (0, 0.02, -0.05)),
            (9, air, (0, 0.42, 0.10)),
            (13, land, (0, 0.65, -0.05)),
            (20, {}, (0, 0.65, 0))]


def dash_keys():
    """뒷다리로 땅을 강하게 차며 앞으로 돌진. 끝에서 앞(-Y)으로 1.0m 나가 있다."""
    load = merge(CROUCH, {"spine": [(X, 10)], "neck": [(X, -6)], "tail.1": [(X, 6)]})
    launch = {"spine": [(X, 14)], "neck": [(X, -8)], "head": [(X, -6)],
              "thigh.L": [(X, 34)], "thigh.R": [(X, 28)], "shin.L": [(X, 6)], "shin.R": [(X, 10)],
              "foot.L": [(X, 20)], "foot.R": [(X, 18)], "tail.1": [(X, 10)], "tail.2": [(X, 6)],
              "arm.L": [(X, 30)], "arm.R": [(X, 30)]}
    land = merge(CROUCH, {"spine": [(X, 8)], "thigh.L": [(X, -10)]})
    return [(1, {}, (0, 0, 0)),
            (4, load, (0, 0.02, -0.06)),
            (8, launch, (0, -0.55, 0.05)),
            (12, land, (0, -1.0, -0.05)),
            (18, {}, (0, -1.0, 0))]


def side_dash_keys(direction):
    """옆으로 대시. direction=+1 왼쪽(+X), -1 오른쪽(-X). 끝에서 옆으로 0.8m."""
    d = direction
    load = merge(CROUCH, {"spine": [(Y, 8 * d)], "head": [(Y, -6 * d)]})
    air = {"spine": [(Y, -14 * d), (Z, 6 * d)], "neck": [(Y, 6 * d)], "head": [(Y, 8 * d)],
           "thigh.L": [(Y, -12 * d)], "thigh.R": [(Y, -12 * d)], "shin.L": [(X, 20)], "shin.R": [(X, 20)],
           "tail.1": [(Z, -16 * d)], "tail.2": [(Z, -12 * d)], "tail.3": [(Z, -8 * d)]}
    land = merge(CROUCH, {"spine": [(Y, -6 * d)], "tail.1": [(Z, 8 * d)]})
    return [(1, {}, (0, 0, 0)),
            (4, load, (0, 0, -0.05)),
            (8, air, (0.45 * d, 0, 0.06)),
            (12, land, (0.8 * d, 0, -0.04)),
            (18, {}, (0.8 * d, 0, 0))]


ACTIONS = [
    ("Idle-loop", idle_keys), ("Walk-loop", walk_keys), ("Run-loop", run_keys),
    ("Attack_Slam", slam_keys), ("Attack_Uppercut", uppercut_keys), ("Attack_Hook", hook_keys),
    ("Parry_Tail", parry_tail_keys), ("Backstep", backstep_keys), ("Dash", dash_keys),
    ("Dash_Left", lambda: side_dash_keys(1)), ("Dash_Right", lambda: side_dash_keys(-1)),
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

    acts = [make_action(arm, name, fn()) for name, fn in ACTIONS]
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
    # 동작마다 가장 특징적인 프레임 하나 (전체 움직임은 preview_anims.py 의 GIF 로 본다)
    shots = [("Idle-loop", 21), ("Walk-loop", 1), ("Run-loop", 1), ("Attack_Slam", 13), ("Attack_Uppercut", 13),
             ("Attack_Hook", 14), ("Parry_Tail", 10), ("Backstep", 9), ("Dash", 8), ("Dash_Left", 8)]
    by_name = {a.name: a for a in acts}
    for name, f in shots:
        arm.animation_data.action = by_name[name]
        sc.frame_set(f)
        sc.render.filepath = os.path.join(OUT, f"anim_{name.split('-')[0].lower()}_{f:02d}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[rig] rendered {name} @ {f}")


main()

"""Ram 주인공 — 동작 미리보기 GIF

실행:  python preview_anims.py <ram_rigged.blend> [출력폴더] [--step N] [--size PX]
  - 동작마다 옆 3/4 각도에서 프레임을 렌더해 출력폴더/anim_<동작>.gif 로 묶는다.
  - GIF 를 만들려면 Pillow 가 필요하다 (pip install pillow).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [a for a in sys.argv[1:] if not a.endswith(".py")]
opts = {"--step": 2, "--size": 360}
pos = []
i = 0
while i < len(argv):
    if argv[i] in opts:
        opts[argv[i]] = int(argv[i + 1])
        i += 2
    else:
        pos.append(argv[i])
        i += 1
if not pos:
    sys.exit("사용법: python preview_anims.py <ram_rigged.blend> [출력폴더] [--step N] [--size PX]")
SRC = os.path.abspath(pos[0])
OUT = os.path.abspath(pos[1]) if len(pos) > 1 else os.path.abspath("out_preview")
STEP, SIZE = opts["--step"], opts["--size"]
os.makedirs(OUT, exist_ok=True)


def setup(sc):
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 12
    sc.cycles.use_denoising = True
    sc.render.resolution_x = sc.render.resolution_y = SIZE
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
    cam.data.lens = 62
    cam.location = Vector((-3.6, -2.4, 1.5))
    cam.rotation_euler = (Vector((0, -0.15, 0.7)) - cam.location).to_track_quat("-Z", "Y").to_euler()


def main():
    bpy.ops.wm.open_mainfile(filepath=SRC)
    sc = bpy.context.scene
    setup(sc)
    arm = bpy.data.objects["RamRig"]
    from PIL import Image  # 렌더가 끝난 뒤에만 필요

    for act in [a for a in bpy.data.actions if a.users or a.use_fake_user]:
        arm.animation_data.action = act
        f0, f1 = (int(v) for v in act.frame_range)
        loop = act.name.endswith("-loop")
        # 반복 동작은 마지막 프레임(=첫 프레임)을 빼서 GIF 가 끊김 없이 돈다
        frames = list(range(f0, f1 if loop else f1 + 1, STEP))
        paths = []
        for f in frames:
            sc.frame_set(f)
            p = os.path.join(OUT, f"_frame_{act.name}_{f:03d}.png")
            sc.render.filepath = p
            bpy.ops.render.render(write_still=True)
            paths.append(p)
        imgs = [Image.open(p).convert("P", palette=Image.ADAPTIVE) for p in paths]
        name = act.name.split("-")[0].lower()
        gif = os.path.join(OUT, f"anim_{name}.gif")
        hold = [] if loop else [600]  # 한 번짜리 동작은 마지막에 잠깐 멈춘다
        durations = [round(1000 * STEP / sc.render.fps)] * (len(imgs) - len(hold)) + hold
        imgs[0].save(gif, save_all=True, append_images=imgs[1:], duration=durations, loop=0, disposal=2)
        for p in paths:
            os.remove(p)
        print(f"[preview] {gif} ({len(imgs)} frames)")


main()

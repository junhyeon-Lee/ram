"""동작 GIF 의 모든 프레임을 번호와 함께 한 장의 PNG 로 펼친다 (움직임을 한눈에 확인하기 위한 시트).

실행:  python gif_sheet.py <anim.gif> <out.png> [--cols N] [--size PX]
  - 프레임 번호는 GIF 안의 순서(0부터)다. Blender 프레임 = 1 + 번호 × preview_anims.py 의 --step(기본 2).
  - Pillow 가 필요하다.
"""
import sys

from PIL import Image, ImageDraw

args = [a for a in sys.argv[1:] if not a.startswith("--")]
if len(args) < 2:
    sys.exit(__doc__)
opts = {"--cols": 6, "--size": 240}
for i, a in enumerate(sys.argv):
    if a in opts:
        opts[a] = int(sys.argv[i + 1])
        args = [x for x in args if x != sys.argv[i + 1]]
src, out = args[0], args[1]
cols, size = opts["--cols"], opts["--size"]

gif = Image.open(src)
frames = []
try:
    while True:
        frames.append(gif.convert("RGB").resize((size, size)))
        gif.seek(gif.tell() + 1)
except EOFError:
    pass

rows = (len(frames) + cols - 1) // cols
sheet = Image.new("RGB", (cols * size, rows * size), (255, 255, 255))
draw = ImageDraw.Draw(sheet)
for i, f in enumerate(frames):
    x, y = (i % cols) * size, (i // cols) * size
    sheet.paste(f, (x, y))
    draw.rectangle((x + 4, y + 4, x + 34, y + 20), fill=(20, 20, 24))
    draw.text((x + 8, y + 6), str(i), fill=(255, 255, 255))
sheet.save(out)
print(f"[sheet] {len(frames)} frames -> {out}")

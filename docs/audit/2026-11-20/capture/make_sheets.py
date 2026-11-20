"""raw 폴더의 <묶음>__<번호>__<라벨>.png 를 묶음별로 정리한다.
still_* · close_* (한 장짜리) 는 stills/ 로 그대로, seq_* 는 프레임을 나란히 붙여 motion/ 에 시트로.
사용: python make_sheets.py <audit 폴더>
"""
import os
import sys
from collections import defaultdict

from PIL import Image, ImageDraw

root = sys.argv[1]
raw = os.path.join(root, "raw")
groups = defaultdict(list)
for fn in sorted(os.listdir(raw)):
    if fn.endswith(".png") and "__" in fn:
        g, idx, label = fn[:-4].split("__")
        groups[g].append((int(idx), label, os.path.join(raw, fn)))

for g, items in sorted(groups.items()):
    items.sort()
    if len(items) == 1:
        Image.open(items[0][2]).convert("RGB").save(os.path.join(root, "stills", g + ".png"))
        print("still ", g)
        continue
    first = Image.open(items[0][2])
    square = first.width == first.height
    tw, th = (400, 400) if square else (640, 360)
    cols = 4
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * th), (20, 20, 24))
    d = ImageDraw.Draw(sheet)
    for i, (idx, label, path) in enumerate(items):
        im = Image.open(path).convert("RGB").resize((tw, th), Image.LANCZOS)
        x, y = (i % cols) * tw, (i // cols) * th
        sheet.paste(im, (x, y))
        d.rectangle((x + 4, y + th - 22, x + 110, y + th - 4), fill=(0, 0, 0))
        d.text((x + 8, y + th - 20), f"{idx + 1}/{len(items)}  {label}", fill=(255, 230, 120))
    sheet.save(os.path.join(root, "motion", g + ".png"))
    print("sheet ", g, len(items), sheet.size)

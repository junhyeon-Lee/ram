"""단계별 영상의 같은 순간(정지 컷)을 한 장으로 붙인다. 사용: python make_overview.py <out 폴더> <컷 번호 1~3> <out.png>"""
import os
import sys

from PIL import Image

out, which, dst = sys.argv[1], sys.argv[2], sys.argv[3]
files = sorted(f for f in os.listdir(os.path.join(out, "shots")) if f.endswith(f"_{which}.png"))
tw, th, cols = 640, 360, 4
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * th), (20, 20, 24))
for i, f in enumerate(files):
    im = Image.open(os.path.join(out, "shots", f)).convert("RGB").resize((tw, th), Image.LANCZOS)
    sheet.paste(im, ((i % cols) * tw, (i // cols) * th))
sheet.save(dst)
print("overview", len(files), sheet.size)

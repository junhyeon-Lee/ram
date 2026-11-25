"""Ram 모습의 진화: git 기록의 단계별 모델 렌더(앞 3/4 모습)를 꺼내 한 장으로 붙인다.
사용: python make_look_sheet.py <저장소> <out.png>
"""
import io
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

repo, out = sys.argv[1], sys.argv[2]
# (커밋, 날짜, 한 줄)
STAGES = [
    ("f62cbea", "11/05", "첫 로우폴리 모델"),
    ("481e5ac", "11/05", "주둥이 가시 제거"),
    ("2e08f0f", "11/05", "머리 1.3배, 다리 굵게"),
    ("2e3299b", "11/05", "기둥형 다리, 넓은 발"),
    ("c422de4", "11/05", "발목을 가늘게"),
    ("265ec46", "11/05", "팔 굵게·손, 꼬리 짧고 굵게"),
    ("0416b90", "11/05", "돌머리가 머리 모양을 따라"),
    ("ae23c2f", "11/05", "돌머리 꼭대기를 낮춤"),
    ("145a4f2", "11/05", "톱니 경계 무늬 되살림"),
    ("98460a3", "11/05", "돌머리 잿빛으로"),
    ("a368236", "11/11", "목 세움, 매끈한 돌머리"),
]
PATHS = ["docs/renders/latest/render_front34.png", "docs/renders/checkpoint_01/render_front34.png"]


def show(commit, path):
    r = subprocess.run(["git", "-C", repo, "show", f"{commit}:{path}"], capture_output=True)
    return r.stdout if r.returncode == 0 and r.stdout else None


font = None
for name in ("malgunbd.ttf", "malgun.ttf"):
    try:
        font = ImageFont.truetype(rf"C:\Windows\Fonts\{name}", 22)
        break
    except OSError:
        pass
tw, th, cap = 480, 480, 44
cols = 4
tiles = []
for commit, date, title in STAGES:
    data = None
    for p in PATHS:
        data = show(commit, p)
        if data:
            break
    if not data:
        print("없음", commit)
        continue
    im = Image.open(io.BytesIO(data)).convert("RGB")
    s = min(tw / im.width, th / im.height)
    im = im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)
    tile = Image.new("RGB", (tw, th + cap), (24, 24, 28))
    tile.paste(im, ((tw - im.width) // 2, (th - im.height) // 2))
    ImageDraw.Draw(tile).text((10, th + 8), f"{len(tiles) + 1}. {date} {title}", fill=(255, 230, 140), font=font)
    tiles.append(tile)
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * (th + cap)), (24, 24, 28))
for i, t in enumerate(tiles):
    sheet.paste(t, ((i % cols) * tw, (i // cols) * (th + cap)))
sheet.save(out)
print("sheet", len(tiles), sheet.size)

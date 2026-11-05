# Ram

박치기 공룡이 방에서 방으로 싸워 나가는 3D 근접 격투 로그라이크.
진행 방식은 하데스, 싸우는 손맛은 시푸에서 가져온다.

- 설계 문서: https://claude.ai/artifact/84osqWgQkDQugsrKgKLPxC
- 엔진: Godot 4 · 플랫폼: Windows PC
- 아트: 로우폴리 + 단색 면 + 약한 명암

## 폴더

| 경로 | 내용 |
|---|---|
| `tools/blender/build_dino.py` | 주인공 모델을 만드는 Blender 파이썬 스크립트 |
| `assets/characters/ram/` | 스크립트로 만든 주인공 모델 (`dino.glb` → Godot, `dino.blend` → Blender) |
| `docs/renders/` | 렌더 사진 (`latest/` 최신, `checkpoint_*/` 체크포인트 기록) |

## 주인공 모델 다시 만들기

Blender 없이 파이썬 모듈 `bpy`로 돌린다 (Python 3.13).

```bash
python -m venv .venv
.venv/bin/pip install bpy          # Windows: .venv\Scripts\pip install bpy
.venv/bin/python tools/blender/build_dino.py out
```

`out/`에 `dino.blend`, `dino.glb`, 렌더 사진(`render_*.png`)이 생긴다.
설치된 Blender로 돌려도 된다: `blender -b -P tools/blender/build_dino.py -- out`

### 색 바꾸기

스크립트 맨 위 `PALETTE`만 바꾸면 된다. `accent` 슬롯(등 줄무늬·돌기)은 빌드에 따라 게임에서 바꿀 색이다.

## 체크포인트

- **checkpoint_01** — 첫 주인공 모델. 돌머리가 몸과 한 덩어리, 반달 동심원 눈, 짧은 주둥이와 입선, 차콜 바탕 + 빌드 색 슬롯. 삼각형 약 2,700개.
- 이후 — 주둥이 가시 제거(돌기는 돌머리 테두리에만). 최신 렌더는 `docs/renders/latest/`.
- 이후 — 머리 쪽(머리·주둥이·돌머리·눈·입선·돌기)을 목 끝 기준 1.3배(`HEAD_SCALE`), 다리를 약 1.35배 굵게.
- 이후 — 다리를 듬직하게: 곧고 굵은 기둥형, 넓은 발을 무게중심 아래로, 양발 간격 넓힘(`LEG_X`). 발목은 가늘게 좁혀 무다리 느낌을 덜어냄.

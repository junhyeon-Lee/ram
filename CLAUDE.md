# Ram — 작업 안내

박치기 공룡 3D 로그라이크(Godot 4, Windows). 설계 결정은 `docs/design.md`, 실행 방법은 `README.md`, 이어받을 일은 `docs/handoff.md`.

## 모델 작업 순서

```bash
python -m venv .venv && .venv/bin/pip install bpy pillow   # bpy 는 Python 3.13
.venv/bin/python tools/blender/build_dino.py out             # 정지 모델 + 렌더
.venv/bin/python tools/blender/rig_dino.py out/dino.blend out  # 뼈대·동작 → ram_rigged.glb
.venv/bin/python tools/blender/preview_anims.py out/ram_rigged.blend out   # 동작 GIF
.venv/bin/python tools/blender/build_helpers.py out          # 조력자 4인
```

모델을 바꾸면 `rig_dino.py` 도 다시 돌려 `assets/characters/ram/` 의 `dino.*` 와 `ram_rigged.*` 를 함께 갱신한다(서로 어긋나면 안 된다). `docs/renders/latest/` 렌더도 같이 바꾼다.

## Godot 작업

- Godot 4.7. 저장소 루트가 프로젝트 루트다. `docs/`·`tools/` 는 `.gdignore` 로 제외된다.
- 게임 코드를 바꾸면 헤드리스 점검을 돌려 `SMOKE TEST: PASS` 를 확인한다:
  `godot --headless --path . --fixed-fps 120 --script tools/godot/smoke_test.gd`
- 키 배치를 바꾸면 `tools/godot/setup_input.gd` 를 고치고 다시 돌린다(`project.godot` 를 손으로 고치지 않는다).
- Ram 모델은 +Z 를 보고 들어온다(플레이어에서 180° 돌림). 동작 속 root 뼈 회전은 Godot root motion 회전값 대신 `_root_yaw()` 로 읽는다(180° 에서 값이 튐).
- `.import`·`.uid` 파일은 커밋한다. `.godot/` 는 커밋하지 않는다.
- 걷기·달리기 동작을 바꾸면 `tools/godot/measure_feet.gd` 로 발 속도를 다시 재서 `player.gd` 의 `RUN_FOOT_SPEED`·`WALK_FOOT_SPEED` 를 고친다.

## 디자인을 바꿀 때

- `docs/design.md` 의 "주인공 디자인 규칙"을 먼저 읽는다. 돌머리·눈은 사용자와 여러 번 맞춘 결과다.
- 바꾸기 전과 후를 나란히 렌더해 보여 주고(얼굴 확대 + 옆모습), 고른 것만 반영한다. 시안은 저장소 밖에서 만든다.
- 두개도스·램펄드 등 기존 캐릭터 디자인을 그대로 따라 만들지 않는다.
- `bmesh` 는 `bpy` 다음에 import 한다.

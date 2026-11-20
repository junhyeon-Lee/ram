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
- 클라우드·PC 세션이 같은 `main` 에 올린다. 작업을 시작하거나 게임을 띄우기 전에 `git pull` 한다.
- 화면을 눈으로 확인할 때는 `tools/godot/capture_frame.gd` 로 캡처한다(헤드리스는 그리지 않는다).
- 게임 코드를 바꾸면 헤드리스 점검을 돌려 `SMOKE TEST: PASS` 를 확인한다:
  `godot --headless --path . --fixed-fps 120 --script tools/godot/smoke_test.gd`
- 출근길 장면(`game/commute/`)을 바꾸면 `tools/godot/commute_test.gd` 도 돌려 `COMMUTE TEST: PASS` 를 확인한다. 장면 모델을 바꾸면 `tools/blender/build_commute.py export assets/environments/commute/commute.glb`, `tools/blender/build_home.py export assets/environments/home/home.glb` 로 다시 내보낸다(집은 같은 폴더에 `egg.glb` — 아래 껍질 `EggBase` + 조각 `Shard_NN` — 도 같이 나온다. 게임 코드의 위치 상수 — 회사 정문 `TOWER_Y`, 광장 `PLAZA`, 알 자리 `EGG_POS`, 걸을 수 있는 영역 `WALK_RECTS`·직원 자리 `NPCS` — 와 어긋나면 안 된다).
- 키 배치를 바꾸면 `tools/godot/setup_input.gd` 를 고치고 다시 돌린다(`project.godot` 를 손으로 고치지 않는다).
- Ram 모델은 +Z 를 보고 들어온다(플레이어에서 180° 돌림). 동작 속 root 뼈 회전은 Godot root motion 회전값 대신 `_root_yaw()` 로 읽는다(180° 에서 값이 튐).
- `.import`·`.uid` 파일은 커밋한다. `.godot/` 는 커밋하지 않는다.
- 걷기·달리기 동작을 바꾸면 `tools/godot/measure_feet.gd` 로 발 속도를 다시 재서 `player.gd` 의 `RUN_FOOT_SPEED`·`WALK_FOOT_SPEED` 를 고친다.

## 동작을 바꿀 때

- `.claude/skills/ram-motion` 스킬을 먼저 읽는다(뼈·축 규칙, 만들기 → GIF·프레임 시트 확인 → 게임 연결 순서, 함정).

## 디자인을 바꿀 때

- `docs/design.md` 의 "주인공 디자인 규칙"을 먼저 읽는다. 돌머리·눈은 사용자와 여러 번 맞춘 결과다.
- 바꾸기 전과 후를 나란히 렌더해 보여 주고(얼굴 확대 + 옆모습 + 뒤·게임 카메라), 고른 것만 반영한다. 시안은 저장소 밖에서 만든다. 나란히 찍기는 `tools/godot/compare_models.gd`(`--game` 이면 게임 조명).
- 머리 위치를 바꾸면 `build_dino.py` 와 `rig_dino.py` 의 `HEAD_LIFT` 를 같이 고친다(뼈 위치가 따라가야 한다).
- 두개도스·램펄드 등 기존 캐릭터 디자인을 그대로 따라 만들지 않는다.
- `bmesh` 는 `bpy` 다음에 import 한다.

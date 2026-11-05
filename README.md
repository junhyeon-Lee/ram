# Ram

쉬고 싶은 박치기 공룡 Ram 이 사직서를 내러 회사 9층 인사팀까지 머리로 깨부수며 올라가는 3D 근접 격투 로그라이크.
진행 방식은 하데스, 싸우는 손맛은 시푸에서 가져온다. 한 판은 출근 시각부터 오전 9시까지.

- **스토리:** AI 에 밀려 지하 1층으로 쫓겨난 개발자 Ram. 사원증으로 엘리베이터도 못 타서 계단으로 층마다 깨부수며 올라간다. 잡히면 끌려가 일하고, 다음 날 아침 다시 출근.
- **성장:** 일해서 번 돈으로 집을 꾸며 더 일찍 일어나고(시간), 지하 동료들이 몸을 사이버웨어로 개조해 준다(능력치).
- **특징:** 시간 감속 능력 '산재비스탄', 조력자 4인과 합체 필살기(두루치기·양치기·메치기·날치기).

- 설계 결정: [`docs/design.md`](docs/design.md) (원본 문서: https://claude.ai/artifact/84osqWgQkDQugsrKgKLPxC)
- 엔진: Godot 4 · 플랫폼: Windows PC
- 아트: 로우폴리 + 단색 면 + 약한 명암

## 폴더

| 경로 | 내용 |
|---|---|
| `tools/blender/build_dino.py` | 주인공 모델을 만드는 Blender 파이썬 스크립트 |
| `tools/blender/rig_dino.py` | 모델에 뼈대·가중치·기본 동작을 넣는 스크립트 |
| `tools/blender/preview_anims.py` | 동작마다 미리보기 GIF 를 만드는 스크립트 |
| `tools/blender/build_helpers.py` | 조력자 4인 첫 디자인 모델 스크립트 |
| `assets/characters/ram/` | 주인공 모델. `dino.*` 정지 모델, `ram_rigged.*` 뼈대·동작 포함 (Godot 에는 `ram_rigged.glb`) |
| `assets/characters/helpers/` | 조력자 모델 (`crane`·`sheep`·`catfish`·`flyfish` .glb/.blend) |
| `docs/design.md` | 확정한 설계 결정 (스토리·하루의 흐름과 성장·건물·조작·카메라·디자인 규칙·산재비스탄·빌드와 조력자) |
| `docs/renders/` | 렌더 사진: `latest/` 최신 · `checkpoint_01/` 첫 모델 · `helpers/` 조력자 · `explorations/` 비교 시안 |

## 주인공 모델 다시 만들기

Blender 없이 파이썬 모듈 `bpy`로 돌린다 (bpy 5.2 는 Python 3.13 필요).

```bash
python -m venv .venv
.venv/bin/pip install bpy          # Windows: .venv\Scripts\pip install bpy
.venv/bin/python tools/blender/build_dino.py out
```

`out/`에 `dino.blend`, `dino.glb`, 렌더 사진(`render_*.png`)이 생긴다.
설치된 Blender로 돌려도 된다: `blender -b -P tools/blender/build_dino.py -- out`

### 뼈대·동작 넣기

```bash
.venv/bin/python tools/blender/rig_dino.py out/dino.blend out
```

`out/ram_rigged.glb`에 뼈대 18개와 동작 11개가 들어간다.

| 동작 | 내용 |
|---|---|
| `Idle-loop` · `Walk-loop` · `Run-loop` | 대기 · 걷기 · 달리기 |
| `Attack_Slam` | 머리를 위로 들었다가 내리찍기 |
| `Attack_Uppercut` | 낮게 숙였다가 아래에서 위로 올려치기 |
| `Attack_Hook` | 오른쪽 위로 들었다가 왼쪽 아래로 후려치기 |
| `Parry_Tail` | 한 바퀴 돌며 꼬리로 쓸어내기 |
| `Backstep` | 앞다리로 밀며 뒤로 0.65m |
| `Dash` | 뒷다리로 차며 앞으로 1.0m |
| `Dash_Left` · `Dash_Right` | 옆으로 0.8m |

대시·백스텝·패링은 `root` 뼈가 실제로 움직인다(Godot 에서 root motion 으로 쓸 수 있다).
이름 끝의 `-loop`는 Godot가 반복 재생으로 가져오라는 표시다.

동작 미리보기 GIF (Pillow 필요):

```bash
.venv/bin/pip install pillow
.venv/bin/python tools/blender/preview_anims.py out/ram_rigged.blend out
```

최신 GIF: `docs/renders/latest/anim_*.gif` (동작마다 하나)

### 색 바꾸기

스크립트 맨 위 `PALETTE`만 바꾸면 된다. `accent` 슬롯(등 줄무늬·돌기)은 빌드에 따라 게임에서 바꿀 색이다.

## 조력자 (빌드마다 하나, 합체 필살기)

| 빌드 | 조력자 | 합체 필살기 | 성격 |
|---|---|---|---|
| 1 | 두루미 | 두루치기 | 공중·낙하 |
| 2 | 양 | 양치기 | 방어·패링 |
| 3 | 메기 | 메치기 | 잡기·던지기 |
| 4 | 날치 | 날치기 | 속도·대시 |

첫 디자인: `.venv/bin/python tools/blender/build_helpers.py out` → `docs/renders/helpers/lineup.png`(Ram 과 나란히)

## 작업 기록

| 단계 | 내용 |
|---|---|
| 체크포인트 1 | 첫 주인공 모델: 돌머리 한 덩어리, 반달 동심원 눈, 짧은 주둥이와 입선, 차콜 바탕 + 빌드 색 슬롯 (`docs/renders/checkpoint_01/`) |
| 비율 | 주둥이 가시 제거, 머리 쪽 1.3배(`HEAD_SCALE`), 기둥형 다리 + 가는 발목 + 넓은 발(`LEG_X`), 팔 굵게, 꼬리 짧고 굵게 |
| 돌머리 | 테두리부터 위로 좁아지게, 꼭대기 낮춤, 체크포인트 1의 톱니 경계 무늬 유지(`PAINT_DOME_*`), 잿빛 |
| 뼈대·동작 | 뼈 18개, 동작 11개 (`ram_rigged.glb`), 동작 GIF |
| 조력자 | 두루미·양·메기·날치 첫 디자인 |
| 기획 | 스토리 'Ram은 쉬고 싶다'(회사 편), 하루의 흐름과 두 갈래 성장, 시계 2배속, 9층 인사팀 따귀 이벤트, 산재비스탄, 사이버웨어 개조 (`docs/design.md`) |

자세한 변경은 `git log` 에 있다.

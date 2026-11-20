---
name: ram-motion
description: Ram(박치기 공룡 주인공)의 동작을 만들거나 고치는 순서 — 걷기·달리기·박치기·패링·대시·백스텝 같은 애니메이션을 tools/blender/rig_dino.py 에서 수치로 짜고, GIF·프레임 시트로 확인하고, Godot 게임에 연결해 스모크 테스트까지. "동작 추가", "모션 다듬어", "걷기가 어색해", "박치기 타격감", "발이 미끄러져", "꼬리가 뻣뻣해", "새 공격 만들어", "애니메이션 고쳐"처럼 Ram 이 어떻게 움직이는지에 관한 요청이면 rig_dino.py 를 열기 전에 꼭 이 스킬부터 읽는다. 모델의 모양·색(디자인)을 바꾸는 일은 이 스킬이 아니라 CLAUDE.md '디자인을 바꿀 때'를 따른다.
---

# Ram 동작 만들기·다듬기

Ram 의 동작은 손으로 찍은 키프레임이 아니라 **파이썬 수치**다. `tools/blender/rig_dino.py` 의 `*_keys()` 함수가
뼈마다 회전 각도를 적고, 스크립트가 뼈대·가중치·동작을 한 번에 만들어 `ram_rigged.glb` 로 내보낸다.
그래서 동작을 고친다는 것은 "숫자를 고치고 → 다시 만들고 → 눈으로 보고 → 게임에서 확인"의 반복이다.
눈으로 보는 단계를 건너뛰면 숫자는 맞는데 움직임이 이상한 결과가 나온다. 이 순서를 지킨다.

## 0. 시작 전

1. `git pull` — 클라우드·PC 세션이 같은 `main` 에 올린다.
2. 읽는다: `docs/design.md` 의 '동작 (Ram)'과 '모션·전투 다듬기', `docs/references/motion.md`(레퍼런스와 "Ram 에 적용할 점").
   새 동작이면 motion.md 에 해당 절이 있는지 보고, 없으면 레퍼런스를 먼저 찾아 그 문서에 더한다(영상·이미지는 링크만).
3. bpy 가 되는 Python(3.13)을 확인한다: `python -c "import bpy; print(bpy.app.version_string)"`.
   없으면 CLAUDE.md '모델 작업 순서'대로 가상환경을 만든다(Pillow 도 같이). 저장소 밖에 이미 만들어 둔 가상환경이 있을 수 있으니 handoff.md 를 본다.

## 1. 규칙 (rig_dino.py)

**뼈 18개**
```
root ─ pelvis ─┬ spine ─ neck ─ head
               │        └ arm.L/R ─ forearm.L/R
               ├ thigh.L/R ─ shin.L/R ─ foot.L/R
               └ tail.1 ─ tail.2 ─ tail.3
```

**좌표와 부호** (Blender 기준, 30fps, 프레임은 1부터)
- 정면은 **-Y**, 왼쪽은 **+X**, 위는 +Z.
- 각도는 월드 축으로 적는다. `X` = 끄덕임·다리 앞뒤, `Z` = 좌우로 틀기, `Y` = 갸웃(롤).
- `X` + 각도: 앞을 보는 뼈(몸통·목·머리)는 **숙이고**, 다리는 **뒤로 차고**, 꼬리는 **위로 든다**.
- `Z` + 각도: 앞을 보는 뼈가 캐릭터의 **왼쪽**으로 돈다.

**키 하나 = `(프레임, 자세, root_loc)`**
- 자세는 `{뼈: [(축, 각도), ...]}`. 적지 않은 뼈는 기본 자세로 키가 들어간다(동작마다 완결).
- `merge(a, b)` 로 자세를 합친다. 웅크림은 `CROUCH` 를 합쳐 쓴다.
- `root_loc = (x, y, z)`: x·y 는 **root 뼈**로 가서 게임에서 캐릭터 이동(root motion)이 된다. z 는 **골반**으로 간다.
  - 높이를 root 에 주면 Godot 가 root motion 으로 떼어 가서 화면에서 사라진다. 그래서 위아래는 늘 골반이다. 자세 안에서 `"_pelvis": (x, y, z)` 로 골반을 옮길 수도 있다.
- 몸 전체를 제자리에서 돌릴 때만 `"root": [(Z, 각도)]`. 공중제비 같은 회전은 `pelvis` 에 준다.
- 한 번에 90° 넘게 돌리면 쿼터니언 보간이 반대로 돌 수 있다. **60° 간격**으로 키를 둔다.

**이름**
- 반복 동작은 `-loop` 로 끝낸다(`Run-loop`). Godot 가 반복으로 가져오고, 게임 코드에서는 `Run` 으로 부른다.
- 반복 동작의 마지막 키는 첫 키와 같은 자세로 닫는다.
- 걷기·달리기는 `gait_keys()` 의 숫자(보폭 `swing`, 출렁임 `bob`, 좌우 실림 `lateral`, 비틀림 `twist`, 꼬리 `tail_sway` …)만 바꾼다.
- 공격은 맞은 자리에 서서 끝난다(root 가 뒤로 돌아오지 않는다).
- 새 동작은 `ACTIONS` 목록에 넣어야 만들어진다.

**좋은 동작의 뼈대** (motion.md 요약)
- 공격: 예비 동작(짧게) → 타격 프레임(가장 또렷한 자세) → 맞은 뒤 목·꼬리가 한 박자 늦게 출렁(`quake`) → 가라앉음(`settle`) → 회복.
- 꼬리는 뿌리에서 끝으로 갈수록 늦게, 크게 따라온다. 머리(돌머리)는 화면 중심이라 덜 흔들리게.

## 2. 만들기

모델 모양을 안 바꿨다면 저장소의 정지 모델을 그대로 쓴다. 출력은 저장소 밖이나 `out/`(커밋하지 않음)에 둔다.

```bash
python tools/blender/rig_dino.py assets/characters/ram/dino.blend out
```

`out/ram_rigged.glb`, `out/ram_rigged.blend`, 동작별 대표 프레임 `out/anim_*.png` 가 생긴다.
새 동작의 대표 프레임도 찍히게 `main()` 의 `shots` 목록에 `(이름, 프레임)`을 더한다(보통 타격 프레임).

## 3. 눈으로 확인 (건너뛰지 않는다)

```bash
python tools/blender/preview_anims.py out/ram_rigged.blend out --only Attack_Shove,Run-loop
python .claude/skills/ram-motion/scripts/gif_sheet.py out/anim_attack_shove.gif out/sheet_attack_shove.png
```

- `--only` 로 바꾼 동작만 렌더한다(전부 하면 몇 분 걸린다). GIF 이름은 소문자, `-loop` 는 빠진다.
- GIF 는 사용자가 보는 것이고, **시트 PNG 는 내가 보는 것**이다. `gif_sheet.py` 가 모든 프레임을 번호와 함께 한 장으로 펼친다. 시트를 읽고 프레임마다 확인한다:
  - 타격 프레임의 자세가 또렷한가, 돌머리가 상대 가슴 높이를 향하는가(너무 숙이면 땅을 박는다)
  - 발이 바닥을 뚫거나 뜨지 않는가, 몸이 바닥 아래로 내려가지 않는가
  - 꼬리·목이 늦게 따라오는가, 시작과 끝 자세가 이어지는가
  - 회전이 중간에 반대로 돌지 않는가
- 고치기 전 GIF 는 `docs/renders/latest/anim_*.gif` 에 있다. 전·후를 같이 사용자에게 보여 준다.

## 4. 게임에 넣고 확인

1. `out/ram_rigged.glb`·`.blend` 를 `assets/characters/ram/` 에, 다시 만든 GIF·`anim_*.png` 를 `docs/renders/latest/` 에 복사한다.
2. 다시 가져온다: `godot --headless --path . --import`
3. **걷기·달리기를 바꿨으면** 발 속도를 다시 잰다. 안 맞으면 발이 미끄러진다.
   ```bash
   godot --headless --path . --script tools/godot/measure_feet.gd
   ```
   `Run`·`Walk` 줄의 `stance foot speed` 를 `game/player/player.gd` 의 `RUN_FOOT_SPEED`·`WALK_FOOT_SPEED` 에 넣는다.
   `lowest ankle` 은 발목 뼈 높이다(대기 자세 0.08m). 0 아래로 내려가는 웅크림은 게임에서 발 IK 가 다리를 접어 받쳐 주지만, 걷기·달리기에서 낮게 나오면 동작을 고친다.
4. **공격을 바꾸거나 더했으면** `player.gd` 를 맞춘다:
   - `ATTACKS[이름]["hits"]` = 맞는 순간(초) = **(타격 프레임 − 1) / 30**. 타격 프레임을 옮기면 이 숫자도 옮긴다.
   - `stop`(히트스톱), `shake`(화면 흔들림), `kick`(날리는 세기), `up`(띄우는 비율)
   - Space 로 번갈아 나오게 하려면 `ATTACK_VARIANTS`, 콤보 연결이면 `COMBO_LINKS`
   - 제자리에서 돌고 원래 방향으로 끝나는 동작은 `VISUAL_SPIN_ACTIONS` (카메라가 같이 돌지 않게)
5. 점검한다. `SMOKE TEST: PASS` 가 나와야 한다. 새 동작에는 `tools/godot/smoke_test.gd` 에 점검 항목을 더한다(재생되는지, 맞는지, 이동 거리).
   ```bash
   godot --headless --path . --fixed-fps 120 --script tools/godot/smoke_test.gd
   ```
6. 화면에서 볼 것이 있으면 `tools/godot/capture_frame.gd` 로 찍는다. 사용자가 직접 해 보게 하려면 `git pull` 뒤 에디터 없이 띄운다(README).

## 5. 마무리

- 문서: README 의 동작 표, `docs/design.md` '동작 (Ram)'·'모션·전투 다듬기', `docs/handoff.md` '열려 있는 것'. 설계 결정이면 원본 설계 문서에도.
- 커밋에는 스크립트·`assets/characters/ram/ram_rigged.*`·`docs/renders/latest/`·`player.gd`·`smoke_test.gd`·문서를 함께 넣는다. 스크립트와 glb 가 어긋나면 다음 세션이 다시 만들 때 결과가 달라진다.

## 함정

| 증상 | 원인과 처리 |
|---|---|
| 높이 변화가 게임에서 안 보임 | root 에 준 높이는 root motion 으로 빠진다 → 골반(`root_loc` 의 z, `_pelvis`) |
| 회전이 중간에 거꾸로 돈다 | 키 사이 90° 초과 → 60° 간격 |
| 게임에서 회전 동작이 180° 근처에서 튄다 | Godot root motion 회전값을 쓰지 않는다. `player.gd` 의 `_root_yaw()` 로 읽는다 |
| 박치기가 빗나가거나 늦게 맞는다 | `ATTACKS` 의 `hits` 가 타격 프레임과 안 맞음, 또는 돌머리 높이. 판정은 head 뼈에서 0.25m 앞, 반지름 0.75m |
| 머리·목 동작이 어긋난다 | `build_dino.py` 와 `rig_dino.py` 의 `HEAD_LIFT` 가 다르다. 머리 위치는 두 파일을 같이 고친다 |
| 달릴 때 발이 미끄러진다 | `measure_feet.gd` 를 다시 재서 `RUN_FOOT_SPEED`·`WALK_FOOT_SPEED` 갱신 |
| 게임에 예전 동작이 나온다 | `--import` 를 안 했거나, `git pull` 을 안 했다 |
| 사람형 동작 라이브러리를 그대로 쓰고 싶다 | Ram 은 등이 수평이고 꼬리가 있는 자체 뼈대라 입힐 수 없다. 움직임 참고로만 본다 |

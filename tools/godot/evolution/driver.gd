## Ram 진화 과정 녹화용: 어느 시점의 저장소에서든 시험용 층을 띄워, 정해진 같은 키 입력을 그대로 재생한다.
## 화면 아래에 단계 이름과 지금 누르고 있는 키를 보여 준다 (같은 입력에 판마다 어떻게 반응하는지 비교).
## 실행: godot --path <그 시점의 저장소> --fixed-fps 60 --resolution 1280x720 --write-movie <out.avi|ogv>
##        --script driver.gd -- "<단계 제목>"
## 게임 내부 변수는 건드리지 않는다. 입력 이름(move_forward 등)만 쓴다 — 첫 Godot 판부터 같다.
extends SceneTree

# [시작 초, 끝 초, 입력 이름]  — 모든 판에 똑같이 재생한다
const TIMELINE := [
	[1.2, 2.1, "move_forward"],                                   # 앞으로 달리기
	[2.6, 3.4, "turn_left"], [3.5, 4.3, "turn_right"],           # 제자리에서 좌우로 돌기
	[4.8, 4.86, "attack"], [5.15, 5.21, "attack"], [5.5, 5.56, "attack"], [5.85, 5.91, "attack"],   # 서서 Space 네 번
	[7.6, 7.66, "backstep"],                                      # 백스텝
	[8.6, 8.66, "guard"],                                         # 패링(E)
	[10.2, 11.9, "move_forward"],                                 # 위키를 누른 채
	[10.5, 10.56, "attack"], [10.85, 10.91, "attack"], [11.2, 11.26, "attack"], [11.55, 11.61, "attack"],   # Space 네 번
	[13.4, 14.0, "attack"],                                       # Space 길게
	[15.4, 16.4, "turn_left"],                                    # 크게 돌아서
	[16.5, 17.5, "move_forward"],                                 # 달리다가
	[17.1, 17.16, "attack"],                                      # 달리는 중 Space
	[18.6, 18.66, "sanjae"],                                      # 산재비스탄(R)
	[19.0, 20.2, "move_forward"], [19.6, 19.66, "attack"],        # 느려진 시간 속에서 달리고 치기
]
const END := 22.5
const KEY_NAMES := {"move_forward": "↑", "move_back": "↓", "turn_left": "←", "turn_right": "→",
		"attack": "Space", "guard": "E", "backstep": "Shift", "sanjae": "R"}
const KEY_ORDER := ["turn_left", "move_forward", "turn_right", "attack", "backstep", "guard", "sanjae"]

var _t := 0.0
var _title := ""
var _keys: Label
var _held := {}
var _flash := {}          # 짧게 누른 키도 화면에서 0.25초는 보이게
const SHOT_AT := [5.7, 11.4, 17.0]
var _shot_prefix := ""
var _shots_done := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_title = args[0] if args.size() > 0 else ""
	_shot_prefix = args[1] if args.size() > 1 else ""
	root.add_child(load("res://game/main.tscn").instantiate())
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.55)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -64
	layer.add_child(bar)
	var title := Label.new()
	title.text = _title
	title.add_theme_font_size_override("font_size", 26)
	title.position = Vector2(20, 14)
	bar.add_child(title)
	_keys = Label.new()
	_keys.add_theme_font_size_override("font_size", 26)
	_keys.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_keys.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_keys.offset_left = -520
	_keys.offset_right = -20
	_keys.offset_top = -18
	bar.add_child(_keys)


func _process(delta: float) -> bool:
	_t += delta / Engine.time_scale            # 산재비스탄으로 시간이 느려져도 입력 시각은 실제 시간으로
	var want := {}
	for seg in TIMELINE:
		if _t >= seg[0] and _t < seg[1]:
			want[seg[2]] = true
	for a in KEY_NAMES:
		if want.has(a) and not _held.has(a):
			if InputMap.has_action(a):
				Input.action_press(a)
			_held[a] = true
			_flash[a] = _t + 0.25
		elif not want.has(a) and _held.has(a):
			if InputMap.has_action(a):
				Input.action_release(a)
			_held.erase(a)
	var shown := []
	for a in KEY_ORDER:
		if _held.has(a) or float(_flash.get(a, 0.0)) > _t:
			shown.append(KEY_NAMES[a])
	_keys.text = "   ".join(shown)
	# 확인용 정지 컷 (둘째 인자로 경로 앞부분을 주면): 서서 연타 중, 위키 누른 채 연타 중, 달리는 중
	if _shot_prefix != "":
		for i in SHOT_AT.size():
			if _t >= SHOT_AT[i] and not _shots_done.has(i):
				_shots_done[i] = true
				root.get_texture().get_image().save_png("%s_%d.png" % [_shot_prefix, i + 1])
	if _t >= END:
		quit()
		return true
	return false

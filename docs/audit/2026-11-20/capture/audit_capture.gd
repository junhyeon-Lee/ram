## 평가용 증거 뽑기 (집·출근길): 알 깨기, 정지 화면, 동작별 연속 프레임, Ram 가까이 보기.
## 실행: godot --path <repo> --fixed-fps 60 --resolution 1280x720 --script audit_capture.gd -- <raw 폴더>
## 파일 이름: <묶음>__<번호>__<라벨>.png  (make_sheets.py 가 묶음별로 시트를 만든다)
extends SceneTree

const LEN := {"Attack_RearSlam": 1.13, "Attack_LowCharge": 0.9, "Attack_FlankButt": 1.0, "Attack_Shove": 1.4, "Attack_Hook": 1.0,
		"Attack_Uppercut": 1.0, "Parry_Tail": 1.07, "Backstep": 0.67, "Dash": 0.6}

var _s: Node
var _out := ""
var _hatch_at: Array = []
var _hi := 0
var _after := 0.0
var _jobs: Array = []
var _ji := -1
var _f := 0
var _close: Camera3D


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	_s = load("res://game/commute/commute.tscn").instantiate()
	root.add_child(_s)
	for i in 13:
		_hatch_at.append(0.3 + 0.2 * i)
	_close = Camera3D.new()
	_close.fov = 40.0
	root.add_child(_close)

	# ---- 집 (먼저 다 찍는다: 바깥으로 나가면 집으로 돌아오지 않는다)
	_still("still_home_2_idle", 0, Vector2(0.45, -0.35), Vector2(0.9, 0.35), 260)
	_still("still_home_3_door", 0, Vector2(2.2, -1.5), Vector2(0.77, -0.64))
	_still("still_home_4_front_left", 0, Vector2(-1.4, 0.8), Vector2(-0.6, 0.8))
	_still("still_home_5_back_wall", 0, Vector2(0.6, -2.5), Vector2(-1.0, 0.1))
	_jobs.append({"name": "seq_home_run", "stage": 0, "pos": Vector2(-0.8, 0.4), "face": Vector2(1, 0), "keys": ["turn_right"],
			"frames": [10, 15, 20, 25, 30, 35, 40, 45], "crop": 520})
	for a in ["Attack_RearSlam", "Attack_LowCharge", "Attack_FlankButt", "Attack_Shove", "Attack_Hook", "Attack_Uppercut", "Parry_Tail", "Backstep", "Dash"]:
		_jobs.append({"name": "seq_home_" + a, "stage": 0, "pos": Vector2(-0.2, 0.2), "face": Vector2(1, 0), "action": a,
				"frames": _spread(LEN[a]), "crop": 520})
	_closeup("close_home_1_front", 0, Vector2(0.6, -0.2), Vector2(0.3, 1.0), Vector3(1.3, 1.0, 2.2))
	_closeup("close_home_2_back", 0, Vector2(0.6, -0.2), Vector2(0.3, 1.0), Vector3(-1.2, 1.3, -2.3))

	# ---- 바깥
	_still("still_road_1_out", 1, Vector2(-2.7, -7.0), Vector2(0.72, -0.69))
	_still("still_road_2_village", 1, Vector2(0.0, -12.0), Vector2(0, -1))
	_still("still_road_3_village_far", 1, Vector2(-0.6, -19.0), Vector2(0, -1))
	_still("still_road_4_boundary", 1, Vector2(0.0, -23.5), Vector2(0, -1))
	_still("still_road_5_plaza", 1, Vector2(0.5, -30.0), Vector2(0, -1), 200)
	_jobs.append({"name": "seq_road_turnaround", "stage": 1, "pos": Vector2(0.0, -10.0), "face": Vector2(0, -1), "keys": ["move_forward"],
			"switch": 40, "keys2": ["move_back"], "frames": [36, 40, 43, 46, 49, 52, 56, 62], "crop": 520})
	for a in ["Attack_RearSlam", "Dash"]:
		_jobs.append({"name": "seq_road_" + a, "stage": 1, "pos": Vector2(0.0, -11.0), "face": Vector2(0, -1), "action": a,
				"frames": _spread(LEN[a]), "crop": 520})
	_closeup("close_road_1_front", 1, Vector2(0.0, -12.0), Vector2(0, -1), Vector3(1.5, 1.0, -2.3))
	_closeup("close_road_2_side", 1, Vector2(0.0, -12.0), Vector2(0, -1), Vector3(2.9, 0.9, 0.0))
	_closeup("close_road_3_back", 1, Vector2(0.0, -12.0), Vector2(0, -1), Vector3(-1.4, 1.3, 2.4))
	_closeup("close_road_4_top", 1, Vector2(0.0, -12.0), Vector2(0, -1), Vector3(0.3, 3.4, 1.0))
	# 광장 경계에서 정문까지 달리며 줌 아웃 (마지막: 도착 뒤 카메라가 다 물러난 화면)
	_jobs.append({"name": "seq_road_zoomout", "stage": 1, "pos": Vector2(0.0, -22.0), "face": Vector2(0, -1), "keys": ["move_forward"],
			"frames": [0, 40, 80, 120, 160, 200, 250, 420], "crop": 0})


func _spread(seconds: float) -> Array:
	var out := []
	for i in 8:
		out.append(int(seconds * 60.0 * i / 8.0) + 2)
	return out


func _still(n: String, stage: int, pos: Vector2, face: Vector2, settle := 150) -> void:
	_jobs.append({"name": n, "stage": stage, "pos": pos, "face": face, "settle": settle, "frames": [0], "crop": 0})


func _closeup(n: String, stage: int, pos: Vector2, face: Vector2, off: Vector3) -> void:
	_jobs.append({"name": n, "stage": stage, "pos": pos, "face": face, "frames": [3], "crop": 0, "close": off})


func _process(d: float) -> bool:
	if _hi < _hatch_at.size():                       # 알 깨기: 시간에 맞춰 화면 전체
		if not _s.hatching:
			_after += d
		if _s._hatch_t + _after >= _hatch_at[_hi]:
			_save("seq_home_hatch", _hi, "%.1fs" % _hatch_at[_hi], 0)
			if _hi == 1:
				_save("still_home_1_egg", 0, "egg", 0)
			_hi += 1
		return false
	if _ji < 0 or _f > int(_job().get("settle", 120)) + int(_job().frames[-1]) + 2:
		for k in ["move_forward", "move_back", "turn_left", "turn_right"]:
			Input.action_release(k)
		_s.cam.make_current()
		_ji += 1
		_f = 0
		if _ji >= _jobs.size():
			quit()
			return true
	var j := _job()
	var settle: int = j.get("settle", 120)
	if _f == 0:
		if int(j.stage) != _s.stage:
			_s._enter(j.stage)
		var origin: Vector3 = _s.HOME_ORIGIN if int(j.stage) == 0 else Vector3.ZERO
		_s.ram.position = origin + Vector3(j.pos.x, 0.04, j.pos.y)
		_s.ram.velocity = Vector3.ZERO
		_s.ram.rotation.y = atan2(-j.face.x, -j.face.y)
		if j.has("close"):
			_close.global_position = _s.ram.position + j.close
			_close.look_at(_s.ram.position + Vector3.UP * 0.75)
	if _f == settle:
		if j.has("close"):
			_close.make_current()
		if j.get("action", "") != "":
			_s.ram._start_action(j.action)
		for k in j.get("keys", []):
			Input.action_press(k)
	if j.has("switch") and _f == settle + int(j.switch):
		for k in j.keys:
			Input.action_release(k)
		for k in j.keys2:
			Input.action_press(k)
	var idx: int = j.frames.find(_f - settle)
	if idx >= 0:
		_save(j.name, idx, "%.2fs" % ((_f - settle) / 60.0), j.crop)
	_f += 1
	return false


func _job() -> Dictionary:
	return _jobs[_ji]


func _save(group: String, idx: int, label: String, crop: int) -> void:
	var img := root.get_texture().get_image()
	if crop > 0:
		var c: Vector2 = _s.cam.unproject_position(_s.ram.global_position + Vector3.UP * 0.7)
		var x := clampi(int(c.x) - crop / 2, 0, img.get_width() - crop)
		var y := clampi(int(c.y) - crop / 2, 0, img.get_height() - crop)
		img = img.get_region(Rect2i(x, y, crop, crop))
	img.save_png("%s/%s__%02d__%s.png" % [_out, group, idx, label])
	print("SAVED ", group, " ", idx, " ", label)

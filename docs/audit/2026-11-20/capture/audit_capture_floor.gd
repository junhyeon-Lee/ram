## 평가용 증거 뽑기 (시험용 층): 시작 화면, 책상까지 달려가 박치기로 날리는 연속 장면(타격감), 콤보.
## 실행: godot --path <repo> --fixed-fps 60 --resolution 1280x720 --script audit_capture_floor.gd -- <raw 폴더>
extends SceneTree

var _m: Node
var _out := ""
var _f := 0
var _hit_at := -1


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	_m = load("res://game/main.tscn").instantiate()
	root.add_child(_m)


func _process(_d: float) -> bool:
	_f += 1
	var p = _m.player
	if _f == 90:
		_save("still_floor_1_start", 0, "start")
	if _f == 100:
		Input.action_press("move_forward")
	if _f > 100 and _hit_at < 0 and p.global_position.z < 5.6:      # 책상(z 4) 바로 앞
		Input.action_release("move_forward")
		_save("still_floor_2_desks", 0, "before")
		_hit_at = _f + 20
	if _hit_at > 0:
		var k := _f - _hit_at
		if k == 0:
			Input.action_press("attack")                      # 콤보: 계속 누르고 떼기를 되풀이
		elif k > 0 and k % 24 == 12:
			Input.action_release("attack")
		elif k > 0 and k % 24 == 0:
			Input.action_press("attack")
		if k >= 0 and k < 12 * 6 and k % 6 == 0:
			_save("seq_floor_hit", k / 6, "%.2fs" % (k / 60.0))
		if k >= 72 and k < 72 + 12 * 12 and (k - 72) % 12 == 0:
			_save("seq_floor_combo", (k - 72) / 12, "%.2fs" % (k / 60.0))
		if k == 72 + 12 * 12 + 60:
			Input.action_release("attack")
			_save("still_floor_3_after", 0, "after")
			quit()
			return true
	if _f > 1500:
		quit()
		return true
	return false


func _save(group: String, idx: int, label: String) -> void:
	root.get_texture().get_image().save_png("%s/%s__%02d__%s.png" % [_out, group, idx, label])
	print("SAVED ", group, " ", idx, " ", label)

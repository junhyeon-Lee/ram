## 헤드리스 스모크 테스트: 시험용 층을 띄워 입력을 흉내 내고 결과를 확인한다.
## 실행: godot --headless --path . --fixed-fps 120 --script tools/godot/smoke_test.gd
## 마지막 줄에 "SMOKE TEST: PASS" 또는 실패 항목이 나온다.
extends SceneTree

var _main: Node
var _frame := 0
var _step := 0
var _t := 0.0
var _mark := {}
var _fails: Array[String] = []
var _done := false


func _initialize() -> void:
	var scene: PackedScene = load("res://game/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)


func _process(delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	_t += delta / Engine.time_scale     # 실제 시간 (산재비스탄 중에도)
	var p: RamPlayer = _main.player
	match _step:
		0:  # 땅에 내려앉을 때까지 대기
			if _t > 0.5:
				_mark.pos = p.global_position
				_mark.yaw = p.global_rotation.y
				_next()
		1:  # 앞으로 1초
			Input.action_press("move_forward")
			if _t > 1.0:
				Input.action_release("move_forward")
				var moved: Vector3 = p.global_position - _mark.pos
				_check(moved.z < -2.0 and absf(moved.x) < 0.3, "forward 1s moves ~-Z (moved=%s)" % moved)
				_check(_main.player._anim.current_animation == "Run", "run animation while moving")
				_next()
		2:  # 왼쪽으로 0.5초 회전
			Input.action_press("turn_left")
			if _t > 0.5:
				Input.action_release("turn_left")
				var dyaw := wrapf(p.global_rotation.y - _mark.yaw, -PI, PI)
				_check(dyaw > deg_to_rad(55) and dyaw < deg_to_rad(95), "turn left 0.5s (~75 deg, got %.1f)" % rad_to_deg(dyaw))
				p.global_rotation.y = _mark.yaw   # 다시 정면으로
				_next()
		3:  # 책상 바로 앞으로 옮겨 박치기
			if _t < 0.05:
				p.global_position = Vector3(0, 0.05, 11.0 - 7.0 + 1.6)
				p.global_rotation.y = 0.0
				_mark.desk = _main.get_node("Desk_0_1")
				_mark.desk_pos = _mark.desk.global_position
			elif _t < 0.1:
				Input.action_press("attack")
			elif _t < 0.15:
				Input.action_release("attack")
			elif _t > 1.4:
				var desk: Breakable = _mark.desk
				_check(desk.hits == 1, "headbutt hits the desk once (hits=%d)" % desk.hits)
				_check(desk.global_position.distance_to(_mark.desk_pos) > 0.3, "desk is knocked away")
				_next()
		4:  # 백스텝: 뒤(+Z)로 약 0.65m
			if _t < 0.05:
				p.global_position = Vector3(4.5, 0.05, 6.0)
				p.global_rotation.y = 0.0
				_mark.pos = p.global_position
			elif _t < 0.1:
				Input.action_press("backstep")
			elif _t < 0.15:
				Input.action_release("backstep")
			elif _t > 1.2:
				var d: Vector3 = p.global_position - _mark.pos
				_check(d.z > 0.45 and d.z < 0.85, "backstep moves back ~0.65m (dz=%.2f)" % d.z)
				_next()
		5:  # 꼬리 패링: 한 바퀴 돌고 원래 방향으로
			if _t < 0.05:
				_mark.yaw = p.global_rotation.y
			elif _t < 0.1:
				Input.action_press("guard")
			elif _t < 0.15:
				Input.action_release("guard")
			elif _t > 0.5 and not _mark.has("mid_yaw"):
				_mark.mid_yaw = p.global_rotation.y
			elif _t > 1.4:
				var mid := absf(wrapf(_mark.mid_yaw - _mark.yaw, -PI, PI))
				var end := absf(wrapf(p.global_rotation.y - _mark.yaw, -PI, PI))
				_check(mid > deg_to_rad(60), "parry spins the body (mid %.0f deg)" % rad_to_deg(mid))
				_check(end < deg_to_rad(10), "parry ends facing forward (%.1f deg off)" % rad_to_deg(end))
				_next()
		6:  # 산재비스탄: 엔진·시계가 느려지고, Ram 은 실제 속도 유지, 체력이 깎임
			if not _mark.has("sanjae_pressed"):
				_mark.sanjae_pressed = true
				p.sanjae_gauge = 1.0
				_mark.hp = p.hp
				Input.action_press("sanjae")
			elif not _mark.has("sanjae_started"):
				_mark.sanjae_started = true
				Input.action_release("sanjae")
				_mark.clock = _main.clock.game_seconds
				_mark.pos = p.global_position
				_check(is_equal_approx(Engine.time_scale, RamPlayer.SANJAE_SCALE), "sanjae slows the engine (scale=%.2f)" % Engine.time_scale)
				_check(p.hp < _mark.hp, "sanjae costs HP")
				Input.action_press("move_forward")
			elif _t > 1.1 and not _mark.has("sanjae_checked"):
				_mark.sanjae_checked = true
				Input.action_release("move_forward")
				var game_dt: float = _main.clock.game_seconds - _mark.clock
				# 실제 1초 동안: 보통이면 게임 2초, 산재비스탄이면 0.6초
				_check(game_dt > 0.4 and game_dt < 0.9, "clock slows during sanjae (game %.2fs per real 1s)" % game_dt)
				var moved: float = (p.global_position - _mark.pos).length()
				_check(moved > 2.4, "Ram keeps real speed in sanjae (moved %.2fm in 1s)" % moved)
			elif _t > 3.6:
				_check(is_equal_approx(Engine.time_scale, 1.0), "sanjae ends after 3 real seconds")
				_next()
		7:  # 9시 마감: 시계를 8:59:58 로 돌려 마감 처리 확인
			if _t < 0.05:
				_main.clock.game_seconds = 9 * 3600 - 2.0
			elif _t > 1.5:
				_check(_main.clock.finished and _main._ended, "09:00 ends the run")
				_check(_main.clock.text() == "09:00:00", "clock shows 09:00:00 (got %s)" % _main.clock.text())
				_finish()
	return false


func _next() -> void:
	_step += 1
	_t = 0.0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> void:
	_done = true
	print("SMOKE TEST: " + ("PASS" if _fails.is_empty() else "FAIL (%d)" % _fails.size()))
	Engine.time_scale = 1.0
	quit(0 if _fails.is_empty() else 1)

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
				_check(_camera_sees(p), "camera sees Ram at spawn (no wall in between)")
				_next()
		1:  # 앞으로 1초
			Input.action_press("move_forward")
			# 달리는 동안 골반 높이가 출렁이는지 (root motion 으로 빠져나가지 않고 화면에 보이는지)
			var sk: Skeleton3D = p._model.find_child("Skeleton3D", true, false)
			var py := sk.get_bone_global_pose(sk.find_bone("pelvis")).origin.y
			if _t > 0.3:
				_mark.py_min = minf(_mark.get("py_min", py), py)
				_mark.py_max = maxf(_mark.get("py_max", py), py)
			if _t > 1.0:
				_check(_mark.py_max - _mark.py_min > 0.03, "run bobs the pelvis up/down (range %.3fm)" % (_mark.py_max - _mark.py_min))
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
		3:  # 박치기 4종: Space 로 하나 나오는지 보고, 넷을 차례로 새 책상에 쳐 본다
			var variants: Array = RamPlayer.ATTACK_VARIANTS
			var vi: int = _mark.get("vi", -1)
			var cam3: FollowCamera = _main.get_node("Camera")
			_mark.max_shake = maxf(_mark.get("max_shake", 0.0), cam3.shake)
			if vi == -1:
				# Space 를 누르면 네 가지 중 하나가 나온다
				if _t < 0.05:
					Input.action_press("attack")
				elif not _mark.has("space_checked"):
					_mark.space_checked = true
					Input.action_release("attack")
					_check(p._current_action in variants, "Space plays one of the 4 headbutts (%s)" % p._current_action)
				elif p._state == 0 and _t > 0.3:
					_mark.vi = 0
					_mark.v_start = _t
					_mark.hitstops = p.hitstop_count
					_mark.results = []
			elif vi < variants.size():
				var t0: float = _mark.v_start
				if _t - t0 < 0.02 and not _mark.has("v_spawned_%d" % vi):
					_mark["v_spawned_%d" % vi] = true
					p.global_position = Vector3(5.6, 0.05, 2.0)
					p.global_rotation.y = 0.0
					_main._breakable("TestDesk%d" % vi, Vector3(1.4, 0.9, 0.8), Vector3(5.6, 0.45, 0.5), Color(0.6, 0.5, 0.4))
					_mark.desk = _main.get_node("TestDesk%d" % vi)
					p._start_action(variants[vi])
				elif _t - t0 > 0.2 and p._state == 0 and p._hitstop_left <= 0.0:
					var d = _mark.desk
					var hits: int = 99 if not is_instance_valid(d) else d.hits
					_mark.results.append([variants[vi], hits])
					if is_instance_valid(d):
						d.queue_free()
					_mark.vi = vi + 1
					_mark.v_start = _t
			else:
				for r in _mark.results:
					var want := "breaks the desk (3 hits)" if r[0] == "Attack_Shove" else "hits the desk"
					var ok: bool = r[1] == 99 if r[0] == "Attack_Shove" else r[1] >= 1
					_check(ok, "%s %s (hits=%s)" % [r[0], want, "broken" if r[1] == 99 else str(r[1])])
				_check(p.hitstop_count - _mark.hitstops >= 4, "hitstop on every landed hit (%d)" % (p.hitstop_count - _mark.hitstops))
				_check(_mark.max_shake > 0.05, "camera shakes on impact (max %.2f)" % _mark.max_shake)
				_check(ImpactFx.spawned >= 4, "impact debris spawns on hits (%d)" % ImpactFx.spawned)
				_check(Sfx.thud().get_length() > 0.2 and Sfx.whoosh().get_length() > 0.15, "synth sounds are built (thud %.2fs, whoosh %.2fs)" % [Sfx.thud().get_length(), Sfx.whoosh().get_length()])
				# 번갈아 쓰기: 연달아 같은 박치기가 없고, 네 번마다 네 가지가 다 나온다
				var seq: Array = []
				p._attack_bag.clear()   # 한 바퀴 경계에 맞춰 검사
				for i in 16:
					seq.append(p._next_attack())
				var no_repeat := true
				for i in range(1, seq.size()):
					if seq[i] == seq[i - 1]:
						no_repeat = false
				var all_four := true
				for k in range(0, 16, 4):
					var chunk := {}
					for x in seq.slice(k, k + 4):
						chunk[x] = true
					if chunk.size() != 4:
						all_four = false
				_check(no_repeat and all_four, "attacks rotate: no back-to-back repeat, all 4 every 4 presses")
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
		5:  # 공중제비 패링: 몸(골반)이 공중에서 한 바퀴 구르고, 몸 방향과 카메라는 그대로
			var cam: Camera3D = _main.get_node("Camera")
			var sk5: Skeleton3D = p._model.find_child("Skeleton3D", true, false)
			var pel := sk5.get_bone_global_pose(sk5.find_bone("pelvis"))
			if _t < 0.05:
				_mark.yaw = p.global_rotation.y
				_mark.cam_yaw = cam.global_rotation.y
				_mark.pel_axis = pel.basis.y.normalized()
				_mark.pel_y = pel.origin.y
				_mark.min_dot = 1.0
				_mark.max_lift = 0.0
				_mark.max_body = 0.0
				_mark.max_cam = 0.0
			elif _t < 0.1:
				Input.action_press("guard")
			elif _t < 0.15:
				Input.action_release("guard")
			elif _t < 1.3:
				_mark.min_dot = minf(_mark.min_dot, pel.basis.y.normalized().dot(_mark.pel_axis))
				_mark.max_lift = maxf(_mark.max_lift, pel.origin.y - _mark.pel_y)
				_mark.max_body = maxf(_mark.max_body, absf(wrapf(p.global_rotation.y - _mark.yaw, -PI, PI)))
				_mark.max_cam = maxf(_mark.max_cam, absf(wrapf(cam.global_rotation.y - _mark.cam_yaw, -PI, PI)))
			else:
				_check(_mark.min_dot < -0.5, "parry flips the body over (pelvis axis dot %.2f)" % _mark.min_dot)
				_check(_mark.max_lift > 0.5, "parry jumps into the air (%.2fm)" % _mark.max_lift)
				_check(_mark.max_body < deg_to_rad(1), "parry keeps body facing (%.2f deg)" % rad_to_deg(_mark.max_body))
				_check(_mark.max_cam < deg_to_rad(1), "camera does not turn during parry (%.2f deg)" % rad_to_deg(_mark.max_cam))
				var end_dot := pel.basis.y.normalized().dot(_mark.pel_axis)
				_check(end_dot > 0.99, "lands upright after parry (dot %.3f)" % end_dot)
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
		7:  # 콤보: 맞은 뒤 Space 를 다시 누르면 이어지고, 4타째는 피니시. 위+Space 는 돌진, 길게 누르면 피니시
			var sub: int = _mark.get("csub", 0)
			if sub == 0:
				if not _mark.has("c_started"):
					_mark.c_started = true
					p.global_position = Vector3(-5.6, 0.05, 6.0)
					p.global_rotation.y = 0.0
					_mark.c_seq = []
					_mark.c_t0 = _t
					Input.action_press("attack")
				else:
					Input.action_release("attack")
					# 새 동작이 시작된 순간(동작 시간이 되감긴 순간)만 기록한다
					if p._current_action != "" and (_mark.c_seq.is_empty() or p._action_time < _mark.get("c_prev_t", 0.0)):
						_mark.c_seq.append(str(p._current_action))
					_mark.c_prev_t = p._action_time
					_mark.c_max = maxi(_mark.get("c_max", 0), p.combo_step)
					# 맞는 순간이 다 지나면 바로 다음 입력 (사람이 연타하는 것처럼)
					if p._state == 1 and p._hits_done >= p.ATTACKS[p._current_action].hits.size() and not p._queued:
						Input.action_press("attack")
					if p._state == 0 and _t - _mark.c_t0 > 0.5:
						var seq: Array = _mark.c_seq
						_check(seq.size() == 4, "4-hit combo chains (%s)" % ", ".join(seq))
						_check(seq.size() == 4 and seq[3] == RamPlayer.COMBO_FINISHER, "4th hit is the finisher")
						_check(_mark.c_max == 4, "combo counter reaches 4 (%d)" % _mark.c_max)
						_mark.csub = 1
						_mark.c_t0 = _t
			elif sub == 1:   # 위+Space = 돌진 공격
				if _t - _mark.c_t0 < 0.05:
					Input.action_press("move_forward")
					Input.action_press("attack")
				elif not _mark.has("dash_checked"):
					_mark.dash_checked = true
					Input.action_release("attack")
					Input.action_release("move_forward")
					_check(p._current_action == RamPlayer.DASH_ATTACK, "Up+Space is the charge attack (%s)" % p._current_action)
				elif p._state == 0:
					_mark.csub = 2
					_mark.c_t0 = _t
			elif sub == 2:   # Space 를 누른 채 있으면 피니시로 이어짐
				if not _mark.has("hold_pressed"):
					_mark.hold_pressed = true
					Input.action_press("attack")
				elif p._current_action == RamPlayer.COMBO_FINISHER and p.combo_step >= 2:
					_mark.hold_ok = true
				if p._state == 0 and _t - _mark.c_t0 > 0.3:
					Input.action_release("attack")
					_check(_mark.has("hold_ok"), "holding Space goes to the finisher")
					_next()

		8:  # 발: 달리기 재생 속도가 이동 속도에 맞는지, 깊게 웅크려도 발이 바닥에 파묻히지 않는지(IK), 다리 길이 유지
			var sk8: Skeleton3D = p._skeleton
			if not _mark.has("f_init"):
				_mark.f_init = true
				_mark.ank_min = INF
				_mark.ik_max = 0.0
				_mark.len_err = 0.0
				var lens := {}
				for side in ["L", "R"]:
					lens[side] = [sk8.get_bone_rest(sk8.find_bone("shin." + side)).origin.length(),
						sk8.get_bone_rest(sk8.find_bone("foot." + side)).origin.length()]
				_mark.rest_lens = lens
				sk8.skeleton_updated.connect(func() -> void:
					if not _mark.get("f_watch", false):
						return
					for side in ["L", "R"]:
						var th := sk8.get_bone_global_pose(sk8.find_bone("thigh." + side)).origin
						var sh := sk8.get_bone_global_pose(sk8.find_bone("shin." + side)).origin
						var ft := sk8.get_bone_global_pose(sk8.find_bone("foot." + side)).origin
						var y: float = (sk8.global_transform * ft).y
						_mark.ank_min = minf(_mark.ank_min, y)
						var rl: Array = _mark.rest_lens[side]
						_mark.len_err = maxf(_mark.len_err, maxf(absf(th.distance_to(sh) - rl[0]), absf(sh.distance_to(ft) - rl[1])))
					_mark.ik_max = maxf(_mark.ik_max, p.feet.max_influence))
				p.global_position = Vector3(-5.6, 0.05, 6.0)
				p.global_rotation.y = 0.0
				Input.action_press("move_forward")
				_mark.f_t0 = _t
			elif not _mark.has("f_run_checked"):
				if _t - _mark.f_t0 > 0.4:
					_mark.f_run_checked = true
					Input.action_release("move_forward")
					var want := p.forward_speed / RamPlayer.RUN_FOOT_SPEED
					_check(absf(p._anim.speed_scale - want) < 0.02, "run plays at move speed / foot speed (%.3f, want %.3f)" % [p._anim.speed_scale, want])
			elif not _mark.has("f_shove"):
				if p._state == 0 and _t - _mark.f_t0 > 0.8:
					_mark.f_shove = true
					_mark.f_watch = true
					_mark.f_t1 = _t
					p._start_action("Attack_Shove")
			elif _t - _mark.f_t1 > 1.6:
				_mark.f_watch = false
				_check(_mark.ik_max > 0.9, "foot IK turns on in a deep crouch (%.2f)" % _mark.ik_max)
				_check(_mark.ank_min > 0.055, "ankles stay above the floor (lowest %.3fm, was -0.06 without IK)" % _mark.ank_min)
				_check(_mark.len_err < 0.01, "IK keeps leg lengths (max error %.4fm)" % _mark.len_err)
				_next()

		9:  # 9시 마감: 시계를 8:59:58 로 돌려 마감 처리 확인
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


## 카메라에서 Ram 몸 가운데까지 벽(StaticBody3D)이 가로막지 않는지
func _camera_sees(p: RamPlayer) -> bool:
	var cam := root.get_camera_3d()
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, p.global_position + Vector3.UP * 0.9)
	q.exclude = [p.get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or not (hit.collider is StaticBody3D)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> void:
	_done = true
	print("SMOKE TEST: " + ("PASS" if _fails.is_empty() else "FAIL (%d)" % _fails.size()))
	Engine.time_scale = 1.0
	quit(0 if _fails.is_empty() else 1)

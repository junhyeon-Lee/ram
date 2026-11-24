## 출근길 장면 헤드리스 점검: 알을 깨고 나오는지, 집 안·길에서 자유롭게 움직이되 벽·알·경계석·직원에 막히는지,
## 박치기·대시·패링이 두 화면에서 되는지, 현관으로 나가 바깥으로 이어지는지, 카메라가 광장 경계부터 물러나는지,
## 정문에서 도착하는지, 이동 시간이 짧은지.
## 실행: godot --headless --path . --fixed-fps 120 --script tools/godot/commute_test.gd
## 마지막 줄에 "COMMUTE TEST: PASS" 또는 실패 항목 수가 나온다.
extends SceneTree

const MAX_TRAVEL_SECONDS := 13.5      # 처음 판(27초)의 절반 이하
const KEYS := ["move_forward", "move_back", "turn_left", "turn_right", "attack", "backstep", "guard"]
const MOVE := 0                       # RamPlayer.State.MOVE
const ACTION := 1

var _s: Node
var _p: RamPlayer
var _step := 0
var _t := 0.0
var _mark := {}
var _fails := 0
var _done := false


func _initialize() -> void:
	_s = load("res://game/commute/commute.tscn").instantiate()
	root.add_child(_s)


func _process(delta: float) -> bool:
	if _done:
		return true
	_p = _s.ram                           # 장면의 _ready 가 끝난 뒤에야 생긴다
	_t += delta
	match _step:
		0:  # 시작: 알 속. Ram 은 안 보이고 알은 온전하다
			if _t > 0.2:
				_check(_s.stage == _s.Stage.HOME and _s.hatching, "starts inside the egg at home")
				_check(not _p.visible, "Ram is hidden inside the egg")
				_check(_s.shards.size() >= 4 and _s.shards.size() <= 8, "egg top breaks into a few big shards (%d)" % _s.shards.size())
				_check(_egg_height() > 1.5, "egg is taller than Ram (shards up to %.2f m)" % _egg_height())
				_check(_s.cam.is_position_in_frustum(_s.egg.global_position + Vector3.UP * 1.3), "egg is on screen")
				_check(_s.travel_seconds() <= MAX_TRAVEL_SECONDS, "home to company takes %.1f s (limit %.1f), hatching %.1f s" % [_s.travel_seconds(), MAX_TRAVEL_SECONDS, _s.hatch_seconds()])
				_mark.cam = _s.cam.global_position
				_press(["turn_left"])                       # 깨는 동안에는 조작이 안 먹는다
				_next()
		1:  # 알이 터지고 Ram 이 튀어나와 내려선다
			if _p.visible and not _mark.has("peak"):
				_mark.peak = 0.0
			if _mark.has("peak"):
				_mark.peak = maxf(_mark.peak, _p.position.y)
			if not _s.hatching:
				_press([])
				_check(_t < 3.0, "hatches in %.1f s" % _t)
				_check(_mark.get("peak", 0.0) > 1.2, "Ram jumps out over the shell (peak %.2f m)" % _mark.get("peak", 0.0))
				_check(_local(_p.position).distance_to(_s.HATCH_LAND) < 0.1, "lands beside the egg")
				_check(_p._model.scale.is_equal_approx(Vector3.ONE) and absf(_p.rotation.x) < 0.01, "Ram stands level at full size")
				_check(_s.cam.is_position_in_frustum(_p.global_position + Vector3.UP * 0.7), "Ram is on screen")
				_next()
		2:  # 조각은 바닥에 흩어져 눕는다
			if _t > 1.5:
				var resting := 0
				var far := 0
				for sh in _s.shards:
					var n: Node3D = sh.node
					resting += 1 if sh.resting and n.position.y < 0.2 else 0
					far += 1 if Vector2(n.position.x, n.position.z).length() > 1.0 else 0
				_check(resting == _s.shards.size(), "all shards come to rest on the floor (%d/%d)" % [resting, _s.shards.size()])
				_check(far == _s.shards.size(), "shards land outside the shell (%d/%d)" % [far, _s.shards.size()])
				_check(_p._state == MOVE and absf(_p.position.y - 0.04) < 0.03, "Ram stands on the floor after hatching (y %.3f)" % _p.position.y)
				_mark.p = _p.position
				_next()
		3:  # 집 안 자유 이동: 오른쪽
			_press(["turn_right"])
			if _t > 0.5:
				var d: Vector3 = _p.position - _mark.p
				_check(d.x > 1.3 and absf(d.z) < 0.4, "right key moves Ram to the right of the screen (%.2f, %.2f)" % [d.x, d.z])
				_check(_p._anim.current_animation == "Run", "run animation while moving")
				var want := _p.forward_speed / RamPlayer.RUN_FOOT_SPEED
				_check(absf(_p._anim.speed_scale - want) < 0.02, "run plays at move speed / foot speed (%.3f)" % _p._anim.speed_scale)
				_mark.p = _p.position
				_next()
		4:  # 아래 = 화면 앞쪽(카메라 쪽)
			_press(["move_back"])
			if _t > 0.3:
				var d: Vector3 = _p.position - _mark.p
				_check(d.z > 0.6 and absf(d.x) < 0.3, "down key moves Ram toward the camera (%.2f, %.2f)" % [d.x, d.z])
				_check(_s.cam.global_position.distance_to(_mark.cam) < 0.01, "camera stays in place inside the home")
				_next()
		5:  # 벽: 계속 밀어도 방 밖으로 못 나간다
			_press(["turn_right", "move_back"])
			if _t > 3.0:
				var q := _local(_p.position)
				_check(Vector2(q.x, q.z).length() <= _s.ROOM_RADIUS + 0.01 and q.z <= _s.ROOM_FRONT_Z + 0.01, "walls stop Ram (%.2f m from the center)" % Vector2(q.x, q.z).length())
				_check(_s.cam.is_position_in_frustum(_p.global_position + Vector3.UP * 0.7), "Ram is still on screen at the wall")
				_next()
		6:  # 알: 껍질 안으로는 못 들어간다
			if _t < 0.05:
				_place(_s.HOME_ORIGIN + Vector3(0.6, 0.0, -1.0))
			_press(["turn_left"])
			if _t > 1.5:
				var gap := Vector2(_local(_p.position).x - _s.EGG_POS.x, _local(_p.position).z - _s.EGG_POS.z).length()
				_check(gap >= _s.EGG_BLOCK - 0.02, "the eggshell blocks Ram (%.2f m from its center)" % gap)
				_press([])
				_next()
		7:  # 집 안 박치기: Space
			if _t < 0.05:
				_place(_s.HOME_ORIGIN + Vector3(0.6, 0.0, -0.2))
				_press(["attack"])
			elif not _mark.has("h_attack"):
				_mark.h_attack = true
				_press([])
				_check(_p._state == ACTION and _p._current_action in RamPlayer.ATTACK_VARIANTS, "Space headbutts at home (%s)" % _p._current_action)
			elif _p._state == MOVE:
				_check(_t < 2.0, "headbutt finishes and control returns (%.1f s)" % _t)
				_next()
		8:  # 집 안 대시: 방향키 + Shift → 그 방향으로
			if _t < 0.05:
				_place(_s.HOME_ORIGIN + Vector3(-0.2, 0.0, 0.3))
				_mark.p = _p.position
				_press(["turn_right"])
			elif _t < 0.15:
				_press(["turn_right", "backstep"])
			elif not _mark.has("h_dash"):
				_mark.h_dash = true
				_press([])
				_check(_p._current_action == "Dash", "arrow + Shift dashes at home (%s)" % _p._current_action)
				_mark.dash_t = _t
				_mark.dash_p = _p.position
			elif _p._state == MOVE:
				var d: Vector3 = _p.position - _mark.p
				_check(d.x > 1.0 and absf(d.z) < 0.6, "dash carries Ram the way the arrow points (%.2f, %.2f)" % [d.x, d.z])
				# 대시는 달리기보다 확실히 빨라야 한다 (평가 때는 0.61초에 1.05m 로 달리기의 절반이었다)
				var dash_m: float = (_p.position - _mark.dash_p).length()
				var dash_s: float = _t - _mark.dash_t
				_check(dash_m / dash_s > _p.forward_speed * 1.3, "dash is faster than running (%.2f m in %.2f s = %.1f m/s, run %.1f)" % [dash_m, dash_s, dash_m / dash_s, _p.forward_speed])
				_next()
		9:  # 집 안 패링(E)·백스텝(Shift 만)
			if _t < 0.05:
				_press(["guard"])
			elif not _mark.has("h_parry"):
				_mark.h_parry = true
				_press([])
				_check(_p._current_action == "Parry_Tail", "E parries at home (%s)" % _p._current_action)
			elif _p._state == MOVE and not _mark.has("h_back"):
				_mark.h_back = _t
				_press(["backstep"])
			elif _mark.has("h_back") and _t > _mark.h_back + 0.1 and not _mark.has("h_back_checked"):
				_mark.h_back_checked = true
				_press([])
				_check(_p._current_action == "Backstep", "Shift alone backsteps (%s)" % _p._current_action)
			elif _mark.has("h_back_checked") and _p._state == MOVE:
				_next()
		10:  # 벽 쪽으로 대시해도 방 밖으로 못 나간다
			if _t < 0.05:
				_place(_s.HOME_ORIGIN + Vector3(2.4, 0.0, -0.3))
				_press(["turn_right"])
			elif _t < 0.15:
				_press(["turn_right", "backstep"])
			elif _t < 0.3:
				_press([])
			elif _p._state == MOVE:
				var q := _local(_p.position)
				_check(Vector2(q.x, q.z).length() <= _s.ROOM_RADIUS + 0.01, "a dash into the wall stays inside (%.2f m from the center)" % Vector2(q.x, q.z).length())
				_next()
		11:  # 방 어디에 있어도 화면 안에 보인다
			var missed := 0
			var total := 0
			for ix in range(-6, 7):
				for iz in range(-6, 4):
					var q := Vector2(ix * 0.45, iz * 0.45)
					if q.length() > _s.ROOM_RADIUS or q.y > _s.ROOM_FRONT_Z or q.distance_to(Vector2(_s.EGG_POS.x, _s.EGG_POS.z)) < _s.EGG_BLOCK:
						continue
					total += 1
					_p.position = _s.HOME_ORIGIN + Vector3(q.x, 0.04, q.y)
					_s._home_camera(1.0)
					for off in [Vector3(0, 0.1, 0), Vector3(0, 1.2, 0)]:
						if not _s.cam.is_position_in_frustum(_p.position + off):
							missed += 1
							break
			_check(missed == 0, "Ram is visible everywhere in the room (%d of %d spots missed)" % [missed, total])
			_place(_s.HOME_ORIGIN + _s.DOOR_DIR * 2.2)
			_next()
		12:  # 현관 굴로 나가면 바깥으로 이어진다
			_press(["turn_right", "move_forward"])
			if _s.stage == _s.Stage.ROAD and not _s._fading:
				_press([])
				_check(_t < 3.0, "leaves the home through the door (%.1f s)" % _t)
				_check(_p.position.distance_to(_s.ROAD_START) < 0.5, "comes out in front of the home door")
				_next()
			elif _t > 6.0:
				_press([])
				_check(false, "leaves the home through the door (still inside after 6 s)")
				_next()
		13:  # 위만 눌러도 샛길을 따라 길로 올라선다
			_press(["move_forward"])
			if _t > 1.9:
				_check(_p.position.z < _s.ROAD_START.z - 5.0, "up key leads from the door onto the road (z %.1f)" % _p.position.z)
				_check(absf(_p.position.x) <= 1.56, "Ram is on the road (x %.2f)" % _p.position.x)
				_mark.p = _p.position
				_next()
		14:  # 길에서 옆으로: 경계석까지만
			_press(["turn_right"])
			if _t > 2.0:
				_check(absf(_p.position.x - 1.55) < 0.01 and absf(_p.position.z - _mark.p.z) < 0.05, "moves sideways up to the curb (x %.2f)" % _p.position.x)
				_mark.p = _p.position
				_next()
		15:  # 아래: 돌아서 집 쪽으로
			_press(["move_back"])
			if _t > 1.0:
				var back: float = _p.position.z - _mark.p.z
				_check(back > 2.9 and back < 3.9, "down key runs back toward home (%.2f m)" % back)
				_check(_s.heading().z > 0.9, "Ram faces home after going back")
				_press([])
				_next()
		16:  # 길 위 돌진: 방향키 + Space
			if _t < 0.05:
				_place(Vector3(0.0, 0.04, -5.0))
				_mark.p = _p.position
				_press(["move_forward"])
			elif _t < 0.15:
				_press(["move_forward", "attack"])
			elif not _mark.has("r_attack"):
				_mark.r_attack = true
				_press([])
				_check(_p._current_action == RamPlayer.DASH_ATTACK, "arrow + Space charges on the road (%s)" % _p._current_action)
			elif _p._state == MOVE:
				_check(_p.position.z < _mark.p.z - 0.5 and absf(_p.position.x) <= 1.56, "the charge moves Ram up the road and keeps it on the road (z %.2f)" % (_p.position.z - _mark.p.z))
				_next()
		17:  # 길 위의 직원은 지나가지 못한다 (달려도, 대시해도)
			if _t < 0.05:
				_place(Vector3(_s.NPCS[0].x, 0.04, _s.NPCS[0].y + 2.0))
				_mark.near = 99.0
			_press(["move_forward", "backstep"] if _t > 0.3 and _t < 0.4 else ["move_forward"])
			_mark.near = minf(_mark.near, Vector2(_p.position.x, _p.position.z).distance_to(_s.NPCS[0]))
			if _t > 1.8:
				_press([])
				_check(_mark.near >= _s.NPC_BLOCK - 0.02, "a worker on the road blocks Ram (closest %.2f m)" % _mark.near)
				_next()
		18:  # 주택가 끝(광장 경계 바로 앞): 카메라는 아직 등 뒤에 가깝게 붙어 있다
			if _t < 0.05:
				_place(Vector3(0.0, 0.04, _s.ZOOM_START_Z + 1.0))
			elif _t > 2.0:
				_check(_s.zoom() < 0.001, "no zoom-out before the plaza boundary (zoom=%.2f)" % _s.zoom())
				_check(absf(_s.cam.global_position.y - _s.CAM_NEAR.y) < 0.1, "camera stays low behind Ram (%.2f m)" % _s.cam.global_position.y)
				_next()
		19:  # 경계를 넘으면 물러나기 시작한다
			if _t < 0.05:
				_place(Vector3(0.0, 0.04, _s.ZOOM_START_Z - 6.0))
			elif _t > 2.0:
				_check(_s.zoom() > 0.2 and _s.zoom() < 0.8, "zoom-out is under way inside the plaza (zoom=%.2f)" % _s.zoom())
				_check(_s.cam.global_position.y > _s.CAM_NEAR.y + 3.0, "camera has risen (%.2f m)" % _s.cam.global_position.y)
				_next()
		20:  # 광장 보도 끝에서 정문까지 달려 도착
			if _t < 0.05:
				_place(Vector3(2.0, 0.04, _s.DOOR_Z + 2.0))
			_press(["move_forward"])
			if _t > 1.5:
				_press([])
				_check(_s.arrived, "reaching the front door ends the commute")
				_check(absf(_p.position.z - _s.DOOR_Z) < 0.05, "Ram stops at the door (z=%.2f)" % _p.position.z)
				_check(absf(_s.progress() - 1.0) < 0.001, "progress bar is full")
				_next()
		21:  # 정문에 닿았을 때: 가장 멀고 높다. 건물 꼭대기 위로 하늘이 보인다
			if _t > 3.0:
				_check(_s.zoom() > 0.999, "camera fully pulled back at the door (zoom=%.2f)" % _s.zoom())
				_check(absf(_s.cam.global_position.y - _s.CAM_FAR.y) < 0.3, "camera height ~%.0fm (%.2f)" % [_s.CAM_FAR.y, _s.cam.global_position.y])
				var top := Vector3(0.0, 21.5, -_s.TOWER_Y)        # 옥상 시계
				_check(not _s.cam.is_position_behind(top) and _s.cam.is_position_in_frustum(top), "rooftop clock is on screen")
				var sky := Vector3(0.0, 30.0, -_s.TOWER_Y)        # 건물 꼭대기보다 8m 위
				_check(_s.cam.is_position_in_frustum(sky), "sky above the building is on screen")
				_check(_s.cam.is_position_in_frustum(_p.global_position + Vector3.UP * 0.7), "Ram is on screen")
				_done = true
				print("COMMUTE TEST: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
				quit(0 if _fails == 0 else 1)
	return false


func _next() -> void:
	_step += 1
	_t = 0.0


func _press(keys: Array) -> void:
	for k in KEYS:
		if k in keys:
			if not Input.is_action_pressed(k):
				Input.action_press(k)
		elif Input.is_action_pressed(k):
			Input.action_release(k)


func _place(p: Vector3) -> void:
	_p.position = Vector3(p.x, 0.04, p.z)
	_p.velocity = Vector3.ZERO


func _local(p: Vector3) -> Vector3:
	return p - _s.HOME_ORIGIN


func _egg_height() -> float:
	var top := 0.0
	for sh in _s.shards:
		top = maxf(top, (sh.node as Node3D).position.y)
	return top


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1

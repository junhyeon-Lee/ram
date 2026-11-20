## 집·출근길 카메라: 집 카메라가 고개를 돌리는 속도·지연, 화면 가장자리 여유, 방향키 → 화면 방향 어긋남,
## 길 카메라의 따라오는 지연, 옆걸음·뒤돌기 때 카메라 회전 속도, 줌 아웃 중 Ram 크기(화면 높이 %), 화면 밖.
## 화면 크기는 게임 기본 창(1152x648)으로 맞춘다.
extends SceneTree

const MAX_TICKS := 120 * 120
const DT := 1.0 / 120.0
const KEYS := ["move_forward", "move_back", "turn_left", "turn_right", "attack", "backstep", "guard", "sanjae"]
var ticks := 0
var s: Node
var p: RamPlayer
var cam: Camera3D
var vp := Vector2(1152, 648)
var ram_h := 1.2


func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	s = load("res://game/commute/commute.tscn").instantiate()
	root.add_child(s)
	_run()


func _physics_process(_d: float) -> bool:
	ticks += 1
	if ticks > MAX_TICKS:
		print("TIMEOUT")
		quit(2)
	return false


func tick(n := 1) -> void:
	for i in n:
		await physics_frame


func press(keys: Array) -> void:
	for k in KEYS:
		if k in keys:
			if not Input.is_action_pressed(k):
				Input.action_press(k)
		elif Input.is_action_pressed(k):
			Input.action_release(k)


func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func place(pos: Vector3, yaw := 0.0) -> void:
	p.position = Vector3(pos.x, 0.04, pos.z)
	p.rotation = Vector3(0, yaw, 0)
	p.velocity = Vector3.ZERO
	s._last_pos = p.position


func scr(w: Vector3) -> Vector2:
	# 헤드리스 창은 64x64(1:1)라 가로를 게임 창 16:9(1152x648) 기준으로 바꾼다 (세로 FOV 고정이라 세로는 그대로)
	var v := cam.unproject_position(w) / vp
	v.x = 0.5 + (v.x - 0.5) * (vp.x / vp.y) / (1152.0 / 648.0)
	return v


func ram_screen_height() -> float:
	var a := scr(p.global_position)
	var b := scr(p.global_position + Vector3.UP * ram_h)
	return absf(a.y - b.y)


func cam_yaw() -> float:
	var f := -cam.global_transform.basis.z
	return atan2(f.x, -f.z)


func cam_pitch() -> float:
	var f := -cam.global_transform.basis.z
	return asin(f.y)


## 방향키 8개 각각: 화면에서 Ram 이 움직이는 방향이 키 방향에서 몇 도 어긋나는가
func key_dev(label: String) -> void:
	var worst := 0.0
	var worst_key := ""
	var card := 0.0
	var per := []
	var sum := 0.0
	var n := 0
	for v in [Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1)]:
		var dir: Vector3 = p.screen_forward.cross(Vector3.UP) * v.x - p.screen_forward * v.y
		dir = dir.normalized()
		var a := scr(p.global_position + Vector3.UP * 0.5)
		var b := scr(p.global_position + Vector3.UP * 0.5 + dir * 0.3)
		var sd := (b - a) * Vector2(1152, 648)
		var dev := rad_to_deg(absf(v.normalized().angle_to(sd.normalized())))
		per.append("%s:%.0f" % ["U UR R DR D DL L UL".split(" ")[n], dev])
		sum += dev
		n += 1
		if v.x == 0 or v.y == 0:
			card = maxf(card, dev)
		if dev > worst:
			worst = dev
			worst_key = str(v)
	print("  %-34s key->screen deviation mean %.1f deg, worst %.1f deg (key %s), worst of 4 straight keys %.1f deg  %s" % [label, sum / n, worst, worst_key, card, " ".join(per)])


func _run() -> void:
	await tick(5)
	p = s.ram
	cam = s.cam
	vp = root.get_visible_rect().size
	print("viewport ", vp)
	s.skip_hatch()
	await tick(5)
	# Ram 키 (모델 메시 AABB)
	var box := AABB()
	var first := true
	for mi in p._model.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	ram_h = box.end.y - p.global_position.y
	print("Ram mesh height %.2f m (AABB top above feet), length %.2f m" % [ram_h, maxf(box.size.x, box.size.z)])

	print("--- home camera")
	# 정지 상태: 방 안 격자에서 화면 여유
	var min_margin := 1.0
	var where := Vector2.ZERO
	var edge := ""
	var hmin := 1.0
	var hmax := 0.0
	for ix in range(-7, 8):
		for iz in range(-7, 4):
			var q := Vector2(ix * 0.4, iz * 0.4)
			if q.length() > s.ROOM_RADIUS or q.y > s.ROOM_FRONT_Z or q.distance_to(Vector2(s.EGG_POS.x, s.EGG_POS.z)) < s.EGG_BLOCK:
				continue
			p.position = s.HOME_ORIGIN + Vector3(q.x, 0.04, q.y)
			s._home_camera(1.0)
			for off in [Vector3(0, 0.0, 0), Vector3(0, ram_h, 0)]:
				var sp := scr(p.position + off)
				var m := minf(minf(sp.x, 1.0 - sp.x), minf(sp.y, 1.0 - sp.y))
				if m < min_margin:
					edge = "x" if minf(sp.x, 1.0 - sp.x) < minf(sp.y, 1.0 - sp.y) else "y"
					min_margin = m
					where = q
			var h := ram_screen_height()
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
	print("  static: smallest margin of Ram (feet/top) to a screen edge %.1f%% (%s edge) at room (%.2f, %.2f); Ram height on screen %.0f%%..%.0f%%" % [min_margin * 100.0, edge, where.x, where.y, hmin * 100.0, hmax * 100.0])
	# 방향 어긋남
	for spot in [Vector2(0.45, -0.35), Vector2(-2.3, 0.6), Vector2(2.4, 0.5), Vector2(1.5, -2.2), Vector2(0.0, 0.95), Vector2(-0.3, -2.7)]:
		p.position = s.HOME_ORIGIN + Vector3(spot.x, 0.04, spot.y)
		s._home_camera(1.0)
		key_dev("home at (%.1f, %.1f)" % [spot.x, spot.y])
	# 움직일 때: 왼쪽 벽 → 오른쪽 벽으로 달리기
	place(s.HOME_ORIGIN + Vector3(-2.2, 0, 0.5))
	s._home_camera(1.0)
	await tick(5)
	var y_prev := cam_yaw()
	var max_rate := 0.0
	var max_lag := 0.0
	var sx_min := 1.0
	var sx_max := 0.0
	var off_ticks := 0
	press(["turn_right"])
	for i in 150:
		await tick()
		var yw := cam_yaw()
		max_rate = maxf(max_rate, absf(rad_to_deg(wrapf(yw - y_prev, -PI, PI))) / DT)
		y_prev = yw
		var focus: Vector3 = p.position + Vector3.UP * 0.7
		var want: Vector3 = (s.HOME_ORIGIN + s.HOME_LOOK).lerp(focus, s.HOME_TRACK)
		var f := -cam.global_transform.basis.z
		max_lag = maxf(max_lag, rad_to_deg(f.angle_to((want - cam.global_position).normalized())))
		var sp := scr(p.position + Vector3.UP * 0.5)
		sx_min = minf(sx_min, sp.x)
		sx_max = maxf(sx_max, sp.x)
		if not cam.is_position_in_frustum(p.position + Vector3.UP * 0.5):
			off_ticks += 1
	press([])
	print("  running left->right wall: camera turn rate max %.0f deg/s, look lag max %.1f deg, Ram screen x %.2f..%.2f, ticks off-screen %d" % [max_rate, max_lag, sx_min, sx_max, off_ticks])
	# 카메라 쪽으로 달리기
	place(s.HOME_ORIGIN + Vector3(0.0, 0, -2.0))
	s._home_camera(1.0)
	await tick(3)
	press(["move_back"])
	var symax := 0.0
	var ymin_top := 1.0
	for i in 120:
		await tick()
		symax = maxf(symax, scr(p.position).y)
		ymin_top = minf(ymin_top, scr(p.position + Vector3.UP * ram_h).y)
	press([])
	print("  running toward camera to the front edge: feet lowest on screen y=%.3f (1 = bottom edge), Ram height on screen %.0f%%" % [symax, ram_screen_height() * 100.0])

	print("--- road camera")
	s._enter(s.Stage.ROAD)
	await tick(3)
	# C1 앞으로 달리기 지연
	place(Vector3(0.0, 0, -6.5))
	s._follow_camera(1.0)
	await tick(3)
	var idle_y := scr(p.position + Vector3.UP * 0.6).y
	press(["move_forward"])
	await tick(150)
	var want_z: float = p.position.z + s.CAM_NEAR.z
	print("  C1 running fwd steady: camera %.3f m behind its target spot, Ram screen y idle %.3f -> running %.3f, Ram height %.0f%%" % [cam.global_position.z - want_z, idle_y, scr(p.position + Vector3.UP * 0.6).y, ram_screen_height() * 100.0])
	# C3 반대로: 카메라 쪽으로 달리기
	var yaw_p := cam_yaw()
	var pit_p := cam_pitch()
	var max_yr := 0.0
	var max_pr := 0.0
	var y_hist := []
	press(["move_back"])
	for i in 60:
		await tick()
		max_yr = maxf(max_yr, absf(rad_to_deg(cam_yaw() - yaw_p)) / DT)
		max_pr = maxf(max_pr, absf(rad_to_deg(cam_pitch() - pit_p)) / DT)
		yaw_p = cam_yaw()
		pit_p = cam_pitch()
		if i % 10 == 0:
			y_hist.append(snappedf(scr(p.position + Vector3.UP * 0.6).y, 0.001))
	print("  C3 fwd->back on road: Ram screen y every 10 ticks %s, camera pitch rate max %.1f deg/s, yaw rate max %.1f deg/s, camera dist behind target %.3f m" % [y_hist, max_pr, max_yr, cam.global_position.z - (p.position.z + s.CAM_NEAR.z)])
	press([])
	await tick(30)
	# C2 옆걸음
	place(Vector3(-1.5, 0, -12.0))
	s._follow_camera(1.0)
	await tick(3)
	yaw_p = cam_yaw()
	max_yr = 0.0
	var xs := []
	press(["turn_right"])
	for i in 100:
		await tick()
		max_yr = maxf(max_yr, absf(rad_to_deg(wrapf(cam_yaw() - yaw_p, -PI, PI))) / DT)
		yaw_p = cam_yaw()
		if i % 10 == 0:
			xs.append(snappedf(scr(p.position + Vector3.UP * 0.6).x, 0.001))
	press([])
	var lagx: float = cam.global_position.x - (p.position.x + s.CAM_NEAR.x)
	await tick(60)
	print("  C2 strafe right across road: Ram screen x every 10 ticks %s, camera yaw rate max %.1f deg/s, camera x lag at curb %.3f m" % [xs, max_yr, lagx])
	# C6 키 방향 어긋남 (길)
	for spot in [Vector3(0, 0, -10), Vector3(1.5, 0, -10), Vector3(-1.5, 0, -18)]:
		place(spot)
		s._follow_camera(1.0)
		key_dev("road (%.1f, %.1f)" % [spot.x, spot.z])

	print("--- zoom-out (steady camera at each spot, and while running)")
	for z in [-23.0, -26.0, -29.0, -32.0, -34.0, -36.0, -36.99]:
		for x in [0.0, 2.35, -2.35]:
			place(Vector3(x, 0, z))
			for k in 6:
				s._follow_camera(1.0)
			var top := scr(p.position + Vector3.UP * ram_h)
			var bot := scr(p.position)
			var inside := cam.is_position_in_frustum(p.position + Vector3.UP * 0.5)
			if x == 0.0:
				print("  z %.2f zoom %.2f cam dist %.1f m: Ram height %.1f%% of screen, Ram at screen (%.2f, %.2f)" % [z, s.zoom(), cam.global_position.distance_to(p.position), ram_screen_height() * 100.0, bot.x, (bot.y + top.y) * 0.5])
			else:
				print("      x %+.2f: Ram screen x %.3f, in frustum %s" % [x, bot.x, inside])
		place(Vector3(0, 0, z))
		for k in 3:
			s._follow_camera(1.0)
		key_dev("  keys at z %.1f, x 0" % z)
		place(Vector3(2.3, 0, z))
		for k in 3:
			s._follow_camera(1.0)
		key_dev("  keys at z %.1f, x 2.3" % z)
	# 달리면서
	place(Vector3(0, 0, -22.0))
	s._follow_camera(1.0)
	await tick(3)
	press(["move_forward"])
	var max_vy := 0.0
	var prev_cy := cam.global_position.y
	var max_lag2 := 0.0
	for i in 600:
		await tick()
		max_vy = maxf(max_vy, absf(cam.global_position.y - prev_cy) / DT)
		prev_cy = cam.global_position.y
		var e: float = s.zoom()
		var off: Vector3 = s.CAM_NEAR.lerp(s.CAM_FAR, e)
		var want := Vector3(p.position.x * (1.0 - e) + off.x, off.y, p.position.z + off.z)
		max_lag2 = maxf(max_lag2, cam.global_position.distance_to(want))
		if s.arrived:
			break
	press([])
	await tick(240)
	print("  running through the plaza: camera vertical speed max %.1f m/s, max distance from its target spot %.2f m, settled at door: Ram height %.1f%%" % [max_vy, max_lag2, ram_screen_height() * 100.0])
	print("DONE")
	quit(0)

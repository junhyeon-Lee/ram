## 시험용 층(기본 조작): 가속·정지·돌기·뒤로 가기·카메라 지연·벽 미끄러짐을 틱(1/120초) 단위로 잰다.
## 측정 시각: await physics_frame 직후 = 노드 물리 처리 전 → 읽는 값은 '지난 틱의 결과'. 입력도 여기서 누르므로 같은 틱에 just_pressed.
extends SceneTree

const MAX_TICKS := 120 * 90
const DT := 1.0 / 120.0
const KEYS := ["move_forward", "move_back", "turn_left", "turn_right", "attack", "backstep", "guard", "sanjae"]
var ticks := 0
var main: Node
var p: RamPlayer
var cam: FollowCamera


func _initialize() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
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


func place(pos: Vector3, yaw: float) -> void:
	p.global_position = pos
	p.rotation = Vector3(0, yaw, 0)
	p.velocity = Vector3.ZERO
	cam._yaw = yaw
	cam.global_position = cam._desired_position()


func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func fwd() -> Vector3:
	return -p.global_transform.basis.z


func _run() -> void:
	await tick(10)
	p = main.player
	cam = main.get_node("Camera")
	var vp := root.get_visible_rect().size
	print("viewport ", vp, "  physics_ticks ", Engine.physics_ticks_per_second)

	# ---- A. 가속·정지 (앞으로)
	place(Vector3(-5.5, 0.05, 9.0), 0.0)
	press([])
	await tick(40)
	var prev := p.global_position
	press(["move_forward"])
	var first_move := -1
	var full := -1
	var speeds := []
	for i in 90:
		await tick()
		var s := flat(p.global_position - prev).length() / DT
		prev = p.global_position
		speeds.append(s)
		if first_move < 0 and s > 0.01:
			first_move = i
		if full < 0 and s >= 0.95 * p.forward_speed:
			full = i
	var cam_lag := flat(cam.global_position - p.global_position).length() - cam.distance
	var scr_run := cam.unproject_position(p.global_position + Vector3.UP * 0.7) / vp
	print("A forward: first moving tick=%d (0=same tick)  95%% speed tick=%d  steady=%.3f m/s" % [first_move, full, speeds[-1]])
	print("A camera steady lag while running fwd: %.3f m (behind desired %.1f m)  Ram screen=(%.3f,%.3f)" % [cam_lag, cam.distance, scr_run.x, scr_run.y])
	press([])
	var stop_start := p.global_position
	var stop_tick := -1
	for i in 60:
		await tick()
		var s := flat(p.global_position - prev).length() / DT
		prev = p.global_position
		if stop_tick < 0 and s < 0.01:
			stop_tick = i
	print("A release: stopped at tick=%d  stop distance=%.3f m  anim=%s" % [stop_tick, flat(p.global_position - stop_start).length(), p._anim.current_animation])
	await tick(60)
	var scr_idle := cam.unproject_position(p.global_position + Vector3.UP * 0.7) / vp
	print("A Ram screen y idle %.3f vs running %.3f (shift %.1f%% of screen)" % [scr_idle.y, scr_run.y, (scr_run.y - scr_idle.y) * 100.0])

	# ---- B. 제자리 180° 돌기 + 카메라 따라 돌기
	place(Vector3(-5.5, 0.05, 0.0), 0.0)
	await tick(30)
	var y0 := p.rotation.y
	var acc := 0.0
	var last := y0
	var t180 := -1
	var max_lag := 0.0
	var scr_min := 1.0
	var scr_max := 0.0
	press(["turn_left"])
	for i in 400:
		await tick()
		acc += wrapf(p.rotation.y - last, -PI, PI)
		last = p.rotation.y
		max_lag = maxf(max_lag, absf(rad_to_deg(wrapf(p.rotation.y - cam._yaw, -PI, PI))))
		var sc := cam.unproject_position(p.global_position + Vector3.UP * 0.7) / vp
		scr_min = minf(scr_min, sc.x)
		scr_max = maxf(scr_max, sc.x)
		if acc >= PI and t180 < 0:
			t180 = i + 1
			break
	press([])
	var settle := -1
	for i in 240:
		await tick()
		if absf(rad_to_deg(wrapf(p.rotation.y - cam._yaw, -PI, PI))) < 1.0:
			settle = i
			break
	print("B turn in place 180 deg: %d ticks (%.2f s)  camera max yaw lag %.1f deg  camera settles <1 deg %d ticks after release  Ram screen x %.3f..%.3f  anim=%s" % [t180, t180 * DT, max_lag, settle, scr_min, scr_max, "Walk"])

	# ---- C. 달리며 U턴 (앞+왼쪽)
	place(Vector3(3.0, 0.05, 2.0), PI / 2.0)    # -X 쪽을 보고 시작 (책상 줄 사이 피함)
	place(Vector3(-5.0, 0.05, 9.0), 0.0)
	await tick(30)
	press(["move_forward"])
	await tick(60)
	var u0 := p.global_position
	acc = 0.0
	last = p.rotation.y
	press(["move_forward", "turn_right"])
	var u_ticks := 0
	var maxx := 0.0
	for i in 400:
		await tick()
		acc += absf(wrapf(p.rotation.y - last, -PI, PI))
		last = p.rotation.y
		maxx = maxf(maxx, p.global_position.x - u0.x)
		u_ticks = i + 1
		if acc >= PI:
			break
	print("C running U-turn (fwd+right): %d ticks (%.2f s), lateral width %.2f m, net forward advance %.2f m" % [u_ticks, u_ticks * DT, flat(p.global_position - u0).length(), -(p.global_position.z - u0.z)])
	press([])
	await tick(30)

	# ---- D. 달리다 아래키 (반대 방향): 기본 조작은 몸이 앞을 본 채 뒤로 걷는다
	place(Vector3(-5.5, 0.05, 2.0), 0.0)
	await tick(30)
	press(["move_forward"])
	await tick(60)
	prev = p.global_position
	var cam_before := cam.unproject_position(p.global_position + Vector3.UP * 0.7) / vp
	press(["move_back"])
	var rev := []
	for i in 60:
		await tick()
		var d := p.global_position - prev
		prev = p.global_position
		rev.append(d.dot(fwd()) / DT)
	var cam_after := cam.unproject_position(p.global_position + Vector3.UP * 0.7) / vp
	print("D fwd->back: velocity along facing ticks0..3 = %.2f %.2f %.2f %.2f, after 0.5s %.2f m/s, facing unchanged (dot=%.3f). anim=%s speed_scale=%.2f" % [rev[0], rev[1], rev[2], rev[3], rev[59], fwd().dot(Vector3.FORWARD), p._anim.current_animation, p._anim.speed_scale])
	print("D Ram screen y running fwd %.3f -> walking back 0.5s %.3f (%.1f%% screen jump)" % [cam_before.y, cam_after.y, (cam_after.y - cam_before.y) * 100.0])
	var lag_back := flat(cam.global_position - p.global_position).length() - cam.distance
	print("D camera lag while walking back: %.3f m (negative = closer than desired)" % lag_back)
	press([])
	await tick(30)

	# ---- E. 벽에 비스듬히 (왼쪽 벽 x=-7+0.15 안쪽 면 -6.85)
	for ang in [30.0, 45.0, 60.0, 80.0, 90.0]:
		# 정면 -Z 기준 왼쪽으로 ang 만큼: 벽 쪽(-X)으로 ang 각도
		place(Vector3(-5.8, 0.05, 6.0), deg_to_rad(ang))
		await tick(5)
		press(["move_forward"])
		var touched := -1
		var along := []
		var normal_pos := []
		prev = p.global_position
		for i in 240:
			await tick()
			var d := p.global_position - prev
			prev = p.global_position
			if p.global_position.x < -6.85 + 0.38 + 0.02 and touched < 0:
				touched = i
			if touched >= 0 and i > touched + 10:
				along.append(absf(d.z) / DT)
				normal_pos.append(p.global_position.x)
		press([])
		var mean_along := 0.0
		for a in along:
			mean_along += a
		mean_along /= maxf(1.0, along.size())
		var nmin := 99.0
		var nmax := -99.0
		var flips := 0
		for k in normal_pos.size():
			nmin = minf(nmin, normal_pos[k])
			nmax = maxf(nmax, normal_pos[k])
			if k >= 2 and signf(normal_pos[k] - normal_pos[k - 1]) != signf(normal_pos[k - 1] - normal_pos[k - 2]) and absf(normal_pos[k] - normal_pos[k - 1]) > 1e-5:
				flips += 1
		print("E wall at %2.0f deg: touch tick %d, slide speed %.3f m/s (%.0f%% of run, ideal cos=%.0f%%), normal pos range %.5f m, direction flips %d, anim %s x%.2f" % [ang, touched, mean_along, mean_along / p.forward_speed * 100.0, cos(deg_to_rad(ang)) * 100.0, nmax - nmin, flips, p._anim.current_animation, p._anim.speed_scale])
		await tick(20)

	# ---- F. 책상(RigidBody 8kg)에 달려 들어가기
	var desk: RigidBody3D = main.get_node("Desk_0_1")    # (0, 0.45, 4)
	place(Vector3(0.0, 0.05, 6.5), 0.0)
	await tick(10)
	var dp0 := desk.global_position
	press(["move_forward"])
	var rp0 := p.global_position
	await tick(120)
	press([])
	print("F run into desk 1 s: Ram moved %.2f m, desk moved %.3f m (Ram stops at desk; anim %s)" % [flat(p.global_position - rp0).length(), flat(desk.global_position - dp0).length(), p._anim.current_animation])
	await tick(10)
	print("DONE")
	quit(0)

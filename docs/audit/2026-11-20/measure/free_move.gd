## 출근길(자유 이동): 가속·정지·180°/90° 방향 전환 때 몸 방향 지연, 대시·백스텝·돌진 거리, 달리다 동작을 누를 때 속도 끊김.
extends SceneTree

const MAX_TICKS := 120 * 120
const DT := 1.0 / 120.0
const KEYS := ["move_forward", "move_back", "turn_left", "turn_right", "attack", "backstep", "guard", "sanjae"]
var ticks := 0
var s: Node
var p: RamPlayer


func _initialize() -> void:
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


func place(pos: Vector3, yaw: float) -> void:
	p.position = Vector3(pos.x, 0.04, pos.z)
	p.rotation = Vector3(0, yaw, 0)
	p.velocity = Vector3.ZERO
	s._last_pos = p.position


func facing() -> Vector2:
	var f := -p.global_transform.basis.z
	return Vector2(f.x, f.z).normalized()


func _run() -> void:
	await tick(5)
	p = s.ram
	s.skip_hatch()
	await tick(5)
	s._enter(s.Stage.ROAD)
	await tick(5)

	# F1 가속·정지
	place(Vector3(0, 0, -6.0), 0.0)
	press([])
	await tick(20)
	var prev := p.position
	press(["move_forward"])
	var first := -1
	var full := -1
	for i in 60:
		await tick()
		var sp := flat(p.position - prev).length() / DT
		prev = p.position
		if first < 0 and sp > 0.01:
			first = i
		if full < 0 and sp >= 0.95 * p.forward_speed:
			full = i
	press([])
	var st := p.position
	var stop := -1
	for i in 30:
		await tick()
		var sp := flat(p.position - prev).length() / DT
		prev = p.position
		if stop < 0 and sp < 0.01:
			stop = i
	print("F1 free: first move tick %d, 95%% speed tick %d, release -> stop tick %d, stop distance %.3f m" % [first, full, stop, flat(p.position - st).length()])

	# F2 180° 뒤로: 앞(-Z)으로 달리다 아래키
	for trial in 2:
		place(Vector3(0.3 * trial, 0, -14.0), 0.0)
		await tick(5)
		press(["move_forward"])
		await tick(60)
		prev = p.position
		press(["move_back"])
		var t90 := -1
		var t10 := -1
		var moon := 0.0
		var side_sum := 0.0
		var errs := []
		for i in 120:
			await tick()
			var d := flat(p.position - prev)
			prev = p.position
			var err := rad_to_deg(facing().angle_to(d.normalized())) if d.length() > 1e-4 else 0.0
			errs.append(absf(err))
			if absf(err) > 90.0:
				moon += d.length()
			if t90 < 0 and absf(err) <= 90.0:
				t90 = i
			if t10 < 0 and absf(err) <= 10.0:
				t10 = i
		print("F2 fwd->back (180): facing within 90 deg at tick %d (%.3f s), within 10 deg at tick %d (%.3f s); distance moved while facing >90 deg off: %.3f m; err ticks0..5 %s" % [t90, t90 * DT, t10, t10 * DT, moon, errs.slice(0, 6)])
		press([])
		await tick(30)

	# F3 90°: 앞 → 오른쪽
	place(Vector3(-1.2, 0, -14.0), 0.0)
	await tick(5)
	press(["move_forward"])
	await tick(40)
	prev = p.position
	press(["turn_right"])
	var t10b := -1
	var off45 := 0.0
	for i in 80:
		await tick()
		var d := flat(p.position - prev)
		prev = p.position
		var err := rad_to_deg(facing().angle_to(d.normalized())) if d.length() > 1e-4 else 0.0
		if absf(err) > 45.0:
			off45 += d.length()
		if t10b < 0 and absf(err) <= 10.0:
			t10b = i
	print("F3 fwd->right (90): facing within 10 deg at tick %d (%.3f s), distance moved while facing >45 deg off %.3f m" % [t10b, t10b * DT, off45])
	press([])
	await tick(20)

	# F4 동작 (자유 이동)
	var cases := [["Right+Shift dash", ["turn_right", "backstep"], Vector3(-1.4, 0, -12.0)],
		["Up+Shift dash", ["move_forward", "backstep"], Vector3(0, 0, -8.0)],
		["Shift alone backstep", ["backstep"], Vector3(0, 0, -12.0)],
		["Up+Space charge", ["move_forward", "attack"], Vector3(0, 0, -8.0)],
		["Down+Space (free)", ["move_back", "attack"], Vector3(0, 0, -16.0)],
		["Down+Shift (free)", ["move_back", "backstep"], Vector3(0, 0, -16.0)],
		["Space alone", ["attack"], Vector3(0, 0, -12.0)],
		["E parry", ["guard"], Vector3(0, 0, -12.0)]]
	for c in cases:
		place(c[2], 0.0)
		await tick(10)
		var start := p.position
		prev = p.position
		var yaw0 := p.rotation.y
		press(c[1])
		var act := -1
		var endt := -1
		var peak := 0.0
		var name := ""
		var movestart := -1
		for i in 300:
			if i == 8:
				press([])
			await tick()
			var sp := flat(p.position - prev).length() / DT
			prev = p.position
			peak = maxf(peak, sp)
			if p._state == 1 and act < 0:
				act = i
				name = str(p._current_action)
			if act >= 0 and movestart < 0 and sp > 0.05:
				movestart = i
			if act >= 0 and p._state == 0:
				endt = i
				break
		var d := flat(p.position - start)
		print("F4 %-22s -> %-16s act@%d move@%d end@%d (%.2f s) disp (x %.2f, z %.2f) = %.2f m, peak %.2f m/s, avg %.2f m/s, yaw snapped %+.0f deg" % [c[0], name, act, movestart, endt, endt * DT, d.x, d.y, d.length(), peak, d.length() / maxf(DT, (endt - act) * DT), rad_to_deg(wrapf(p.rotation.y - yaw0, -PI, PI))])
		await tick(10)

	# F5 달리다 Space: 속도가 끊기는가
	for label in ["run then Space", "run then Up+Shift dash"]:
		place(Vector3(0, 0, -6.0), 0.0)
		await tick(5)
		press(["move_forward"])
		await tick(40)
		prev = p.position
		press(["move_forward", "attack"] if label == "run then Space" else ["move_forward", "backstep"])
		var sp_list := []
		for i in 16:
			if i == 8:
				press([])
			await tick()
			sp_list.append(snappedf(flat(p.position - prev).length() / DT, 0.01))
			prev = p.position
		print("F5 %s: speed per tick (m/s) %s  action=%s" % [label, sp_list, p._current_action])
		press([])
		await tick(160)

	# F6 대시 중 방향키: 휘어지는가 / 공격 중 Shift+방향
	place(Vector3(-1.0, 0, -12.0), 0.0)
	await tick(5)
	press(["move_forward", "backstep"])
	await tick(8)
	press(["turn_right"])
	var p0 := p.position
	await tick(50)
	print("F6 steer during dash (hold Right): sideways drift %.3f m  action=%s" % [p.position.x - p0.x, p._current_action])
	press([])
	await tick(100)
	place(Vector3(0, 0, -12.0), 0.0)
	await tick(5)
	p._attack_bag = ["Attack_RearSlam"]
	press(["attack"])
	await tick(8)
	press([])
	await tick(40)
	press(["turn_right", "backstep"])
	await tick(8)
	press([])
	print("F6 Right+Shift at 0.4 s into RearSlam: current=%s (dash cancel %s)" % [p._current_action, "YES" if p._current_action == "Dash" else "NO"])
	await tick(120)

	# F7 동작 끝 → 달리기: 끝나는 틱에 방향키를 누르고 있으면 몇 틱 뒤 달리나
	place(Vector3(0, 0, -12.0), 0.0)
	await tick(5)
	press(["backstep"])
	await tick(8)
	press(["move_forward"])
	var was_action := true
	var end_tick := -1
	prev = p.position
	for i in 200:
		await tick()
		var sp := flat(p.position - prev).length() / DT
		prev = p.position
		if p._state == 0 and end_tick < 0:
			end_tick = i
		if end_tick >= 0 and sp > 3.0:
			print("F7 holding Up through backstep: running %d ticks after action end" % (i - end_tick))
			break
	press([])
	await tick(10)
	print("DONE")
	quit(0)

## 남은 확인: (1) 시험용 층 카메라가 벽에 막힐 때 튀는 정도·Ram 크기, (2) 집·출근길 박치기에 맞는 것이 있는가(히트스톱·흔들림),
## (3) 알 깨기·화면 전환 동안 입력이 버려지는 시간.
extends SceneTree

const MAX_TICKS := 120 * 90
const DT := 1.0 / 120.0
const KEYS := ["move_forward", "move_back", "turn_left", "turn_right", "attack", "backstep", "guard", "sanjae"]
var ticks := 0
var sc: Node
var p: RamPlayer


func _initialize() -> void:
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


func _run() -> void:
	sc = load("res://game/main.tscn").instantiate()
	root.add_child(sc)
	await tick(30)
	p = sc.player
	var cam: FollowCamera = sc.get_node("Camera")
	var vp := root.get_visible_rect().size
	# (1) 뒤 벽(z 안쪽 면 10.85) 앞에서 앞을 보고 서기 → 카메라가 벽에 막힘 → 제자리 돌기
	p.global_position = Vector3(-3.0, 0.05, 9.6)
	p.rotation.y = 0.0
	cam._yaw = 0.0
	cam.global_position = cam._desired_position()
	await tick(60)
	var d0 := cam.global_position.distance_to(p.global_position + Vector3.UP * 0.9)
	var h0 := absf((cam.unproject_position(p.global_position) - cam.unproject_position(p.global_position + Vector3.UP * 1.46)).y) / vp.y
	var maxstep := 0.0
	var prev := cam.global_position
	press(["turn_left"])
	var maxh := h0
	var mind := d0
	for i in 150:
		await tick()
		maxstep = maxf(maxstep, cam.global_position.distance_to(prev))
		prev = cam.global_position
		mind = minf(mind, cam.global_position.distance_to(p.global_position + Vector3.UP * 0.9))
		var h := absf((cam.unproject_position(p.global_position) - cam.unproject_position(p.global_position + Vector3.UP * 1.46)).y) / vp.y
		maxh = maxf(maxh, h)
	press([])
	# 열린 곳 기준
	p.global_position = Vector3(-3.0, 0.05, 0.0)
	cam.global_position = cam._desired_position()
	await tick(60)
	var hopen := absf((cam.unproject_position(p.global_position) - cam.unproject_position(p.global_position + Vector3.UP * 1.46)).y) / vp.y
	print("(1) camera against back wall: cam-Ram %.2f m (open floor %.2f m), Ram height on screen %.0f%% (max %.0f%% while turning; open floor %.0f%%), largest camera jump in one tick %.2f m (= %.0f m/s), closest cam-Ram %.2f m" % [d0, cam.distance, h0 * 100.0, maxh * 100.0, hopen * 100.0, maxstep, maxstep / DT, mind])
	sc.queue_free()
	await tick(5)

	# (2)(3) 출근길
	sc = load("res://game/commute/commute.tscn").instantiate()
	root.add_child(sc)
	await tick(2)
	p = sc.ram
	# 알 깨기 동안 Space
	var t0 := ticks
	var got := -1
	for i in 400:
		if i % 10 == 0:
			press(["attack"])
		elif i % 10 == 3:
			press([])
		await tick()
		if p._state == 1:
			got = i
			break
		if not sc.hatching and got < 0 and i > 0:
			pass
	print("(3) mashing Space from scene start: first action at tick %d (%.2f s); hatching ends at %.2f s" % [got, got * DT, sc.hatch_seconds()])
	press([])
	await tick(200)
	print("(2) home: camera has add_shake: %s" % sc.cam.has_method("add_shake"))
	var before := p.hitstop_count
	for a in ["Attack_RearSlam", "Attack_LowCharge", "Attack_FlankButt", "Attack_Shove"]:
		# 알 쪽을 보고 알 바로 앞에서
		var e: Vector3 = sc.HOME_ORIGIN + sc.EGG_POS
		var spot: Vector3 = e + Vector3(1.6, 0, 0)
		p.position = Vector3(spot.x, 0.04, spot.z)
		sc._last_pos = p.position
		p.rotation = Vector3(0, atan2(1.0, 0.0), 0)    # -X 쪽(알)을 본다
		await tick(3)
		p._attack_bag = [a]
		press(["attack"])
		await tick(8)
		press([])
		await tick(180)
	print("    attacks at the egg: hitstops %d" % (p.hitstop_count - before))
	sc._enter(sc.Stage.ROAD)
	await tick(3)
	before = p.hitstop_count
	var n: Vector2 = sc.NPCS[1]
	for a in ["Attack_RearSlam", "Attack_LowCharge", "Attack_FlankButt", "Attack_Shove"]:
		p.position = Vector3(n.x, 0.04, n.y + 0.8)
		sc._last_pos = p.position
		p.rotation = Vector3.ZERO
		await tick(3)
		p._attack_bag = [a]
		press(["attack"])
		await tick(8)
		press([])
		await tick(180)
	# 머리 둘레에 무엇이 걸리나
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 2.0
	q.shape = sph
	q.transform = Transform3D(Basis(), Vector3(n.x, 0.8, n.y))
	var found := []
	for h in p.get_world_3d().direct_space_state.intersect_shape(q, 16):
		found.append(str(h.collider.name) + ("(take_headbutt)" if h.collider.has_method("take_headbutt") else ""))
	print("    attacks at worker NPC1: hitstops %d; physics bodies within 2 m of the worker: %s" % [p.hitstop_count - before, found])
	# (3) 현관 → 길 전환 중 입력 막힘
	print("DONE")
	quit(0)

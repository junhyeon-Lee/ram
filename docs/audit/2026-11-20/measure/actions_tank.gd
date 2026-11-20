## 시험용 층(기본 조작): 동작마다 시작 지연·이동 거리·묶이는 시간, 맞힐 때 히트스톱·흔들림·날아가는 속도,
## 동작 중 입력이 버려지는지/기억되는지를 틱(1/120초) 단위로 잰다.
extends SceneTree

const MAX_TICKS := 120 * 120
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


## 동작 하나: keys 를 hold 틱 동안 누르고, MOVE 로 돌아올 때까지 기록.
## extra: {tick: keys} 로 중간에 누를 키 (1틱만 누르고 뗀다)
func run_action(label: String, keys: Array, hold := 8, extra := {}, max_t := 600) -> Dictionary:
	press([])
	await tick(2)
	var start := p.global_position
	var yaw0 := p.rotation.y
	var f0 := -p.global_transform.basis.z
	var r0 := p.global_transform.basis.x
	var prev := start
	var r := {"label": label, "act_tick": -1, "move_tick": -1, "end_tick": -1, "peak": 0.0, "seq": [], "hit_ticks": [], "hitstop_ticks": 0, "max_shake": 0.0, "shake_end": -1, "combo_max": 0}
	press(keys)
	var cur := ""
	var prev_at := 0.0
	var hits_prev := 0
	var saw_action := false
	for i in max_t:
		if i == hold:
			press([])
		if extra.has(i):
			press(extra[i])
		if extra.has(i - 3) and not extra.has(i) and i != hold:
			press([])
		await tick()
		var d := p.global_position - prev
		prev = p.global_position
		var s := flat(d).length() / DT
		r.peak = maxf(r.peak, s)
		if r.move_tick < 0 and s > 0.05:
			r.move_tick = i
		if p._state == 1:
			saw_action = true
			if r.act_tick < 0:
				r.act_tick = i
			if str(p._current_action) != cur or p._action_time < prev_at:
				cur = str(p._current_action)
				r.seq.append("%s@%d" % [cur, i])
				hits_prev = 0
			prev_at = p._action_time
			if p._hits_done > hits_prev:
				r.hit_ticks.append(i)
				hits_prev = p._hits_done
		if p._hitstop_left > 0.0:
			r.hitstop_ticks += 1
		r.max_shake = maxf(r.max_shake, cam.shake)
		r.combo_max = maxi(r.combo_max, p.combo_step)
		if saw_action and p._state == 0 and r.end_tick < 0:
			r.end_tick = i
		if r.end_tick >= 0 and i > r.end_tick + 2 and cam.shake < 0.005:
			break
	var disp := p.global_position - start
	r.fwd = disp.dot(f0)
	r.side = disp.dot(r0)
	r.dist = flat(disp).length()
	r.yaw = rad_to_deg(wrapf(p.rotation.y - yaw0, -PI, PI))
	return r


func show(r: Dictionary) -> void:
	print("%-26s act@%d move@%d end@%d (%.2fs) fwd %.2f side %.2f dist %.2f m peak %.2f m/s yaw %+.0f  seq=%s hits@%s hitstop %d ticks shake max %.3f combo %d" % [
		r.label, r.act_tick, r.move_tick, r.end_tick, r.end_tick * DT, r.fwd, r.side, r.dist, r.peak, r.yaw, r.seq, r.hit_ticks, r.hitstop_ticks, r.max_shake, r.combo_max])


func spawn_desk(n: String, pos: Vector3) -> RigidBody3D:
	main._breakable(n, Vector3(1.4, 0.9, 0.8), pos, Color(0.6, 0.5, 0.4))
	return main.get_node(n)


func _run() -> void:
	await tick(30)
	p = main.player
	cam = main.get_node("Camera")
	var open := Vector3(-5.5, 0.05, 8.0)

	print("--- animation lengths")
	for a in ["Idle", "Walk", "Run", "Dash", "Backstep", "Parry_Tail", "Attack_RearSlam", "Attack_LowCharge", "Attack_FlankButt", "Attack_Shove", "Attack_Hook", "Attack_Uppercut"]:
		if p._anim.has_animation(a):
			var spec: Dictionary = p.ATTACKS.get(a, {})
			var hits: Array = spec.get("hits", [])
			print("  %-18s len %.3f s%s" % [a, p._anim.get_animation(a).length, "" if hits.is_empty() else "  first hit %.3f s (%d ticks), last hit %.3f s, recovery after last hit %.3f s" % [hits[0], roundi(hits[0] * 120), hits.back(), p._anim.get_animation(a).length - hits.back()]])

	print("--- single actions from rest, open floor (whiff)")
	for a in ["Attack_RearSlam", "Attack_LowCharge", "Attack_FlankButt", "Attack_Shove"]:
		place(open, 0.0)
		await tick(20)
		p._attack_bag = [a]
		show(await run_action("whiff " + a, ["attack"]))
	place(open, 0.0)
	await tick(20)
	show(await run_action("Up+Space charge", ["move_forward", "attack"]))
	place(open, 0.0)
	await tick(20)
	show(await run_action("Backstep (Shift)", ["backstep"]))
	place(open, 0.0)
	await tick(20)
	show(await run_action("Parry (E)", ["guard"]))
	place(open, 0.0)
	await tick(20)
	show(await run_action("Down+Shift (tank)", ["move_back", "backstep"]))
	place(open, 0.0)
	await tick(20)
	p._attack_bag = ["Attack_FlankButt"]
	show(await run_action("Down+Space (tank)", ["move_back", "attack"]))

	print("--- hits on a fresh desk (Ram at desk+1.5 m)")
	var k := 0
	for a in ["Attack_RearSlam", "Attack_LowCharge", "Attack_FlankButt", "Attack_Shove"]:
		place(Vector3(5.6, 0.05, 2.0), 0.0)
		var desk := spawn_desk("D%d" % k, Vector3(5.6, 0.45, 0.5))
		k += 1
		await tick(20)
		p._attack_bag = [a]
		# 맞는 틱 뒤 책상 속도를 보려고 따로 지켜본다
		var watch := {"v": 0.0, "moved_in_stop": 0.0}
		var r := await run_action_watch("hit " + a, desk, watch)
		show(r)
		print("    desk speed right after hit %.2f m/s, desk moved %.3f m during Ram's hitstop (target not frozen if > 0)" % [watch.v, watch.moved_in_stop])
		if is_instance_valid(desk):
			desk.queue_free()
		await tick(30)

	print("--- input during actions")
	# B1: 백스텝 중간에 Space 1틱 → 끝난 뒤 박치기가 나오는가
	place(open, 0.0)
	await tick(20)
	show(await run_action("B1 Backstep + Space@30", ["backstep"], 8, {30: ["attack"]}))
	# B1b: 백스텝 끝나기 직전 (끝 틱 - 3) Space
	place(open, 0.0)
	await tick(20)
	var bl := roundi(p._anim.get_animation("Backstep").length * 120)
	show(await run_action("B1b Backstep + Space@end-3", ["backstep"], 8, {bl - 3: ["attack"]}))
	# B2: 헛친 박치기 60% 에서 Shift → 버려지는가
	place(open, 0.0)
	await tick(20)
	p._attack_bag = ["Attack_RearSlam"]
	show(await run_action("B2 RearSlam + Shift@80", ["attack"], 8, {80: ["backstep"]}))
	# B9: 헛친 박치기 중 E
	place(open, 0.0)
	await tick(20)
	p._attack_bag = ["Attack_RearSlam"]
	show(await run_action("B9 RearSlam + E@80", ["attack"], 8, {80: ["guard"]}))
	# B3: 헛친 박치기 중 Space 다시 (맞는 순간 전) → 헛쳐도 콤보로 이어지는가
	place(open, 0.0)
	await tick(20)
	p._attack_bag = ["Attack_FlankButt"]
	show(await run_action("B3 whiff FlankButt + Space@20", ["attack"], 8, {20: ["attack"]}))
	# B5: Space 를 길게 (0.5 s) → 의도하지 않은 피니시?
	place(open, 0.0)
	await tick(20)
	p._attack_bag = ["Attack_FlankButt"]
	show(await run_action("B5 Space held 0.5s", ["attack"], 60))
	# B7: 박치기 중 방향키 돌기 → 동작 중 몸을 돌릴 수 있는가
	place(open, 0.0)
	await tick(20)
	p._attack_bag = ["Attack_FlankButt"]
	show(await run_action("B7 FlankButt + hold Left", ["attack", "turn_left"], 90))
	# B8: 헛친 4연타 최단 (맞는 순간 지나면 바로 누름)
	place(open, 0.0)
	await tick(20)
	p._attack_bag = ["Attack_FlankButt"]
	var ex := {}
	for t in range(10, 400, 6):
		ex[t] = ["attack"]
	show(await run_action("B8 mash Space every 6 ticks", ["attack"], 1, ex))
	# B4: 맞힌 뒤 히트스톱 중 Space 1틱 → 버려지는가
	place(Vector3(5.6, 0.05, 2.0), 0.0)
	var desk2 := spawn_desk("DB4", Vector3(5.6, 0.45, 0.5))
	await tick(20)
	p._attack_bag = ["Attack_FlankButt"]
	var hit_t := roundi(0.367 * 120)
	show(await run_action("B4 hit + Space during hitstop", ["attack"], 8, {hit_t + 2: ["attack"]}))
	if is_instance_valid(desk2):
		desk2.queue_free()
	await tick(10)
	# B4b: 같은데 히트스톱 직후 (+10)
	place(Vector3(5.6, 0.05, 2.0), 0.0)
	desk2 = spawn_desk("DB4b", Vector3(5.6, 0.45, 0.5))
	await tick(20)
	p._attack_bag = ["Attack_FlankButt"]
	show(await run_action("B4b hit + Space after hitstop", ["attack"], 8, {hit_t + 10: ["attack"]}))
	if is_instance_valid(desk2):
		desk2.queue_free()

	print("--- camera shake curve (FlankButt hit)")
	place(Vector3(5.6, 0.05, 2.0), 0.0)
	var desk3 := spawn_desk("DS", Vector3(5.6, 0.45, 0.5))
	await tick(20)
	p._attack_bag = ["Attack_RearSlam"]
	press(["attack"])
	await tick()
	press([])
	var curve := []
	var max_off := 0.0
	for i in 160:
		await tick()
		if cam.shake > 0.0 or curve.size() > 0:
			curve.append(cam.shake)
			max_off = maxf(max_off, maxf(absf(cam.h_offset), absf(cam.v_offset)))
	var above := 0
	for c in curve:
		if c > 0.02:
			above += 1
	var dist_cam := cam.global_position.distance_to(p.global_position + Vector3.UP * 0.9)
	var screen_h := 2.0 * dist_cam * tan(deg_to_rad(cam.fov * 0.5))
	print("RearSlam hit: shake start %.3f m, ticks above 0.02 m: %d (%.2f s), max offset %.3f m = %.1f%% of screen height at Ram (cam dist %.2f m)" % [curve[0] if curve.size() > 0 else 0.0, above, above * DT, max_off, max_off / screen_h * 100.0, dist_cam])
	if is_instance_valid(desk3):
		desk3.queue_free()
	print("DONE")
	quit(0)


func run_action_watch(label: String, desk: RigidBody3D, watch: Dictionary) -> Dictionary:
	# run_action 과 같지만 책상 속도를 같이 본다: 한 틱씩 따로 돌린다
	var st := {"done": false}
	var res := {}
	var f := func() -> void:
		res.merge(await run_action(label, ["attack"]))
		st.done = true
	f.call()
	var stop_pos := Vector3.ZERO
	var in_stop := false
	while not st.done:
		await tick()
		if not is_instance_valid(desk):
			continue
		if p._hitstop_left > 0.0 and not in_stop:
			in_stop = true
			stop_pos = desk.global_position
		if in_stop and watch.v == 0.0 and desk.linear_velocity.length() > 0.1:
			watch.v = desk.linear_velocity.length()
		if in_stop and p._hitstop_left <= 0.0 and watch.moved_in_stop == 0.0:
			watch.moved_in_stop = desk.global_position.distance_to(stop_pos) + 1e-6
	return res

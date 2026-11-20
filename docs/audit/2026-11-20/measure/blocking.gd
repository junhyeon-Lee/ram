## 집·출근길 막힘: 벽·알·경계석·직원에 비스듬히 밀 때 남는 속도, 떨림, 딱 멈추는 자리(_walkable 이 from 을 돌려주는 경우),
## 대시·돌진으로 뚫리는가, 막혀 있는 동안 달리기 동작이 계속 도는가.
extends SceneTree

const MAX_TICKS := 120 * 150
const DT := 1.0 / 120.0
const KEYS := ["move_forward", "move_back", "turn_left", "turn_right", "attack", "backstep", "guard", "sanjae"]
const DIRS := {"U": ["move_forward"], "UR": ["move_forward", "turn_right"], "R": ["turn_right"], "DR": ["move_back", "turn_right"],
	"D": ["move_back"], "DL": ["move_back", "turn_left"], "L": ["turn_left"], "UL": ["move_forward", "turn_left"]}
const VEC := {"U": Vector2(0, -1), "UR": Vector2(1, -1), "R": Vector2(1, 0), "DR": Vector2(1, 1), "D": Vector2(0, 1), "DL": Vector2(-1, 1), "L": Vector2(-1, 0), "UL": Vector2(-1, -1)}
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


func place(pos: Vector3, yaw := 0.0) -> void:
	p.position = Vector3(pos.x, 0.04, pos.z)
	p.rotation = Vector3(0, yaw, 0)
	p.velocity = Vector3.ZERO
	s._last_pos = p.position


func key_dir(k: String) -> Vector2:
	var v: Vector2 = VEC[k]
	var d: Vector3 = p.screen_forward.cross(Vector3.UP) * v.x - p.screen_forward * v.y
	return flat(d).normalized()


## 한 키를 누르고 n 틱 동안: 평균 속도, 법선 방향 떨림(부호 바뀜 수), 달리기 재생 배율
func hold(k: String, n: int, normal_fn: Callable) -> Dictionary:
	press(DIRS[k])
	var prev := p.position
	var sp := []
	var nrm := []
	for i in n:
		await tick()
		sp.append(flat(p.position - prev).length() / DT)
		prev = p.position
		nrm.append(normal_fn.call(p.position))
	press([])
	var mean := 0.0
	for i in range(10, sp.size()):
		mean += sp[i]
	mean /= maxf(1.0, sp.size() - 10)
	var flips := 0
	for i in range(12, nrm.size()):
		var a: float = nrm[i] - nrm[i - 1]
		var b: float = nrm[i - 1] - nrm[i - 2]
		if absf(a) > 1e-5 and absf(b) > 1e-5 and signf(a) != signf(b):
			flips += 1
	var nmin := 1e9
	var nmax := -1e9
	for i in range(10, nrm.size()):
		nmin = minf(nmin, nrm[i])
		nmax = maxf(nmax, nrm[i])
	return {"mean": mean, "flips": flips, "nrange": nmax - nmin, "anim": str(p._anim.current_animation), "scale": p._anim.speed_scale, "min": sp.slice(10).min() if sp.size() > 10 else 0.0}


## _walkable 이 그 자리 그대로(from)를 돌려 '딱 멈추는' 경우를 격자로 센다.
## 미끄러질 수 있었는지: 같은 키 방향을 ±45° 돌린 방향 중 하나라도 움직이면 '미끄러질 길이 있었는데 멈춤'
func stop_grid(label: String, origin: Vector2, half: Vector2, stepm: float) -> void:
	var stops := 0
	var slide_possible := 0
	var total := 0
	var examples := []
	var step := p.forward_speed * DT
	var x := origin.x - half.x
	while x <= origin.x + half.x:
		var z := origin.y - half.y
		while z <= origin.y + half.y:
			var q := Vector3(x, 0.04, z)
			var ok: Vector3 = s._walkable(q, q)
			if flat(ok - q).length() < 1e-5:
				for k in VEC.keys():
					var d := key_dir(k)
					total += 1
					var r: Vector3 = s._walkable(q, q + Vector3(d.x, 0, d.y) * step)
					var moved := flat(r - q).length()
					if moved < 1e-6:
						stops += 1
						var alt := 0.0
						for ang in [-PI / 4.0, PI / 4.0]:
							var d2 := d.rotated(ang)
							var r2: Vector3 = s._walkable(q, q + Vector3(d2.x, 0, d2.y) * step)
							alt = maxf(alt, flat(r2 - q).length() / step)
						if alt > 0.3:
							slide_possible += 1
							if examples.size() < 4:
								examples.append("(%.2f,%.2f) key %s" % [x, z, k])
			z += stepm
		x += stepm
	print("  %s: %d of %d position x key tests are dead stops; %d of them had a slide path (45 deg off moves >=30%%). e.g. %s" % [label, stops, total, slide_possible, examples])


func _run() -> void:
	await tick(5)
	p = s.ram
	s.skip_hatch()
	await tick(5)
	var H: Vector3 = s.HOME_ORIGIN
	print("--- home: room wall (radius %.2f), each key at several wall spots" % s.ROOM_RADIUS)
	var radial := func(pos: Vector3) -> float: return flat(pos - H).length()
	for az in [180.0, 135.0, 90.0, 45.0, 0.0, 220.0]:
		var dirn := Vector2(cos(deg_to_rad(az)), -sin(deg_to_rad(az)))   # 방 가운데에서 벽 쪽 (x, z)
		var spot: Vector2 = dirn * (s.ROOM_RADIUS - 0.02)
		if spot.y > s.ROOM_FRONT_Z:
			continue
		for k in VEC.keys():
			var kd := key_dir(k)
			var inc := rad_to_deg(kd.angle_to(dirn))
			if absf(inc) < 20.0 or absf(inc) > 75.0:
				continue
			place(H + Vector3(spot.x, 0, spot.y))
			await tick(2)
			var r: Dictionary = await hold(k, 50, radial)
			print("  wall az %3.0f key %-2s incidence %4.0f deg: speed %.2f m/s (%.0f%% of run, ideal slide %.0f%%), radial range %.4f m, flips %d, anim %s x%.2f" % [az, k, inc, r.mean, r.mean / p.forward_speed * 100.0, sin(deg_to_rad(absf(inc))) * 100.0, r.nrange, r.flips, r.anim, r.scale])
			press([])
			await tick(3)
	# 정면으로 벽
	place(H + Vector3(2.7, 0, 0.0))
	await tick(2)
	var rw: Dictionary = await hold("R", 60, radial)
	print("  push straight into right wall: speed %.3f m/s, anim %s x%.2f (running in place)" % [rw.mean, rw.anim, rw.scale])

	print("--- home: egg (center %s, block %.2f)" % [s.EGG_POS, s.EGG_BLOCK])
	var E: Vector3 = H + s.EGG_POS
	var egg_r := func(pos: Vector3) -> float: return flat(pos - E).length()
	for k in ["L", "UL", "DL", "U"]:
		place(H + Vector3(0.1, 0, -0.8))
		await tick(2)
		var r: Dictionary = await hold(k, 120, egg_r)
		print("  from (0.1,-0.8) hold %-2s: mean speed %.2f m/s (after first 10 ticks), min %.2f, egg-dist range %.4f, flips %d, ended at (%.2f, %.2f) dist to egg %.2f" % [k, r.mean, r.min, r.nrange, r.flips, (p.position - H).x, (p.position - H).z, flat(p.position - E).length()])
		press([])
		await tick(3)
	stop_grid("home grid", Vector2(H.x, H.z), Vector2(3.0, 3.0), 0.05)

	print("--- road")
	s._enter(s.Stage.ROAD)
	await tick(3)
	var curbx := func(pos: Vector3) -> float: return pos.x
	place(Vector3(1.5, 0, -10.0))
	await tick(2)
	var rc: Dictionary = await hold("UR", 60, curbx)
	print("  curb, Up+Right: speed %.2f m/s (%.0f%% of run), x range %.4f, flips %d, anim %s x%.2f" % [rc.mean, rc.mean / p.forward_speed * 100.0, rc.nrange, rc.flips, rc.anim, rc.scale])
	place(Vector3(1.5, 0, -10.0))
	await tick(2)
	rc = await hold("R", 60, curbx)
	print("  curb, Right only: speed %.3f m/s, anim %s x%.2f (running in place)" % [rc.mean, rc.anim, rc.scale])
	# 직원
	var npcs: Array = s.NPCS
	for c in [[0, 0.0, "U"], [0, 0.4, "U"], [0, -0.5, "U"], [0, 0.25, "U"], [1, 0.0, "U"], [1, 0.3, "U"], [1, -0.4, "UL"], [1, 0.5, "UR"]]:
		var n: Vector2 = npcs[c[0]]
		place(Vector3(n.x + c[1], 0, n.y + 1.6))
		await tick(2)
		var npc_d := func(pos: Vector3) -> float: return flat(pos).distance_to(n)
		var stuck := 0
		var prev := p.position
		press(DIRS[c[2]])
		var closest := 9.0
		var passed := -1
		var flips := 0
		var lastd := 0.0
		var lastdd := 0.0
		for i in 240:
			await tick()
			var mv := flat(p.position - prev).length()
			prev = p.position
			if i > 30 and mv < 1e-6:
				stuck += 1
			closest = minf(closest, npc_d.call(p.position))
			var dd: float = npc_d.call(p.position) - lastd
			if i > 30 and absf(dd) > 1e-5 and absf(lastdd) > 1e-5 and signf(dd) != signf(lastdd):
				flips += 1
			lastdd = dd
			lastd = npc_d.call(p.position)
			if passed < 0 and p.position.z < n.y - 0.8:
				passed = i
		press([])
		print("  NPC%d at x offset %+.2f key %-2s: passed it after %s, ticks at a dead stop %d/210, closest %.3f m, dist flips %d, end x %.2f, anim %s" % [c[0], c[1], c[2], ("%.2f s" % (passed * DT)) if passed >= 0 else "NEVER (2 s)", stuck, closest, flips, p.position.x, p._anim.current_animation])
		await tick(3)
	# 대시·돌진으로 직원 뚫기
	for c in [["Up+Shift dash", ["move_forward", "backstep"]], ["Up+Space charge", ["move_forward", "attack"]]]:
		var n: Vector2 = npcs[1]
		place(Vector3(n.x, 0, n.y + 1.3))
		await tick(2)
		press(c[1])
		var closest := 9.0
		for i in 130:
			if i == 8:
				press([])
			await tick()
			closest = minf(closest, flat(p.position).distance_to(n))
		print("  %s straight at NPC1 from 1.3 m: closest %.3f m (block %.2f), end z offset %.2f" % [c[0], closest, s.NPC_BLOCK, p.position.z - n.y])
		await tick(10)
	stop_grid("road grid NPC0", npcs[0], Vector2(1.2, 1.2), 0.05)
	stop_grid("road grid NPC1", npcs[1], Vector2(1.2, 1.2), 0.05)
	stop_grid("plaza grid NPC3", npcs[3], Vector2(1.2, 1.2), 0.05)
	stop_grid("yard (door path)", Vector2(-2.0, -7.5), Vector2(1.5, 1.5), 0.05)
	print("DONE")
	quit(0)

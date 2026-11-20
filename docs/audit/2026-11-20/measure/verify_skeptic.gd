## 반박 검증(E): (1) 발 미끄러짐을 발목 대신 발끝·더 좁은 띠로 다시 잰다
## (2) 집·길 키 방향 어긋남을 '고정 screen_forward' 와 '지금 카메라 방향으로 다시 계산' 두 경우로 비교
## (3) 대시 root 이동의 시간 분포(움직이는 구간 속도)
extends SceneTree

const MAX_TICKS := 120 * 60
const DT := 1.0 / 120.0
const KEYS := ["move_forward", "move_back", "turn_left", "turn_right", "attack", "backstep", "guard", "sanjae"]
var ticks := 0
var s: Node
var p: RamPlayer
var cam: Camera3D
var vp := Vector2(1152, 648)


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


func scr(w: Vector3) -> Vector2:
	var v := cam.unproject_position(w) / vp
	v.x = 0.5 + (v.x - 0.5) * (vp.x / vp.y) / (1152.0 / 648.0)
	return v


func dev_for(sf: Vector3) -> Array:
	var out := []
	for v in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		var dir: Vector3 = (sf.cross(Vector3.UP) * v.x - sf * v.y).normalized()
		var a := scr(p.global_position + Vector3.UP * 0.5)
		var b := scr(p.global_position + Vector3.UP * 0.5 + dir * 0.3)
		var sd := (b - a) * Vector2(1152, 648)
		out.append(snappedf(rad_to_deg(absf(v.angle_to(sd.normalized()))), 0.1))
	return out


func cam_flat_forward() -> Vector3:
	var f := -cam.global_transform.basis.z
	return Vector3(f.x, 0, f.z).normalized()


func bone_world(n: String) -> Vector3:
	var sk := p._skeleton
	var i := sk.find_bone(n)
	return sk.global_transform * sk.get_bone_global_pose(i).origin


func _run() -> void:
	await tick(5)
	p = s.ram
	cam = s.cam
	vp = root.get_visible_rect().size
	s.skip_hatch()
	await tick(5)
	var sk := p._skeleton
	var names := []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
	print("bones: ", names)

	# (2) 집: 키 방향 어긋남, 고정 vs 지금 카메라 기준
	for spot in [Vector2(0.45, -0.35), Vector2(-2.3, 0.6), Vector2(2.4, 0.5), Vector2(1.5, -2.2)]:
		p.position = s.HOME_ORIGIN + Vector3(spot.x, 0.04, spot.y)
		for k in 30:
			s._home_camera(1.0)
		print("home (%.1f,%.1f) U/R/D/L fixed %s | per-frame cam %s | ram screen %s" % [spot.x, spot.y, dev_for(p.screen_forward), dev_for(cam_flat_forward()), scr(p.global_position + Vector3.UP * 0.5)])

	# (3) 대시 root 이동 분포: 애니메이션 트랙을 직접 샘플
	var anim: AnimationPlayer = p._anim
	for an in ["Dash", "Backstep"]:
		var a := anim.get_animation(an)
		var tr := -1
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_POSITION_3D and str(a.track_get_path(i)) == "RamRig/Skeleton3D:root":
				tr = i
		var prev := a.position_track_interpolate(tr, 0.0)
		var line := []
		var moving_t := 0.0
		var moving_d := 0.0
		var peak := 0.0
		var t := 0.0
		while t < a.length - 1e-6:
			var t2 := minf(t + 1.0 / 60.0, a.length)
			var q := a.position_track_interpolate(tr, t2)
			var sp := (q - prev).length() / (t2 - t)
			peak = maxf(peak, sp)
			if sp > 0.5:
				moving_t += t2 - t
				moving_d += (q - prev).length()
			line.append(snappedf(sp, 0.1))
			prev = q
			t = t2
		print("%s length %.3f s, root speed per 1/60 s %s" % [an, a.length, line])
		print("  moving(>0.5 m/s) %.3f s covering %.2f m -> %.2f m/s, peak %.2f, total %.2f m" % [moving_t, moving_d, moving_d / maxf(moving_t, 0.001), peak, (a.position_track_interpolate(tr, a.length) - a.position_track_interpolate(tr, 0.0)).length()])

	# (1) 길: 정상 달리기 발 미끄러짐, 발목·발끝·띠 폭별
	s._enter(s.Stage.ROAD)
	await tick(5)
	p.position = Vector3(0, 0.04, -6.0)
	s._last_pos = p.position
	cam = s.cam
	await tick(5)
	# (2b) 길 키 방향
	for spot in [Vector3(0, 0, -10), Vector3(1.5, 0, -10)]:
		p.position = Vector3(spot.x, 0.04, spot.z)
		s._last_pos = p.position
		for k in 60:
			s._follow_camera(1.0)
		print("road (%.1f,%.1f) U/R/D/L fixed %s | per-frame cam %s" % [spot.x, spot.z, dev_for(p.screen_forward), dev_for(cam_flat_forward())])
	p.position = Vector3(0, 0.04, -6.0)
	s._last_pos = p.position
	await tick(5)
	press(["move_forward"])
	await tick(60)
	var bones := ["foot.L", "foot.R"]
	var toes := []
	for n in names:
		if String(n).to_lower().contains("toe"):
			toes.append(n)
	var rec := {}
	for b in bones + toes:
		rec[b] = []
	var body := []
	var prevb := p.global_position
	for i in 240:
		await tick()
		for b in bones + toes:
			rec[b].append(bone_world(b))
		body.append(Vector2(p.global_position.x - prevb.x, p.global_position.z - prevb.z).length() / DT)
		prevb = p.global_position
	press([])
	var bsp := 0.0
	for v in body:
		bsp += v
	bsp /= body.size()
	print("body speed %.2f m/s, toes found %s" % [bsp, toes])
	for b in bones + toes:
		var arr: Array = rec[b]
		var miny := 1e9
		for v in arr:
			miny = minf(miny, v.y)
		for band in [0.005, 0.01, 0.02]:
			var sum := 0.0
			var n := 0
			for i in range(1, arr.size()):
				var a: Vector3 = arr[i - 1]
				var c: Vector3 = arr[i]
				if a.y < miny + band and c.y < miny + band:
					sum += Vector2(c.x - a.x, c.z - a.z).length() / DT
					n += 1
			print("  %-10s band %.3f m: planted ticks %d/%d, world speed %.2f m/s = %.0f%% of body" % [b, band, n, arr.size() - 1, sum / maxf(1, n), sum / maxf(1, n) / bsp * 100.0])
	# 한 걸음 중 가장 느린 순간(발이 땅에 가장 붙어 있는 순간) 속도: 매 걸음 최솟값의 중앙값
	for b in bones + toes:
		var arr: Array = rec[b]
		var sp := []
		for i in range(1, arr.size()):
			sp.append(Vector2(arr[i].x - arr[i - 1].x, arr[i].z - arr[i - 1].z).length() / DT)
		var mins := []
		var w := 20
		var i0 := 0
		while i0 + w <= sp.size():
			var m := 1e9
			for j in range(i0, i0 + w):
				m = minf(m, sp[j])
			mins.append(m)
			i0 += w
		mins.sort()
		print("  %-10s min world speed per 1/6 s window, median %.2f m/s" % [b, mins[mins.size() / 2]])
	print("DONE")
	quit(0)

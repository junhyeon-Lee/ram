## 발 미끄러짐: 실제 게임 안에서 디딘 발(발목 뼈가 그 동작 중 가장 낮은 높이 + 2cm 안)이 월드에서 얼마나 움직이는가.
## 완전히 디디면 0 m/s. 몸 속도 대비 % 로도 적는다.
extends SceneTree

const MAX_TICKS := 120 * 120
const DT := 1.0 / 120.0
const KEYS := ["move_forward", "move_back", "turn_left", "turn_right", "attack", "backstep", "guard", "sanjae"]
const BAND := 0.02
var ticks := 0
var root_scene: Node
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


func feet_world() -> Array:
	var sk := p._skeleton
	return [sk.global_transform * sk.get_bone_global_pose(sk.find_bone("foot.L")).origin,
		sk.global_transform * sk.get_bone_global_pose(sk.find_bone("foot.R")).origin]


## n 틱 기록 → 디딘 발 미끄러짐
func sample(label: String, n: int, skip := 0) -> void:
	var rec := []
	var body := []
	var prevb := p.global_position
	for i in n:
		await tick()
		var f := feet_world()
		rec.append(f)
		body.append(Vector2(p.global_position.x - prevb.x, p.global_position.z - prevb.z).length() / DT)
		prevb = p.global_position
	var slip_sum := 0.0
	var slip_n := 0
	var signed := 0.0
	var bsum := 0.0
	for side in 2:
		var miny := 1e9
		for i in range(skip, n):
			miny = minf(miny, rec[i][side].y)
		for i in range(skip + 1, n):
			var a: Vector3 = rec[i - 1][side]
			var b: Vector3 = rec[i][side]
			if a.y < miny + BAND and b.y < miny + BAND:
				slip_sum += Vector2(b.x - a.x, b.z - a.z).length() / DT
				signed += (b - a).dot(-p.global_transform.basis.z) / DT
				slip_n += 1
				bsum += body[i]
	var slip := slip_sum / maxf(1, slip_n)
	var bspd := bsum / maxf(1, slip_n)
	print("  %-40s planted-foot world speed %.2f m/s (body %.2f m/s, slip = %.0f%% of body speed), planted ticks %d/%d, planted foot along body facing %+.2f m/s" % [label, slip, bspd, slip / maxf(0.01, bspd) * 100.0, slip_n, 2 * (n - skip), signed / maxf(1, slip_n)])


func _run() -> void:
	root_scene = load("res://game/main.tscn").instantiate()
	root.add_child(root_scene)
	await tick(30)
	p = root_scene.player
	var cam: FollowCamera = root_scene.get_node("Camera")
	print("--- test floor (turn + forward/back)")
	p.global_position = Vector3(-5.5, 0.05, 9.0)
	await tick(20)
	press(["move_forward"])
	await sample("Idle->Run first 0.25 s (blend)", 30)
	await sample("Run steady (tank)", 120)
	press(["move_back"])
	await tick(30)
	await sample("Walk backward steady (tank)", 120)
	press(["turn_left"])
	await tick(30)
	await sample("Turn in place (Walk, no travel)", 120)
	press([])
	await tick(40)
	p.global_position = Vector3(-6.2, 0.05, 6.0)
	p.rotation.y = deg_to_rad(90)
	cam._yaw = p.rotation.y
	await tick(10)
	press(["move_forward"])
	await tick(30)
	await sample("Run into wall head-on (stopped)", 60)
	press([])
	await tick(30)
	p.global_position = Vector3(-5.5, 0.05, 8.0)
	p.rotation.y = 0.0
	await tick(10)
	press(["move_forward"])
	await tick(40)
	press(["move_forward", "backstep"])
	await tick(8)
	press([])
	await sample("Backstep (root motion)", 70)
	await tick(30)
	root_scene.queue_free()
	await tick(5)

	print("--- commute (free move)")
	root_scene = load("res://game/commute/commute.tscn").instantiate()
	root.add_child(root_scene)
	await tick(5)
	p = root_scene.ram
	root_scene.skip_hatch()
	await tick(5)
	root_scene._enter(root_scene.Stage.ROAD)
	await tick(5)
	p.position = Vector3(0, 0.04, -6.0)
	root_scene._last_pos = p.position
	await tick(5)
	press(["move_forward"])
	await sample("Idle->Run first 0.25 s (free)", 30)
	await sample("Run steady (free)", 120)
	press(["move_back"])
	await sample("180 reversal first 0.25 s", 30)
	press(["move_back", "turn_right"])
	await sample("45 deg turn first 0.25 s", 30)
	press(["turn_right"])
	await tick(60)
	await sample("Run into curb (Right, stopped)", 60)
	p.position = Vector3(1.5, 0.04, -10.0)
	root_scene._last_pos = p.position
	press(["move_forward", "turn_right"])
	await tick(30)
	await sample("Slide along curb (Up+Right, 71% speed)", 60)
	press([])
	await tick(30)
	p.position = Vector3(0, 0.04, -12.0)
	root_scene._last_pos = p.position
	await tick(5)
	press(["move_forward", "backstep"])
	await tick(8)
	press([])
	await sample("Dash (root motion)", 60)
	print("DONE")
	quit(0)

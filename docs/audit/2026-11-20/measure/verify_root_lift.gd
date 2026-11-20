## 반박 검증(E): 동작 속 root 뼈의 높이(Blender z = Godot y) 이동이 게임 화면에 남는가
## 트랙 값(애니메이션 데이터)과 게임 안 root 뼈·몸·골반 높이를 나란히 찍는다.
extends SceneTree

const MAX_TICKS := 120 * 40
var ticks := 0
var m: Node
var p: RamPlayer


func _initialize() -> void:
	m = load("res://game/main.tscn").instantiate()
	root.add_child(m)
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


func _run() -> void:
	await tick(30)
	p = m.player
	var sk := p._skeleton
	var ri := sk.find_bone("root")
	var pi := sk.find_bone("pelvis")
	for an in ["Backstep", "Dash", "Attack_RearSlam"]:
		p.global_position = Vector3(0, 0.05, 8.5)
		await tick(60)
		var a := p._anim.get_animation(an)
		var tr := -1
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_POSITION_3D and str(a.track_get_path(i)) == "RamRig/Skeleton3D:root":
				tr = i
		var track_max := -1e9
		var t := 0.0
		while t <= a.length:
			track_max = maxf(track_max, a.position_track_interpolate(tr, t).y)
			t += 1.0 / 120.0
		var base_pelvis := (sk.global_transform * sk.get_bone_global_pose(pi).origin).y
		p._start_action(an)
		var root_max := -1e9
		var root_min := 1e9
		var pel_max := -1e9
		var body_max := -1e9
		for i in int(a.length * 120.0):
			await tick()
			var ry := sk.get_bone_pose_position(ri).y
			root_max = maxf(root_max, ry)
			root_min = minf(root_min, ry)
			pel_max = maxf(pel_max, (sk.global_transform * sk.get_bone_global_pose(pi).origin).y)
			body_max = maxf(body_max, p.global_position.y)
		print("%s: root track y max %.3f (track rest %.3f) | in game root bone pose y %.3f..%.3f | pelvis world y rise %.3f m | body y max %.3f" % [an, track_max, a.position_track_interpolate(tr, 0.0).y, root_min, root_max, pel_max - base_pelvis, body_max])
	print("DONE")
	quit(0)

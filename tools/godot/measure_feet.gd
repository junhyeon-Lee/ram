## 발 측정 도구: 동작마다 (1) 디딘 발이 몸 기준으로 뒤로 미는 속도, (2) 발목이 가장 낮게 내려가는 높이.
## (1) 은 player.gd 의 WALK_FOOT_SPEED·RUN_FOOT_SPEED 에 넣는다 (이동 속도와 맞춰 발 미끄러짐을 없앰).
## 달리기는 가장 낮은 순간이 한 걸음의 10% 뿐이라 'near-ground mean'(땅 가까이 평균)의 가운데 값을 쓴다.
## 실행: godot --headless --path . --script tools/godot/measure_feet.gd
extends SceneTree

var n: Node3D
var ap: AnimationPlayer
var sk: Skeleton3D
var feet := []
var anims: Array = []
var ai := 0
var i := 0
const N := 240
var samples := []


func _initialize() -> void:
	n = load("res://assets/characters/ram/ram_rigged.glb").instantiate()
	root.add_child(n)
	ap = n.find_child("AnimationPlayer", true, false)
	ap.root_motion_track = NodePath("RamRig/Skeleton3D:root")   # 게임과 같게: root 이동은 빼고 잰다
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	sk = n.find_child("Skeleton3D", true, false)
	feet = [sk.find_bone("foot.L"), sk.find_bone("foot.R")]
	anims = Array(ap.get_animation_list())


func _process(_d: float) -> bool:
	if ai >= anims.size():
		quit()
		return true
	var anim: String = anims[ai]
	var a := ap.get_animation(anim)
	if i == 0:
		ap.play(anim)
		samples = []
	var t := a.length * i / N
	ap.seek(t, true)
	ap.advance(0)
	sk.force_update_all_bone_transforms()
	samples.append([t, sk.get_bone_global_pose(feet[0]).origin, sk.get_bone_global_pose(feet[1]).origin])
	i += 1
	if i > N:
		var miny := 1e9
		for s in samples:
			miny = minf(miny, minf(s[1].y, s[2].y))
		var spd := []
		for k in N:
			var p0: Vector3 = samples[k][1]
			var p1: Vector3 = samples[k + 1][1]
			if p0.y < miny + 0.02 and p1.y < miny + 0.02:
				spd.append(absf(p1.z - p0.z) / (samples[k + 1][0] - samples[k][0]))
		spd.sort()
		var med: float = spd[spd.size() / 2] if spd.size() > 0 else 0.0
		# 땅 가까이(가장 낮은 높이 + 4cm, 8cm 안)에 있는 동안의 평균: 눈에 '디디고 있는' 구간 전체
		var near := []
		for band in [0.04, 0.08]:
			var travel := 0.0
			var time := 0.0
			for k in N:
				var q0: Vector3 = samples[k][1]
				var q1: Vector3 = samples[k + 1][1]
				if q0.y < miny + band and q1.y < miny + band:
					travel += absf(q1.z - q0.z)
					time += samples[k + 1][0] - samples[k][0]
			near.append(travel / time if time > 0.0 else 0.0)
		print("%-18s len=%.2fs  stance foot speed=%.2f m/s  near-ground mean=%.2f~%.2f m/s  lowest ankle=%.3f m" % [anim, a.length, med, minf(near[0], near[1]), maxf(near[0], near[1]), miny])
		ai += 1
		i = 0
	return false

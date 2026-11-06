## 박치기가 맞는 순간: 로우폴리 파편(작은 상자)과 먼지가 튄다. 세기에 따라 양이 달라지고 스스로 사라진다.
class_name ImpactFx
extends Node3D

static var spawned := 0               # 점검용


static func spawn(parent: Node, pos: Vector3, strength: float) -> void:
	var fx := ImpactFx.new()
	parent.add_child(fx)
	fx.global_position = pos
	fx._emit(strength)
	spawned += 1


func _emit(strength: float) -> void:
	add_child(_burst(int(10 + 22 * strength), Color(0.93, 0.90, 0.82), 0.06, 4.5 * (0.6 + strength), 0.35))  # 돌 파편
	add_child(_burst(int(6 + 10 * strength), Color(0.62, 0.62, 0.66), 0.12, 1.6, 0.6))                     # 먼지
	get_tree().create_timer(1.2, false).timeout.connect(queue_free)


func _burst(amount: int, color: Color, size: float, speed: float, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -12, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mesh.material = mat
	p.mesh = mesh
	p.emitting = true
	return p

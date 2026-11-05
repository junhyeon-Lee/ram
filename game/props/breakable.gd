## 박치기로 날려 버리는 사무실 집기 (시험용 상자). 세 번 맞으면 부서져 사라진다.
class_name Breakable
extends RigidBody3D

signal broken

@export var hits_to_break := 3

var hits := 0


## kick: 줄 속도 변화(m/s). 무게를 곱해 충격량으로 바꾼다
func take_headbutt(kick: Vector3) -> void:
	hits += 1
	apply_central_impulse(kick * mass)
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 2.0)
	if hits >= hits_to_break:
		broken.emit()
		queue_free()

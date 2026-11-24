## 박치기로 날려 버리는 사무실 집기 (시험용 상자). 받은 타격이 hits_to_break 에 닿으면 부서져 사라진다.
## 가벼운 박치기는 1, 날리는 박치기(피니시·돌진)는 2 를 깎는다 → 가볍게 세 번 + 피니시에서 부서진다.
class_name Breakable
extends RigidBody3D

signal broken

@export var hits_to_break := 4

var hits := 0                         # 지금까지 받은 타격 (가벼운 타 1, 날리는 타 2)

# 히트스톱 동안 맞은 쪽은 완전히 멈추지 않고 이 비율로만 움직이다가, 끝나면 나머지 힘을 받는다
# (2026-11-24, 시푸 데이터 참고: 멈춘 동안 맞은 쪽 피격 동작을 0.2배로 재생한다)
const FROZEN_RATE := 0.2


## kick: 줄 속도 변화(m/s). 무게를 곱해 충격량으로 바꾼다.
## damage: 깎는 양. stop: 히트스톱(실제 초).
func take_headbutt(kick: Vector3, damage := 1, stop := 0.0) -> void:
	hits += damage
	if hits >= hits_to_break:
		broken.emit()
		queue_free()
		return
	if stop <= 0.0:
		_kick(kick, true)
		return
	_kick(kick * FROZEN_RATE, false)
	# 산재비스탄으로 시간이 느려져도 히트스톱은 실제 시간으로 센다
	await get_tree().create_timer(stop, true, true, true).timeout
	if is_inside_tree():
		_kick(kick * (1.0 - FROZEN_RATE), true)


func _kick(kick: Vector3, spin_too: bool) -> void:
	apply_central_impulse(kick * mass)
	if not spin_too:
		return
	# 살짝 민 것은 거의 돌지 않게, 날린 것은 크게 구르게
	var spin := clampf(kick.length() / 6.5, 0.1, 1.0) * 2.0
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spin)

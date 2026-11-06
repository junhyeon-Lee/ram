## 등 뒤 카메라: 캐릭터가 도는 방향을 따라 살짝 늦게 같이 돈다 (마우스 안 씀)
class_name FollowCamera
extends Camera3D

@export var target: Node3D
@export var distance := 4.2
@export var height := 2.3
@export var look_ahead := 1.6         # 캐릭터보다 이만큼 앞을 본다
@export var look_height := 0.9
@export var yaw_follow := 5.0         # 클수록 빨리 따라 돈다
@export var pos_follow := 10.0
@export var wall_margin := 0.25       # 벽에 막히면 벽 안쪽으로 이만큼 띄운다

var _yaw := 0.0


func _ready() -> void:
	if target:
		_yaw = target.global_rotation.y
		global_position = _desired_position()


func _physics_process(delta: float) -> void:
	if not target:
		return
	# 산재비스탄 중에도 카메라는 실제 시간으로 움직여야 화면이 끈적이지 않는다
	var real_delta := delta / Engine.time_scale
	_yaw = lerp_angle(_yaw, target.global_rotation.y, 1.0 - exp(-yaw_follow * real_delta))
	var next := global_position.lerp(_desired_position(), 1.0 - exp(-pos_follow * real_delta))
	# 벽에 막히면 곧바로 벽 안쪽으로 당기고, 벗어나면 위 lerp 로 천천히 원래 거리로 돌아간다
	global_position = _clear_of_walls(next)
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	look_at(target.global_position + fwd * look_ahead + Vector3.UP * look_height)


func _desired_position() -> Vector3:
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	return target.global_position + back * distance + Vector3.UP * height


## Ram 몸 가운데에서 pos 까지 벽(StaticBody3D)이 막으면 벽 안쪽 자리를 돌려준다.
## 책상 같은 움직이는 집기는 건너뛴다(카메라가 들썩이지 않게).
func _clear_of_walls(pos: Vector3) -> Vector3:
	var pivot := target.global_position + Vector3.UP * look_height
	var q := PhysicsRayQueryParameters3D.create(pivot, pos)
	var exclude: Array[RID] = []
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	var space := get_world_3d().direct_space_state
	for i in 4:
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return pos
		if hit.collider is StaticBody3D:
			return hit.position + hit.normal * wall_margin
		exclude.append(hit.rid)
	return pos

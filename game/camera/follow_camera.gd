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
	global_position = global_position.lerp(_desired_position(), 1.0 - exp(-pos_follow * real_delta))
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	look_at(target.global_position + fwd * look_ahead + Vector3.UP * look_height)


func _desired_position() -> Vector3:
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	return target.global_position + back * distance + Vector3.UP * height

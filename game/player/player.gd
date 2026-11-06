## Ram — 플레이어 조작
## 방향키: 위·아래 앞뒤 이동, 좌우 몸 돌리기 (카메라가 따라 돈다)
## Space 박치기 · E 꼬리 패링 · Shift 백스텝 · R 산재비스탄(시간 감속)
class_name RamPlayer
extends CharacterBody3D

signal sanjae_changed(gauge: float, active: bool)
signal hp_changed(hp: float)

const RAM_SCENE := preload("res://assets/characters/ram/ram_rigged.glb")

@export var forward_speed := 3.2      # m/s
@export var back_speed := 1.8
@export var turn_speed_deg := 150.0   # 도/초
@export var gravity := 20.0

# 박치기 판정: 동작 시작 후 이 구간(초)에 머리 앞을 한 번 검사한다
const HIT_WINDOW := Vector2(0.36, 0.52)
const HIT_RADIUS := 0.75
const HIT_REACH := 1.2
const HIT_KICK := 6.5                 # 맞은 물체에 주는 속도 변화 (m/s, 무게와 상관없이)

# 산재비스탄: 주변(과 9시 시계)을 느리게, Ram 은 그대로. 쓸 때마다 체력이 조금 깎인다(산재).
const SANJAE_SCALE := 0.3
const SANJAE_REAL_SECONDS := 3.0
const SANJAE_HP_COST := 5.0
const SANJAE_RECHARGE := 0.12        # 실제 1초당 게이지 회복

enum State { MOVE, ACTION }

var hp := 100.0
var sanjae_gauge := 1.0
var _sanjae_left := 0.0
var _state := State.MOVE
var _action_time := 0.0
var _hit_done := false
var _current_action := ""

var _model: Node3D
var _anim: AnimationPlayer
var _root_rot_track := {}            # 동작 이름 → root 뼈 회전 트랙 번호
var _spin_prev := 0.0
var _visual_spin := 0.0                # 겉모습만 도는 회전 (몸·카메라는 그대로)

# 이 동작들의 회전은 모델 겉모습에만 준다: 제자리에서 돌고 원래 방향으로 끝나므로
# 몸 방향(이동·카메라 기준)을 돌리면 카메라까지 같이 돌아 화면이 어지럽다.
const VISUAL_SPIN_ACTIONS := ["Parry_Tail"]


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.3
	shape.shape = capsule
	shape.position = Vector3(0, 0.65, 0)
	add_child(shape)

	_model = RAM_SCENE.instantiate()
	# 모델은 +Z 를 보고 있다(Blender 의 -Y 정면). Godot 의 정면 -Z 로 돌린다.
	_model.rotation.y = PI
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	# 대시·백스텝·패링은 root 뼈가 움직인다 → 그 움직임을 몸(CharacterBody) 이동으로 옮긴다
	_anim.root_motion_track = NodePath("RamRig/Skeleton3D:root")
	_anim.animation_finished.connect(_on_animation_finished)
	for anim_name in _anim.get_animation_list():
		var a := _anim.get_animation(anim_name)
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_ROTATION_3D and str(a.track_get_path(i)) == "RamRig/Skeleton3D:root":
				_root_rot_track[anim_name] = i
	_play("Idle")


func _physics_process(delta: float) -> void:
	# 산재비스탄 중에는 엔진 전체가 느려지지만 Ram 은 실제 시간으로 움직인다
	var real_delta := delta / Engine.time_scale
	_update_sanjae(real_delta)

	if not is_on_floor():
		velocity.y -= gravity * real_delta
	else:
		velocity.y = 0.0

	match _state:
		State.MOVE:
			_move(real_delta)
		State.ACTION:
			_action(real_delta)

	# CharacterBody 는 엔진 delta 로 움직이므로, 느려진 만큼 속도를 키워 실제 속도를 지킨다
	var v := velocity
	velocity = v / Engine.time_scale
	move_and_slide()
	velocity = v


func _move(real_delta: float) -> void:
	var turn := Input.get_axis("turn_right", "turn_left")
	rotation.y += deg_to_rad(turn_speed_deg) * turn * real_delta

	var fwd := Input.get_axis("move_back", "move_forward")
	var speed := forward_speed if fwd > 0.0 else back_speed
	var dir := -global_transform.basis.z * fwd * speed
	velocity.x = dir.x
	velocity.z = dir.z

	if fwd > 0.1:
		_play("Run")
	elif fwd < -0.1 or absf(turn) > 0.1:
		_play("Walk")
	else:
		_play("Idle")

	if Input.is_action_just_pressed("attack"):
		_start_action("Attack_Slam")
	elif Input.is_action_just_pressed("backstep"):
		_start_action("Backstep")
	elif Input.is_action_just_pressed("guard"):
		_start_action("Parry_Tail")
	elif Input.is_action_just_pressed("sanjae"):
		activate_sanjae()


func _start_action(anim_name: String) -> void:
	_state = State.ACTION
	_current_action = anim_name
	_action_time = 0.0
	_hit_done = false
	_play(anim_name, 0.05)
	_spin_prev = _root_yaw()
	_visual_spin = 0.0
	_model.rotation.y = PI


func _action(real_delta: float) -> void:
	_action_time += real_delta
	# root motion: 이번 프레임에 root 뼈가 움직인 만큼 몸을 옮기고 돌린다
	var rm_pos := _anim.get_root_motion_position()
	var world_step := _model.global_transform.basis * rm_pos
	velocity.x = world_step.x / real_delta
	velocity.z = world_step.z / real_delta
	# 회전은 root motion 변화량 대신 동작 속 root 뼈의 절대 방향을 읽어 차이만큼 돌린다.
	# (Godot 의 회전 변화량은 뼈 좌표계 기준이고, 180° 지점에서 쿼터니언 부호가 뒤집혀 튄다)
	var yaw := _root_yaw()
	var dyaw := wrapf(yaw - _spin_prev, -PI, PI)
	_spin_prev = yaw
	if _current_action in VISUAL_SPIN_ACTIONS:
		_visual_spin += dyaw
		_model.rotation.y = PI + _visual_spin
	else:
		rotate_y(dyaw)

	if _current_action.begins_with("Attack") and not _hit_done \
			and _action_time >= HIT_WINDOW.x and _action_time <= HIT_WINDOW.y:
		_hit_done = true
		_headbutt_hit()


func _headbutt_hit() -> void:
	var forward := -global_transform.basis.z
	var center := global_position + forward * HIT_REACH + Vector3.UP * 0.8
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = HIT_RADIUS
	query.shape = sphere
	query.transform = Transform3D(Basis(), center)
	query.exclude = [get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var body: Object = hit.collider
		if body.has_method("take_headbutt"):
			body.take_headbutt(forward * HIT_KICK + Vector3.UP * HIT_KICK * 0.35)


func activate_sanjae() -> void:
	if sanjae_gauge < 1.0 or _sanjae_left > 0.0:
		return
	sanjae_gauge = 0.0
	_sanjae_left = SANJAE_REAL_SECONDS
	Engine.time_scale = SANJAE_SCALE
	_anim.speed_scale = 1.0 / SANJAE_SCALE
	hp = maxf(1.0, hp - SANJAE_HP_COST)   # 산재: 몸이 상한다 (끌려가지는 않음)
	hp_changed.emit(hp)


func _update_sanjae(real_delta: float) -> void:
	if _sanjae_left > 0.0:
		_sanjae_left -= real_delta
		if _sanjae_left <= 0.0:
			_sanjae_left = 0.0
			Engine.time_scale = 1.0
			_anim.speed_scale = 1.0
	else:
		sanjae_gauge = minf(1.0, sanjae_gauge + SANJAE_RECHARGE * real_delta)
	sanjae_changed.emit(sanjae_gauge, _sanjae_left > 0.0)


func _on_animation_finished(anim_name: StringName) -> void:
	if _state == State.ACTION and anim_name == _current_action:
		_state = State.MOVE
		_current_action = ""
		_visual_spin = 0.0
		_model.rotation.y = PI
		velocity.x = 0.0
		velocity.z = 0.0


## 지금 동작 속 root 뼈가 수직축으로 얼마나 돌아 있는지 (라디안, 반시계 +)
func _root_yaw() -> float:
	var anim_name := String(_anim.current_animation)
	if not _root_rot_track.has(anim_name):
		return 0.0
	var a := _anim.get_animation(anim_name)
	var q := a.rotation_track_interpolate(_root_rot_track[anim_name], _anim.current_animation_position)
	# root 뼈의 축(Y)이 쉬는 자세에서 (0,0,-1)을 향한다. 수직축으로 θ 돌면 (-sinθ, 0, -cosθ)
	var v := Basis(q) * Vector3.UP
	return atan2(-v.x, -v.z)


func _play(anim_name: String, blend := 0.15) -> void:
	if _anim.current_animation != anim_name:
		_anim.play(anim_name, blend)


func _exit_tree() -> void:
	Engine.time_scale = 1.0

## Ram — 플레이어 조작
## 방향키: 위·아래 앞뒤 이동, 좌우 몸 돌리기 (카메라가 따라 돈다)
## Space 박치기(4종 번갈아, 맞은 뒤 다시 누르면 콤보, 길게 누르면 피니시, 위+Space 돌진)
## E 공중제비 꼬리 패링 · Shift 백스텝 · R 산재비스탄(시간 감속)
## 자유 이동(free_move, 집·출근길 장면): 방향키가 화면 기준 여덟 방향 달리기가 된다.
##   방향키+Space 돌진, 방향키+Shift 그 방향으로 대시, Shift 만 누르면 백스텝. 나머지는 같다.
class_name RamPlayer
extends CharacterBody3D

signal sanjae_changed(gauge: float, active: bool)
signal hp_changed(hp: float)
signal combo_changed(step: int)

const RAM_SCENE := preload("res://assets/characters/ram/ram_rigged.glb")

@export var forward_speed := 3.5      # m/s
@export var back_speed := 1.8
@export var turn_speed_deg := 150.0   # 도/초
@export var gravity := 20.0

var free_move := false                 # 화면 기준 자유 이동 (끄면 돌기 + 앞뒤)
var screen_forward := Vector3.FORWARD  # 자유 이동에서 '위' 키가 가리키는 수평 방향
var input_enabled := true              # 끄면 조작을 받지 않고 서 있는다 (하던 동작은 끝까지 한다)
const FREE_TURN := 14.0                # 자유 이동에서 달리는 쪽으로 몸을 돌리는 빠르기

# 박치기 4종: Space 를 누를 때마다 넷이 겹치지 않게 번갈아 나온다 (docs/references/motion.md)
const ATTACK_VARIANTS := ["Attack_RearSlam", "Attack_LowCharge", "Attack_FlankButt", "Attack_Shove"]
# hits: 맞는 순간(동작 시작 후 초, Blender 프레임 기준 (f-1)/30), stop: 히트스톱(실제 초),
# shake: 화면 흔들림 세기, kick: 맞은 물체에 주는 속도 변화(m/s, 무게와 상관없이), up: 위로 띄우는 비율(기본 0.35)
const ATTACKS := {
	"Attack_RearSlam": {"hits": [0.50], "stop": 0.10, "shake": 0.22, "kick": 8.0},
	"Attack_LowCharge": {"hits": [0.333], "stop": 0.07, "shake": 0.15, "kick": 7.0},
	"Attack_FlankButt": {"hits": [0.367], "stop": 0.06, "shake": 0.12, "kick": 6.5},
	# 밀어붙이기는 날리지 않고 Ram 걸음(0.25m)만큼씩 밀고 간다: 약하게, 위로 띄우지 않게
	"Attack_Shove": {"hits": [0.367, 0.633, 0.90], "stop": 0.035, "shake": 0.06, "kick": 1.6, "up": 0.0},
	# 콤보 연결용 (첫 버전 박치기 재활용). 올려치기는 물체를 위로 띄운다
	"Attack_Hook": {"hits": [0.433], "stop": 0.06, "shake": 0.12, "kick": 6.5},
	"Attack_Uppercut": {"hits": [0.40], "stop": 0.06, "shake": 0.12, "kick": 5.0, "up": 1.2},
}

# 콤보 (시푸 참고, 1차 초안): 맞은 뒤 Space 를 다시 누르면 회복 동작을 끊고 다음 박치기로 잇는다.
# 4타째는 피니시(일어섰다 내리찍기, 더 세게). Space 를 길게 누르고 있으면 바로 피니시. 위+Space 는 돌진 공격.
const COMBO_MAX := 4
const COMBO_FINISHER := "Attack_RearSlam"
const COMBO_LINKS := ["Attack_FlankButt", "Attack_Hook", "Attack_Uppercut", "Attack_LowCharge"]
const DASH_ATTACK := "Attack_LowCharge"
const LINK_DELAY := 0.10              # 마지막 맞는 순간 뒤 이만큼 지나야 다음으로 이어진다
const HEAVY_HOLD := 0.35              # Space 를 이만큼 누르고 있으면 강공(피니시)
const FINISHER_BONUS := {"stop": 1.5, "shake": 1.4, "kick": 1.3}
const HIT_RADIUS := 0.75              # 돌머리 둘레 판정 반지름

# 애니메이션 속 디딘 발이 땅을 미는 속도 (tools/godot/measure_feet.gd 로 잼). 동작을 바꾸면 다시 잰다.
# 이동 속도에 맞춰 재생 속도를 바꿔 발이 미끄러지지 않게 한다.
# 달리기는 '땅 가까이 평균'(4.4~4.7)을 쓴다. 가장 낮은 순간의 중앙값(4.14)은 한 걸음의 10% 뿐이라,
# 그 값에 맞추면 다리가 몸보다 빨라 보인다("걷는 모션보다 움직임이 느린 느낌").
const RUN_FOOT_SPEED := 4.5
const WALK_FOOT_SPEED := 1.41

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
var _hits_done := 0                   # 이번 동작에서 지나간 '맞는 순간' 수
var _current_action := ""
var _attack_bag: Array = []
var _last_attack := ""
var _hitstop_left := 0.0
var hitstop_count := 0                # 점검용: 히트스톱이 걸린 횟수
var _skeleton: Skeleton3D
var _head_bone := -1
var feet: FootGrounder
var combo_step := 0                   # 지금 콤보 몇 타째 (0 = 콤보 아님)
var _queued := false                  # 다음 박치기 입력이 들어와 있음
var _queued_heavy := false
var _hold_time := 0.0
var _link_index := 0
var _is_finisher := false

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
	_skeleton = _model.find_child("Skeleton3D", true, false)
	feet = FootGrounder.attach(_skeleton, self)
	_setup_blends()
	_head_bone = _skeleton.find_bone("head")
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

	if _hitstop_left > 0.0:
		# 히트스톱: 맞은 순간 Ram 의 동작·이동을 잠깐 멈춘다 (타격감)
		_hitstop_left -= real_delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _hitstop_left <= 0.0:
			_anim.speed_scale = _base_anim_speed()
	else:
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
	if not input_enabled:
		velocity.x = 0.0
		velocity.z = 0.0
		_play("Idle")
		_anim.speed_scale = _base_anim_speed()
		return
	var dir := Vector3.ZERO                       # 자유 이동에서 누르고 있는 방향
	if free_move:
		dir = _move_free(real_delta)
	else:
		_move_tank(real_delta)
	var pushing := dir != Vector3.ZERO if free_move else Input.is_action_pressed("move_forward")

	if Input.is_action_just_pressed("attack"):
		combo_step = 1
		_face(dir)
		# 방향키(자유 이동이 아니면 위)+Space 는 돌진 공격, 그냥 Space 는 4종을 번갈아
		_start_attack(DASH_ATTACK if pushing else _next_attack())
	elif Input.is_action_just_pressed("backstep"):
		_face(dir)
		_start_action("Dash" if dir != Vector3.ZERO else "Backstep")
	elif Input.is_action_just_pressed("guard"):
		_start_action("Parry_Tail")
	elif Input.is_action_just_pressed("sanjae"):
		activate_sanjae()


## 자유 이동: 누른 방향(화면 기준)으로 달리고 몸도 그쪽으로 돌린다. 누르고 있는 방향을 돌려준다.
func _move_free(real_delta: float) -> Vector3:
	var v := Input.get_vector("turn_left", "turn_right", "move_forward", "move_back")
	var dir := screen_forward.cross(Vector3.UP) * v.x - screen_forward * v.y
	if dir.length() < 0.1:
		velocity.x = 0.0
		velocity.z = 0.0
		_play("Idle")
		_anim.speed_scale = _base_anim_speed()
		return Vector3.ZERO
	dir = dir.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-FREE_TURN * real_delta))
	velocity.x = dir.x * forward_speed
	velocity.z = dir.z * forward_speed
	_play("Run")
	_anim.speed_scale = _base_anim_speed() * forward_speed / RUN_FOOT_SPEED
	return dir


## 몸(정면 -Z)을 수평 방향 dir 로 바로 돌린다
func _face(dir: Vector3) -> void:
	if dir != Vector3.ZERO:
		rotation.y = atan2(-dir.x, -dir.z)


## 연출용: 장면이 몸을 직접 움직이는 동안(physics 를 꺼 둔 동안) 동작만 튼다
func play_clip(anim_name: String, from := 0.0) -> void:
	_anim.speed_scale = 1.0
	_anim.play(anim_name, 0.0)
	_anim.seek(from, true)


## 연출용: 겉모습만 키우거나 줄인다 (충돌 몸은 그대로)
func set_model_scale(s: float) -> void:
	_model.scale = Vector3.ONE * s


func _move_tank(real_delta: float) -> void:
	var turn := Input.get_axis("turn_right", "turn_left")
	rotation.y += deg_to_rad(turn_speed_deg) * turn * real_delta

	var fwd := Input.get_axis("move_back", "move_forward")
	var speed := forward_speed if fwd > 0.0 else back_speed
	var dir := -global_transform.basis.z * fwd * speed
	velocity.x = dir.x
	velocity.z = dir.z

	# 재생 속도를 이동 속도에 맞춘다 (발 미끄러짐 방지). 제자리 돌기는 원래 속도.
	if fwd > 0.1:
		_play("Run")
		_anim.speed_scale = _base_anim_speed() * forward_speed * fwd / RUN_FOOT_SPEED
	elif fwd < -0.1:
		_play("Walk")
		_anim.speed_scale = _base_anim_speed() * back_speed * -fwd / WALK_FOOT_SPEED
	elif absf(turn) > 0.1:
		_play("Walk")
		_anim.speed_scale = _base_anim_speed()
	else:
		_play("Idle")
		_anim.speed_scale = _base_anim_speed()


func _start_action(anim_name: String, blend := 0.05) -> void:
	_anim.speed_scale = _base_anim_speed()
	_state = State.ACTION
	_current_action = anim_name
	_action_time = 0.0
	_hits_done = 0
	_anim.play(anim_name, blend)   # 같은 동작을 연달아 써도 처음부터
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

	var spec: Dictionary = ATTACKS.get(_current_action, {})
	var hits: Array = spec.get("hits", [])
	if _hits_done < hits.size() and _action_time >= hits[_hits_done]:
		_hits_done += 1
		_headbutt_hit(spec)
	if not hits.is_empty():
		_update_combo(real_delta, hits)


func _start_attack(anim_name: String) -> void:
	_queued = false
	_queued_heavy = false
	_hold_time = 0.0
	_is_finisher = anim_name == COMBO_FINISHER and combo_step >= 2
	_start_action(anim_name, 0.05)
	combo_changed.emit(combo_step)
	Sfx.play_at(get_parent(), Sfx.whoosh(), global_position + Vector3.UP, -6.0, randf_range(0.9, 1.15))


## 콤보: 다음 입력을 모아 두었다가, 마지막 맞는 순간이 지나면 회복 동작을 끊고 잇는다
func _update_combo(real_delta: float, hits: Array) -> void:
	if Input.is_action_just_pressed("attack"):
		_queued = true
	if Input.is_action_pressed("attack"):
		_hold_time += real_delta
		if _hold_time >= HEAVY_HOLD and combo_step < COMBO_MAX:
			_queued = true
			_queued_heavy = true
	else:
		_hold_time = 0.0
	if _queued and combo_step < COMBO_MAX and _hits_done >= hits.size() \
			and _action_time >= float(hits.back()) + LINK_DELAY:
		combo_step += 1
		var next: String
		if _queued_heavy or combo_step >= COMBO_MAX:
			next = COMBO_FINISHER
			combo_step = maxi(combo_step, 2)
		else:
			next = COMBO_LINKS[_link_index % COMBO_LINKS.size()]
			_link_index += 1
			if next == _current_action:
				next = COMBO_LINKS[_link_index % COMBO_LINKS.size()]
				_link_index += 1
		_start_attack(next)


## 다음 박치기: 네 가지를 섞어 한 바퀴씩 쓰고, 바로 앞과 같은 것은 연달아 나오지 않게 한다
func _next_attack() -> String:
	if _attack_bag.is_empty():
		_attack_bag = ATTACK_VARIANTS.duplicate()
		_attack_bag.shuffle()
		if _attack_bag[0] == _last_attack:
			_attack_bag.push_back(_attack_bag.pop_front())
	_last_attack = _attack_bag.pop_front()
	return _last_attack


## 돌머리 둘레를 검사해 맞은 물체를 날린다. 하나라도 맞으면 히트스톱 + 화면 흔들림.
func _headbutt_hit(spec: Dictionary) -> void:
	var head := _skeleton.get_bone_global_pose(_head_bone)
	# head 뼈는 목 끝에서 코끝 쪽으로 뻗는다. 돌머리 가운데는 뼈 시작점에서 조금 앞
	var dome := _skeleton.global_transform * (head.origin + head.basis.y.normalized() * 0.25)
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = HIT_RADIUS
	query.shape = sphere
	query.transform = Transform3D(Basis(), dome)
	query.exclude = [get_rid()]
	var kick: float = spec.get("kick", 6.5)
	var bonus := FINISHER_BONUS if _is_finisher else {"stop": 1.0, "shake": 1.0, "kick": 1.0}
	kick *= float(bonus["kick"])
	var landed := false
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var body: Object = hit.collider
		if body.has_method("take_headbutt"):
			# Ram 에서 맞은 물체 쪽으로 날린다 (옆구리 들이받기는 옆으로 날아간다)
			var dir: Vector3 = (body.global_position - global_position) * Vector3(1, 0, 1)
			if dir.length() < 0.01:
				dir = -global_transform.basis.z
			dir = dir.normalized()
			body.take_headbutt(dir * kick + Vector3.UP * kick * float(spec.get("up", 0.35)))
			landed = true
	if landed:
		var power: float = clampf(spec.get("stop", 0.05) * float(bonus["stop"]) / 0.1, 0.2, 1.5)
		ImpactFx.spawn(get_parent(), dome, power)
		# 소리 크기: 피니시가 겹쳐도 찢어지지 않게 1 아래로
		Sfx.play_at(get_parent(), Sfx.thud(), dome, linear_to_db(0.35 + 0.35 * power), randf_range(0.9, 1.1))
		_hitstop_left = spec.get("stop", 0.05) * float(bonus["stop"])
		hitstop_count += 1
		_anim.speed_scale = 0.0
		var cam := get_viewport().get_camera_3d()
		if cam and cam.has_method("add_shake"):
			cam.add_shake(spec.get("shake", 0.1) * float(bonus["shake"]))


func _base_anim_speed() -> float:
	return 1.0 / SANJAE_SCALE if _sanjae_left > 0.0 else 1.0


func activate_sanjae() -> void:
	if sanjae_gauge < 1.0 or _sanjae_left > 0.0:
		return
	sanjae_gauge = 0.0
	_sanjae_left = SANJAE_REAL_SECONDS
	Engine.time_scale = SANJAE_SCALE
	if _hitstop_left <= 0.0:
		_anim.speed_scale = 1.0 / SANJAE_SCALE
	hp = maxf(1.0, hp - SANJAE_HP_COST)   # 산재: 몸이 상한다 (끌려가지는 않음)
	hp_changed.emit(hp)


func _update_sanjae(real_delta: float) -> void:
	if _sanjae_left > 0.0:
		_sanjae_left -= real_delta
		if _sanjae_left <= 0.0:
			_sanjae_left = 0.0
			Engine.time_scale = 1.0
			if _hitstop_left <= 0.0:
				_anim.speed_scale = 1.0
	else:
		sanjae_gauge = minf(1.0, sanjae_gauge + SANJAE_RECHARGE * real_delta)
	sanjae_changed.emit(sanjae_gauge, _sanjae_left > 0.0)


func _on_animation_finished(anim_name: StringName) -> void:
	if _state == State.ACTION and anim_name == _current_action:
		_state = State.MOVE
		_current_action = ""
		if combo_step != 0:
			combo_step = 0
			_is_finisher = false
			combo_changed.emit(0)
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


## 동작 사이 섞는 시간. 걷기↔달리기↔대기는 부드럽게, 공격 끝 → 이동은 조금 빠르게.
func _setup_blends() -> void:
	_anim.playback_default_blend_time = 0.15
	var loco := ["Idle", "Walk", "Run"]
	for a in loco:
		for b in loco:
			if a != b:
				_anim.set_blend_time(a, b, 0.22)
	for act in _anim.get_animation_list():
		if not act in loco:
			for b in loco:
				_anim.set_blend_time(act, b, 0.12)


func _play(anim_name: String, blend := -1.0) -> void:
	if _anim.current_animation != anim_name:
		_anim.play(anim_name, blend)


func _exit_tree() -> void:
	Engine.time_scale = 1.0

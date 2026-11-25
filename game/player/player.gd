## Ram — 플레이어 조작
## 방향키: 위·아래 앞뒤 이동, 좌우 몸 돌리기 (카메라가 따라 돈다)
## Space 박치기(늘 같은 순서의 4타 콤보: 왼쪽 들이받기 → 오른쪽 후려치기 → 올려치기 → 내리찍기 피니시.
##   1~3타는 조금만 밀고 피니시가 날린다. 길게 누르면 바로 피니시, 위+Space 는 달려들며 여는 첫 타(돌진).
##   박치기마다 맞는 순간까지 앞의 대상 쪽으로 다가선다)
## E 공중제비 꼬리 패링 · Shift 백스텝 · R 산재비스탄(시간 감속, 동작 중에도 켜진다)
## 동작 중에 누른 Space·Shift·E 는 0.2초 기억했다가 할 수 있게 되는 순간 나간다.
##   박치기의 회복 구간은 Shift·E(맞는 순간 0.1초 뒤)와 방향키(0.3초 뒤)로 끊을 수 있다.
## 자유 이동(free_move, 집·출근길 장면): 방향키가 화면 기준 여덟 방향 달리기가 된다.
##   방향키+Space 돌진, 방향키+Shift 그 방향으로 대시, Shift 만 누르면 백스텝. 나머지는 같다.
class_name RamPlayer
extends CharacterBody3D

signal sanjae_changed(gauge: float, active: bool)
signal hp_changed(hp: float)
signal combo_changed(hits: int)       # 이번 콤보에서 실제로 맞은 수 (0 = 콤보 끝)

const RAM_SCENE := preload("res://assets/characters/ram/ram_rigged.glb")

@export var forward_speed := 3.5      # m/s
@export var back_speed := 1.8
@export var turn_speed_deg := 150.0   # 도/초
@export var gravity := 20.0

var free_move := false                 # 화면 기준 자유 이동 (끄면 돌기 + 앞뒤)
var screen_forward := Vector3.FORWARD  # 자유 이동에서 '위' 키가 가리키는 수평 방향
var input_enabled := true              # 끄면 조작을 받지 않고 서 있는다 (하던 동작은 끝까지 한다)
const FREE_TURN := 14.0                # 자유 이동에서 달리는 쪽으로 몸을 돌리는 빠르기

# 큰 박치기 4종 (docs/references/motion.md). 2026-11-21 부터 Space 는 이것을 무작위로 돌려 쓰지 않고
# 아래 COMBO_CHAIN 의 정해진 순서로 나간다. 밀어붙이기(Attack_Shove)는 지금 어떤 입력에도 걸려 있지 않다.
const ATTACK_VARIANTS := ["Attack_RearSlam", "Attack_LowCharge", "Attack_FlankButt", "Attack_Shove"]
# hits: 맞는 순간(동작 시작 후 초, Blender 프레임 기준 (f-1)/30), stop: 히트스톱(실제 초),
# shake: 화면 흔들림 세기, kick: 맞은 물체에 주는 속도 변화(m/s, 무게와 상관없이), up: 위로 띄우는 비율(기본 0.35)
# 히트스톱(stop)은 60fps 프레임 수로 적는다 (2026-11-24, 시푸 데이터 참고: 약 0~2 · 중 4 · 강 6 · 마무리 8~12 프레임).
# 연타의 앞 타는 거의 멈추지 않고, 뒤로 갈수록 길게 멈춰 '탁-탁-탁 … 쾅'이 되게 한다.
const F := 1.0 / 60.0
const ATTACKS := {
	# 흔들림(shake, 화면이 밀리는 폭 m)도 뒤로 갈수록 크게: 연타 세 번은 살짝, 피니시만 크게 (2026-11-25.
	# 전에는 1~3타가 0.12 씩이라 4타가 다 맞으면 0.8초 내내 화면이 덜덜거렸다)
	"Attack_RearSlam": {"hits": [0.50], "stop": 6 * F, "shake": 0.14, "kick": 8.0},     # 강 (콤보 피니시는 아래 배율로 8프레임)
	"Attack_LowCharge": {"hits": [0.333], "stop": 6 * F, "shake": 0.06, "kick": 7.0},   # 강 (돌진)
	"Attack_FlankButt": {"hits": [0.367], "stop": 2 * F, "shake": 0.035, "kick": 6.5},  # 약 (콤보 1타)
	# 밀어붙이기는 날리지 않고 Ram 걸음(0.25m)만큼씩 밀고 간다: 약하게, 위로 띄우지 않게
	"Attack_Shove": {"hits": [0.367, 0.633, 0.90], "stop": 1 * F, "shake": 0.03, "kick": 1.6, "up": 0.0},
	# 콤보 연결용 (첫 버전 박치기 재활용). 올려치기는 물체를 위로 띄운다
	"Attack_Hook": {"hits": [0.433], "stop": 3 * F, "shake": 0.045, "kick": 6.5},         # 중 (콤보 2타)
	# light_up: 가벼운 타일 때도 이만큼은 띄운다 (올려치기에 책상이 살짝 떴다가 피니시를 맞는다)
	"Attack_Uppercut": {"hits": [0.40], "stop": 4 * F, "shake": 0.06, "kick": 5.0, "up": 1.2, "light_up": 1.3},  # 중 (3타)
}

# 콤보 (시푸 참고): Space 를 이어 누르면 회복 동작을 끊고 다음 박치기로 잇는다.
# 순서는 늘 같다 — 한 문장으로 외울 수 있게: 왼쪽으로 들이받기 → 후려치기 → 올려치기 → 일어섰다 내리찍기(피니시).
# Space 를 길게 누르고 있으면 남은 타를 건너뛰고 바로 피니시. 방향키(시험용 층은 위)+Space 는 돌진 공격.
const COMBO_CHAIN := ["Attack_FlankButt", "Attack_Hook", "Attack_Uppercut", "Attack_RearSlam"]
const COMBO_MAX := 4
const COMBO_FINISHER := "Attack_RearSlam"
const DASH_ATTACK := "Attack_LowCharge"
const LINK_DELAY := 3 * F             # 마지막 맞는 순간 뒤 이만큼(3프레임) 지나면 다음 타로 이어진다
const HEAVY_HOLD := 0.20              # Space 를 이만큼 누르고 있으면 강공(피니시)
const FINISHER_BONUS := {"stop": 8.0 / 6.0, "shake": 1.4, "kick": 1.3}   # 피니시 멈춤 6 → 8프레임
const HIT_RADIUS := 0.75              # 돌머리 둘레 판정 반지름

# 조작감 (2026-11-20 평가 뒤): 동작 중에 누른 입력을 잠깐 기억하고, 회복 구간을 끊을 수 있게 한다.
const BUFFERED_ACTIONS := ["guard", "backstep", "attack"]   # 같은 틱에 함께 누르면 뒤의 것이 이긴다
# 누른 입력을 이만큼 기억했다가, 할 수 있게 되는 틱에 실행한다 (2026-11-24: 공격 0.35, 회피·패리 0.15 — 시푸 데이터 참고)
const BUFFER_TIME := {"attack": 0.35, "backstep": 0.15, "guard": 0.15}
# 박치기 회복 끊기 (마지막 맞는 순간 뒤). 다음 타·회피는 곧바로, 패리는 조금 뒤, 걷기는 마무리 타에서만.
const DODGE_CANCEL := 3 * F           # Shift(대시·백스텝)
const GUARD_CANCEL := 15 * F          # E(패리)
const MOVE_CANCEL := 24 * F           # 방향키 — 피니시·돌진만. 연타 중간 타는 다음 타나 회피로만 빠져나간다
# 동작별 손보기 (동작 자체는 그대로 두고 게임에서 맞춘다).
#   speed: 재생 빠르기, reach: 이동 거리 배율, skip: 앞부분(움츠리는 예비 동작)을 건너뛰는 길이(동작 속 초),
#   free: 동작 속 이 시각이 지나면 Space·E·방향키로 끊긴다 (같은 동작을 연달아 끊어 쓰지는 못한다)
# 대시는 원래 0.6초에 1.05m(달리기의 절반 속도)이고 처음 0.13초는 제자리였다.
#   carry: 달리던 속도를 이어받는다
const ACTION_TUNE := {
	"Dash": {"speed": 1.5, "reach": 2.0, "skip": 0.10, "free": 0.42, "carry": true},
}
# 콤보 구조 (2026-11-21): 가벼운 타는 대상을 조금만 밀어 제자리에 두고, 날리는 것은 피니시·돌진뿐이다.
#   (전에는 첫 타가 6.5~8m/s 로 날려 버려 2~4타가 허공을 쳤다)
# 이어지는 타(2·3타)는 예비 동작을 건너뛰고 빠르게 틀어 '탁-탁-탁 … 쾅' 박자를 만든다. 피니시는 원래 빠르기.
const LIGHT_KICK := 1.8               # 가벼운 타가 대상에 주는 속도(m/s)의 기본값 (콤보 밖에서 쓴 가벼운 타)
# 넉백 (2026-11-25): 콤보 타마다 대상에 주는 속도(m/s). 조금씩만 밀어 다음 타가 닿게 하고, 날리는 것은 피니시뿐이다.
const COMBO_KICK := [2.2, 2.6, 2.2]   # 1타 · 2타 · 3타 (3타는 올려치기라 light_up 만큼 위로도 띄운다)
const CHARGE_KICK := 3.0              # 돌진(방향키+Space)으로 여는 첫 타. 조금 더 세게 밀지만 날리지는 않는다
# 방향키+Space 돌진이 대상을 날리는지. 꺼 두면 돌진은 '붙으며 여는 첫 타'가 되어 2·3타·피니시로 이어진다
# (켜져 있던 2026-11-24 까지는 위키를 누른 채 Space 를 누르면 첫 타가 날려 버려 콤보가 이어지지 않았다).
const CHARGE_LAUNCHES := false
# 공격하며 앞으로 (2026-11-25): 박치기마다 맞는 순간까지 앞의 대상 쪽으로 다가선다. 밀려난 대상을 따라붙어 콤보가 이어진다.
const STEP_REACH := 1.05              # 맞는 순간 대상과 이 거리(m, 몸 가운데끼리)가 되게 다가선다
const STEP_MAX := [1.0, 0.8, 0.8, 1.0]   # 타마다 다가설 수 있는 가장 먼 거리(m): 1타 · 2타 · 3타 · 피니시
const STEP_MAX_CHARGE := 2.4          # 돌진은 멀리서 달려든다
const STEP_FREE := 0.35               # 앞에 대상이 없을 때 나아가는 거리(m). 헛쳐도 앞으로 밀고 간다
const STEP_FREE_CHARGE := 1.2
const STEP_SPEED_MAX := 8.0           # 다가서는 속도 상한(m/s)
const AIM_RANGE := 3.4                # 이 거리 안, 앞쪽 AIM_CONE 안의 가장 가까운 대상을 겨눈다
const AIM_CONE_DEG := 50.0
const AIM_TURN_DEG := 30.0            # 박치기를 시작할 때 대상 쪽으로 몸을 돌려 주는 한도
const LIGHT_DAMAGE := 1
const LAUNCH_DAMAGE := 2              # 피니시·돌진은 집기를 두 배로 깎는다 (집기는 4 를 버틴다)
const LINK_TUNE := {"speed": 1.35, "skip": 0.13}
# 콤보로 이어진 피니시: 앞 타(올려치기)가 몸을 세운 채 끝나므로 웅크리는 앞부분만 조금 건너뛴다. 빠르기는 그대로.
const FINISHER_LINK_TUNE := {"skip": 0.13}
const FINISHER_CAM := 1.0             # 피니시 동안 등 뒤 카메라를 올려 내리찍는 돌머리가 몸에 가리지 않게 한다 (0~1)
const CARRY_TIME := 0.12              # 달리다 대시하면 달리던 속도를 이만큼에 걸쳐 이어받는다 (멈칫하지 않게)

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
var _hitstop_left := 0.0
var hitstop_count := 0                # 점검용: 히트스톱이 걸린 횟수
var _skeleton: Skeleton3D
var _head_bone := -1
var feet: FootGrounder
var combo_step := 0                   # 지금 콤보 몇 타째 (0 = 콤보 아님)
var combo_hits := 0                   # 이번 콤보에서 실제로 맞은 수 (화면의 COMBO 숫자)
var _queued := false                  # 다음 박치기 입력이 들어와 있음
var _queued_heavy := false
var _hold_time := 0.0
var _is_finisher := false
var _buffered := ""                   # 기억해 둔 입력 (BUFFERED_ACTIONS 가운데 하나, 없으면 "")
var _buffer_left := 0.0
var _carry_speed := 0.0               # 대시가 이어받은 달리기 속도
var _carry_left := 0.0
var _tune := {}                       # 지금 동작에 걸린 손보기 (ACTION_TUNE 또는 LINK_TUNE)
var _launcher := false                # 지금 박치기가 대상을 날리는 타인지 (피니시)
var _step_target: Node3D              # 이번 박치기가 다가서는 대상 (없으면 null)
var _step_budget := 0.0               # 이번 박치기에서 더 다가설 수 있는 거리(m)
var step_moved := 0.0                 # 점검용: 이번 박치기에서 다가선 거리(m)

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
	_read_input(real_delta)

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
			_anim.speed_scale = _action_speed()
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
	if free_move:
		_move_free(real_delta)
	else:
		_move_tank(real_delta)
	_start_buffered()


## 입력 읽기: 동작·히트스톱 중에도 매 틱 읽는다. 바로 못 하는 입력은 BUFFER_TIME 동안 기억한다.
func _read_input(real_delta: float) -> void:
	if not input_enabled:
		_buffered = ""
		return
	_buffer_left -= real_delta
	if _buffer_left <= 0.0:
		_buffered = ""
	for a in BUFFERED_ACTIONS:
		if Input.is_action_just_pressed(a):
			_buffered = a
			_buffer_left = BUFFER_TIME[a]
			# 박치기 중의 Space 는 콤보로 모아 둔다 (히트스톱 중에 눌러도)
			if a == "attack" and _state == State.ACTION and ATTACKS.has(_current_action):
				_queued = true
	if Input.is_action_just_pressed("sanjae"):
		activate_sanjae()


## 기억해 둔 입력을 실행한다 (실행했으면 true). only 를 주면 그 입력들만 본다.
func _start_buffered(only: Array = BUFFERED_ACTIONS) -> bool:
	if _buffered == "" or not _buffered in only:
		return false
	var what := _buffered
	_buffered = ""
	var dir := _held_dir()
	match what:
		"attack":
			combo_step = 1
			combo_hits = 0
			_face(dir)
			# 방향키(자유 이동이 아니면 위)+Space 는 돌진으로 붙으며 여는 첫 타, 그냥 Space 는 제자리에서 여는 첫 타
			var pushing := dir != Vector3.ZERO if free_move else Input.is_action_pressed("move_forward")
			if pushing:
				_start_attack(DASH_ATTACK, CHARGE_LAUNCHES)
			else:
				_start_attack(COMBO_CHAIN[0])
		"backstep":
			_reset_combo()
			_face(dir)
			_start_action("Dash" if dir != Vector3.ZERO else "Backstep")
		"guard":
			_reset_combo()
			_start_action("Parry_Tail")
	return true


func _reset_combo() -> void:
	_launcher = false
	_camera_emphasis(0.0)
	if combo_step != 0:
		combo_step = 0
		combo_hits = 0
		_is_finisher = false
		combo_changed.emit(0)


## 자유 이동에서 누르고 있는 방향 (화면 기준 수평 단위 벡터, 안 누르면 0). 돌기 + 앞뒤 조작에서는 늘 0.
func _held_dir() -> Vector3:
	if not free_move:
		return Vector3.ZERO
	var v := Input.get_vector("turn_left", "turn_right", "move_forward", "move_back")
	var dir := screen_forward.cross(Vector3.UP) * v.x - screen_forward * v.y
	return dir.normalized() if dir.length() >= 0.1 else Vector3.ZERO


## 방향키를 하나라도 누르고 있는지 (회복 구간을 끊고 움직일 뜻이 있는지)
func _wants_move() -> bool:
	for a in ["move_forward", "move_back", "turn_left", "turn_right"]:
		if Input.is_action_pressed(a):
			return true
	return false


## 자유 이동: 누른 방향(화면 기준)으로 달리고 몸도 그쪽으로 돌린다.
func _move_free(real_delta: float) -> void:
	var dir := _held_dir()
	if dir == Vector3.ZERO:
		velocity.x = 0.0
		velocity.z = 0.0
		_play("Idle")
		_anim.speed_scale = _base_anim_speed()
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-FREE_TURN * real_delta))
	velocity.x = dir.x * forward_speed
	velocity.z = dir.z * forward_speed
	_play("Run")
	_anim.speed_scale = _base_anim_speed() * forward_speed / RUN_FOOT_SPEED


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


## tune 을 주면 동작별 손보기(ACTION_TUNE) 대신 그것을 쓴다 (콤보로 이어지는 타의 LINK_TUNE)
func _start_action(anim_name: String, blend := 0.05, tune: Dictionary = {}) -> void:
	_tune = tune if not tune.is_empty() else ACTION_TUNE.get(anim_name, {})
	# 달리던 속도 가운데 새로 보는 쪽 성분을 이어받는다 (대시처럼 carry 가 켜진 동작만)
	var fwd := -global_transform.basis.z
	_carry_speed = clampf(velocity.x * fwd.x + velocity.z * fwd.z, 0.0, forward_speed) if _tune.get("carry", false) else 0.0
	_carry_left = CARRY_TIME if _carry_speed > 0.0 else 0.0
	_state = State.ACTION
	_current_action = anim_name
	_action_time = 0.0
	_hits_done = 0
	_anim.speed_scale = _action_speed()
	# 같은 동작을 연달아 써도 처음부터 (skip 이 있으면 예비 동작을 건너뛴 자리부터)
	_anim.play_section(anim_name, float(_tune.get("skip", 0.0)), -1.0, blend)
	_spin_prev = _root_yaw()
	_visual_spin = 0.0
	_model.rotation.y = PI


func _action(real_delta: float) -> void:
	_action_time += real_delta
	# root motion: 이번 프레임에 root 뼈가 움직인 만큼 몸을 옮기고 돌린다
	var rm_pos := _anim.get_root_motion_position()
	var tune := _tune
	var world_step := _model.global_transform.basis * rm_pos * float(tune.get("reach", 1.0))
	velocity.x = world_step.x / real_delta
	velocity.z = world_step.z / real_delta
	if _carry_left > 0.0:
		# 이어받은 달리기 속도가 동작 속 이동보다 빠른 동안에는 그 속도로 (서서히 0 으로)
		var fwd := -global_transform.basis.z
		var lack := _carry_speed * _carry_left / CARRY_TIME - (velocity.x * fwd.x + velocity.z * fwd.z)
		if lack > 0.0:
			velocity.x += fwd.x * lack
			velocity.z += fwd.z * lack
		_carry_left -= real_delta
	_step_in(real_delta)
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
	# 맞는 순간은 동작 속 시각으로 잰다 (빠르게 틀거나 앞을 건너뛰어도 같은 자세에서 맞게)
	if _hits_done < hits.size() and _clip_pos() >= hits[_hits_done]:
		_hits_done += 1
		_headbutt_hit(spec)
	if _update_cancel(real_delta, hits, tune):
		return
	if not hits.is_empty():
		_update_combo(real_delta, hits)


## 공격하며 앞으로: 첫 맞는 순간까지, 겨눈 대상과 STEP_REACH 거리가 되도록 (대상이 없으면 STEP_FREE 만큼) 나아간다.
## 동작 자체의 이동(root motion)에 더하는 속도이고, 남은 거리를 맞는 순간까지 남은 시간으로 나눠 매 틱 다시 잰다.
func _step_in(real_delta: float) -> void:
	if _step_budget <= 0.0 or _hits_done > 0:
		return
	var hits: Array = ATTACKS.get(_current_action, {}).get("hits", [])
	if hits.is_empty():
		return
	var left := (float(hits[0]) - _clip_pos()) / float(_tune.get("speed", 1.0))   # 맞는 순간까지 남은 실제 시간
	if left <= 0.0:
		return
	var fwd := -global_transform.basis.z
	var want := _step_budget                       # 대상이 없으면 남은 몫을 고르게 나아간다
	if is_instance_valid(_step_target):
		var to := _step_target.global_position - global_position
		want = (to.x * fwd.x + to.z * fwd.z) - STEP_REACH
	var speed := clampf(want / maxf(left, real_delta), 0.0, STEP_SPEED_MAX)
	speed = minf(speed, _step_budget / real_delta)
	velocity.x += fwd.x * speed
	velocity.z += fwd.z * speed
	_step_budget -= speed * real_delta
	step_moved += speed * real_delta


## 앞쪽 AIM_CONE 안, AIM_RANGE 안에서 가장 가까운 박치기 대상 (없으면 null)
func _find_target() -> Node3D:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = AIM_RANGE
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position + Vector3.UP * 0.6)
	query.exclude = [get_rid()]
	var fwd := -global_transform.basis.z
	var best: Node3D = null
	var best_dist := INF
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var body := hit.collider as Node3D
		if body == null or not body.has_method("take_headbutt"):
			continue
		var to := (body.global_position - global_position) * Vector3(1, 0, 1)
		var dist := to.length()
		if dist < 0.01 or dist > AIM_RANGE or to.normalized().dot(fwd) < cos(deg_to_rad(AIM_CONE_DEG)):
			continue
		if dist < best_dist:
			best = body
			best_dist = dist
	return best


## 박치기를 시작할 때: 대상을 겨눠 몸을 조금 돌리고, 이번 타에서 다가설 몫을 정한다
func _aim_and_plan_step() -> void:
	var charge := _current_action == DASH_ATTACK
	_step_target = _find_target()
	step_moved = 0.0
	if _step_target:
		var to := _step_target.global_position - global_position
		rotation.y = rotate_toward(rotation.y, atan2(-to.x, -to.z), deg_to_rad(AIM_TURN_DEG))
		_step_budget = STEP_MAX_CHARGE if charge else float(STEP_MAX[clampi(combo_step - 1, 0, STEP_MAX.size() - 1)])
	else:
		_step_budget = STEP_FREE_CHARGE if charge else STEP_FREE


## 회복 구간 끊기 (끊었으면 true).
## 박치기 (마지막 맞는 순간 뒤, 동작 속 시각): + DODGE_CANCEL 에 Shift, + GUARD_CANCEL 에 E 가 나가고,
##   피니시·돌진만 + MOVE_CANCEL 에 방향키로 풀려난다. 연타 중간 타는 다음 타(Space, _update_combo)나 회피로만 빠져나간다.
## 손본 동작(대시): free 뒤에는 기억해 둔 Space·E 가 나가고 방향키로 풀려난다. Shift 는 동작이 끝난 뒤에 나간다.
func _update_cancel(real_delta: float, hits: Array, tune: Dictionary) -> bool:
	var move_at := INF
	var now := _clip_pos()
	var windows := []                    # [(이 시각부터, 나갈 수 있는 입력)]
	if not hits.is_empty():
		if _hits_done >= hits.size():
			var last := float(hits.back())
			windows = [[last + DODGE_CANCEL, ["backstep"]], [last + GUARD_CANCEL, ["guard"]]]
			if _launcher:
				move_at = last + MOVE_CANCEL
	elif tune.has("free"):
		windows = [[float(tune["free"]), ["attack", "guard"]]]
		move_at = float(tune["free"])
	for w in windows:
		if now >= w[0] and _start_buffered(w[1]):
			return true
	if now >= move_at and _wants_move():
		_end_action()
		_move(real_delta)
		return true
	return false


## launcher: 대상을 날리는 타 (돌진). 피니시는 늘 날린다. link: 콤보로 이어지는 타 (예비 동작을 줄여 빠르게)
func _start_attack(anim_name: String, launcher := false, link := false) -> void:
	if _buffered == "attack":
		_buffered = ""
	_queued = false
	_queued_heavy = false
	_hold_time = 0.0
	_is_finisher = anim_name == COMBO_FINISHER and combo_step >= 2
	_launcher = launcher or _is_finisher
	var tune := {}
	if link:
		tune = FINISHER_LINK_TUNE if _is_finisher else LINK_TUNE
	_start_action(anim_name, 0.05, tune)
	_aim_and_plan_step()
	_camera_emphasis(FINISHER_CAM if _is_finisher else 0.0)
	Sfx.play_at(get_parent(), Sfx.whoosh(), global_position + Vector3.UP, -6.0, randf_range(0.9, 1.15))


## 콤보: 다음 입력을 모아 두었다가, 마지막 맞는 순간이 지나면 회복 동작을 끊고 잇는다
func _update_combo(real_delta: float, hits: Array) -> void:
	if Input.is_action_pressed("attack"):
		_hold_time += real_delta
		if _hold_time >= HEAVY_HOLD and combo_step < COMBO_MAX:
			_queued = true
			_queued_heavy = true
	else:
		_hold_time = 0.0
	if _queued and combo_step < COMBO_MAX and _hits_done >= hits.size() \
			and _clip_pos() >= float(hits.back()) + LINK_DELAY:
		combo_step += 1
		var next: String
		if _queued_heavy or combo_step >= COMBO_MAX:
			next = COMBO_FINISHER
			combo_step = maxi(combo_step, 2)
		else:
			next = COMBO_CHAIN[combo_step - 1]
		_start_attack(next, false, true)


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
	var bonus := FINISHER_BONUS if _is_finisher else {"stop": 1.0, "shake": 1.0, "kick": 1.0}
	var stop: float = spec.get("stop", 0.05) * float(bonus["stop"])
	# 날리는 타(피니시·돌진)만 동작에 적힌 세기로 날린다. 가벼운 타는 조금 밀기만 해서 다음 타가 닿게 한다.
	var kick: float = spec.get("kick", 6.5) * float(bonus["kick"])
	var up: float = spec.get("up", 0.35)
	if not _launcher:
		kick = minf(kick, _light_kick())
		up = spec.get("light_up", 0.0)
	var landed := false
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var body: Object = hit.collider
		if body.has_method("take_headbutt"):
			# Ram 에서 맞은 물체 쪽으로 날린다 (옆구리 들이받기는 옆으로 날아간다)
			var dir: Vector3 = (body.global_position - global_position) * Vector3(1, 0, 1)
			if dir.length() < 0.01:
				dir = -global_transform.basis.z
			dir = dir.normalized()
			# 맞은 물체도 히트스톱 동안 같이 멈췄다가 움직인다
			body.take_headbutt(dir * kick + Vector3.UP * kick * up, LAUNCH_DAMAGE if _launcher else LIGHT_DAMAGE, stop)
			landed = true
	if landed:
		combo_hits += 1
		if combo_step != 0:
			combo_changed.emit(combo_hits)   # 화면의 COMBO 숫자는 실제로 맞은 수
		var power: float = clampf(stop / 0.1, 0.2, 1.5)
		ImpactFx.spawn(get_parent(), dome, power)
		# 소리 크기: 피니시가 겹쳐도 찢어지지 않게 1 아래로
		Sfx.play_at(get_parent(), Sfx.thud(), dome, linear_to_db(0.35 + 0.35 * power), randf_range(0.9, 1.1))
		_hitstop_left = stop
		hitstop_count += 1
		_anim.speed_scale = 0.0
		var cam := get_viewport().get_camera_3d()
		if cam and cam.has_method("add_shake"):
			cam.add_shake(spec.get("shake", 0.1) * float(bonus["shake"]))


## 가벼운 타가 대상에 주는 속도: 돌진으로 연 첫 타, 콤보 1~3타, 그 밖(콤보 밖에서 쓴 타)
func _light_kick() -> float:
	if _current_action == DASH_ATTACK:
		return CHARGE_KICK
	if combo_step >= 1 and combo_step <= COMBO_KICK.size():
		return float(COMBO_KICK[combo_step - 1])
	return LIGHT_KICK


func _base_anim_speed() -> float:
	return 1.0 / SANJAE_SCALE if _sanjae_left > 0.0 else 1.0


## 지금 동작의 재생 빠르기 (동작별 손보기 포함)
func _action_speed() -> float:
	return _base_anim_speed() * float(_tune.get("speed", 1.0))


## 등 뒤 카메라에 강조(피니시 동안 위로 올라가 내려다보기)를 알린다. 그런 기능이 없는 카메라면 아무 일도 없다.
func _camera_emphasis(amount: float) -> void:
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.has_method("set_emphasis"):
		cam.set_emphasis(amount)


## 지금 동작이 동작 속 몇 초 자리에 있는지 (히트스톱 중에는 멈춰 있다)
func _clip_pos() -> float:
	return _anim.current_animation_position if _anim.current_animation == _current_action else 0.0


func activate_sanjae() -> void:
	if sanjae_gauge < 1.0 or _sanjae_left > 0.0:
		return
	sanjae_gauge = 0.0
	_sanjae_left = SANJAE_REAL_SECONDS
	Engine.time_scale = SANJAE_SCALE
	if _hitstop_left <= 0.0:
		_anim.speed_scale = _action_speed()   # 동작 중에 켜도 그 동작의 빠르기를 지킨다
	hp = maxf(1.0, hp - SANJAE_HP_COST)   # 산재: 몸이 상한다 (끌려가지는 않음)
	hp_changed.emit(hp)


func _update_sanjae(real_delta: float) -> void:
	if _sanjae_left > 0.0:
		_sanjae_left -= real_delta
		if _sanjae_left <= 0.0:
			_sanjae_left = 0.0
			Engine.time_scale = 1.0
			if _hitstop_left <= 0.0:
				_anim.speed_scale = _action_speed()
	else:
		sanjae_gauge = minf(1.0, sanjae_gauge + SANJAE_RECHARGE * real_delta)
	sanjae_changed.emit(sanjae_gauge, _sanjae_left > 0.0)


func _on_animation_finished(anim_name: StringName) -> void:
	if _state == State.ACTION and anim_name == _current_action:
		_end_action()


## 동작을 끝내고 이동 상태로 돌아간다 (동작이 다 돌았거나, 회복 구간을 끊었을 때)
func _end_action() -> void:
	_state = State.MOVE
	_current_action = ""
	_carry_left = 0.0
	_reset_combo()
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

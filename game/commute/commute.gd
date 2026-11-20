## 출근길 시험 장면: 집(돌 이글루 방)의 알을 깨고 나와 회사 정문까지 간다.
## 조작: 방향키 = 화면 기준으로 자유 이동 (위 = 화면 안쪽). Space 박치기 · E 패링 · Shift 대시(방향키와 함께)/백스텝 · R 산재비스탄.
##       F5 = 다시 시작. Ram 은 시험용 층과 같은 플레이어(game/player/player.gd)를 자유 이동으로 켜서 쓴다.
##       걸을 수 있는 곳은 물리 벽이 아니라 이 장면이 매 프레임 자리로 되돌려 지킨다(_walkable).
## 1) 집 안: 시작하면 큰 알이 흔들리다 금이 가고, Ram 이 박치기로 깨고 튀어나온다. 그 뒤로 방 안을 자유롭게 돌아다닌다.
##    카메라는 한 자리에 서서 Ram 쪽으로 고개만 돌린다. 현관 굴로 나가면 화면이 잠깐 어두워졌다가 바깥으로 이어진다.
## 2) 바깥: 집 문 앞 샛길 → 마을 돌길 → 회사 광장 보도. 이 길 영역 안에서 자유롭게 움직인다(경계석·직원은 못 지나간다).
##    카메라는 주택가에서는 등 뒤에 가깝고 낮게 붙어 있다가, 회사 광장 경계를 넘으면서 뒤로 멀리·위로 물러나
##    정문에 닿을 때는 건물 위로 하늘까지 보인다. 정문에 닿으면 도착.
## 장면 모델은 tools/blender/build_home.py · build_commute.py 의 export 로 만든다 (Blender (x, y, z) = 여기서 (x, z, -y)).
extends Node3D

const HOME_SCENE := preload("res://assets/environments/home/home.glb")
const EGG_SCENE := preload("res://assets/environments/home/egg.glb")
const ROAD_SCENE := preload("res://assets/environments/commute/commute.glb")

const FLOOR_Y := 0.04
const FADE_TIME := 0.25
const ARRIVE_TIME := "08:50"

# ---- 집 안 (좌표는 방 가운데 기준, HOME_ORIGIN 을 더해 놓는다)
const HOME_ORIGIN := Vector3(300.0, 0.0, 0.0)           # 집 안 모델은 바깥 장면과 떨어진 자리에 둔다
const HOME_CAM := Vector3(0.3, 2.25, 3.05)              # 카메라가 서 있는 자리 (움직이지 않는다)
const HOME_LOOK := Vector3(-0.25, 0.75, -1.3)           # 기본으로 보는 곳
const HOME_TRACK := 0.6                                # Ram 쪽으로 고개를 돌리는 정도 (0 = 안 돌림, 1 = Ram 만 봄)
const HOME_FOV := 58.7
const ROOM_RADIUS := 2.85                               # 벽 안쪽에서 Ram 몸 길이만큼 뺀 반지름
const ROOM_FRONT_Z := 1.0                              # 카메라 발밑: 이보다 앞으로는 못 온다 (화면 아래로 나가므로)
const DOOR_DIR := Vector3(0.766, 0.0, -0.643)           # 현관 굴 방향 (build_home.py 의 DOOR_AZ 40°)
const DOOR_HALF_WIDTH := 0.42
const DOOR_EXIT := 4.5                                  # 방 가운데에서 굴 방향으로 이만큼 가면 바깥
const EGG_POS := Vector3(-1.5, 0.0, -1.1)               # 알 자리 (build_home.py 의 EGG_C)
const EGG_BLOCK := 1.5                                  # 알 가운데에서 이 안으로는 못 들어간다
# 알 깨기: 흔들림 [시작, 길이, 기울기°] 세 번 → 금 → 터짐 → 뛰어나와 착지
const HATCH_WOBBLES := [[0.35, 0.25, 5.0], [0.75, 0.25, -7.0], [1.12, 0.25, 9.0]]
const HATCH_CRACK := 0.80
const HATCH_BURST := 1.40
const HATCH_JUMP := 0.80
const HATCH_JUMP_HEIGHT := 1.75
const HATCH_LAND := Vector3(0.45, FLOOR_Y, -0.35)       # 알에서 뛰어나와 내려서는 자리
const SHARD_GRAVITY := 14.0
const SHARD_REST_Y := 0.10
const SHARD_STAY := 2.5                                 # 바닥에 떨어진 조각이 남아 있는 시간 (초)

# ---- 바깥
const TOWER_Y := 40.0                                   # 회사 정문 면 (build_commute.py 의 TY)
const PLAZA := 16.0                                     # 회사 앞 광장 길이 (build_commute.py 의 PLAZA)
const DOOR_Z := -(TOWER_Y - 3.0)                        # 정문 앞: 여기 닿으면 도착
const ROAD_START := Vector3(-2.7, FLOOR_Y, -7.0)        # 집 문 앞
const ROAD_START_HEADING := Vector3(0.72, 0.0, -0.69)   # 문에서 길 쪽
# 걸을 수 있는 곳 (x, z): 마을 돌길(경계석 안쪽) · 회사 광장 가운데 보도 · 집 문 앞 샛길(비스듬한 띠)
const WALK_RECTS: Array[Rect2] = [Rect2(-1.55, -(TOWER_Y - PLAZA), 3.1, TOWER_Y - PLAZA - 2.0), Rect2(-2.35, DOOR_Z, 4.7, PLAZA - 3.0)]
const YARD_A := Vector2(-2.8, -6.9)
const YARD_B := Vector2(-1.3, -8.5)
const YARD_HALF_WIDTH := 0.6
# 길 위의 직원들 (build_commute.py 에서 세운 자리): 이 둘레로는 못 지나간다
const NPCS: Array[Vector2] = [Vector2(1.3, -15.0), Vector2(-1.1, -21.0), Vector2(1.0, -(TOWER_Y - 6.0)), Vector2(-1.5, -(TOWER_Y - 3.5))]
const NPC_BLOCK := 0.75
const ZOOM_START_Z := -(TOWER_Y - PLAZA)                # 주택가와 회사 광장의 경계: 여기서부터 줌 아웃
const ZOOM_END_Z := DOOR_Z                              # 정문 앞: 여기서 가장 멀고 높다
const CAM_NEAR := Vector3(1.0, 2.3, 5.2)                # 등 뒤 가까이: 옆·높이·뒤 거리
const CAM_FAR := Vector3(0.0, 16.0, 30.0)               # 정문에 닿았을 때: 건물 위로 하늘까지 보인다
const FOV_NEAR := 45.7
const FOV_FAR := 62.0
const TOWER_LOOK := Vector3(0.0, 14.3, -TOWER_Y)        # 다 물러났을 때 보는 곳 (건물 위쪽 → 화면 윗부분은 하늘)

enum Stage { HOME, ROAD }

var stage := Stage.HOME
var hatching := true           # 알을 깨고 나오는 중 (조작 불가)
var arrived := false
var ram: RamPlayer
var cam: Camera3D
var egg: Node3D
var shards: Array[Dictionary] = []     # {node, vel, axis, spin, normal, resting}
var _last_pos := Vector3.ZERO          # 지난 프레임에 서 있던 (걸을 수 있는) 자리
var _yaw := 0.0
var _hatch_t := 0.0
var _cracked := false
var _burst := false
var _home_look := HOME_ORIGIN + HOME_LOOK
var _env: Environment
var _sun: DirectionalLight3D
var _home_lights: Node3D
var _fade: ColorRect
var _fading := false
var _status: Label
var _bar: ProgressBar


func _ready() -> void:
	Engine.time_scale = 1.0
	var home := HOME_SCENE.instantiate()
	home.position = HOME_ORIGIN
	add_child(home)
	egg = EGG_SCENE.instantiate()
	egg.position = HOME_ORIGIN + EGG_POS
	add_child(egg)
	for n in egg.find_children("Shard_*", "MeshInstance3D", true, false):
		var node := n as MeshInstance3D
		var out := Vector3(node.position.x, 0.0, node.position.z)
		shards.append({"node": node, "vel": Vector3.ZERO, "axis": Vector3.UP, "spin": 0.0, "resting": false,
				"normal": Vector3(out.x, 0.35, out.z).normalized()})
	add_child(ROAD_SCENE.instantiate())
	_build_light()

	# 바닥: 집 안과 바깥이 같은 높이라 평면 하나로 받친다 (Ram 의 중력·발 디딤용)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var ground_shape := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, FLOOR_Y)
	ground_shape.shape = plane
	ground.add_child(ground_shape)
	add_child(ground)

	ram = RamPlayer.new()
	ram.name = "Ram"
	ram.free_move = true
	add_child(ram)
	process_physics_priority = 10          # Ram 이 움직인 뒤에 자리를 바로잡고 카메라를 옮긴다

	cam = Camera3D.new()
	cam.name = "Camera"
	cam.far = 600.0
	add_child(cam)
	cam.make_current()
	_build_hud()
	_enter(Stage.HOME)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	if hatching:
		_update_hatch(delta)
	else:
		# Ram 이 이번 프레임에 달리거나 동작(대시·박치기)으로 옮겨 간 자리를 걸을 수 있는 곳 안으로 되돌린다
		var p := _walkable(_last_pos, ram.position)
		ram.position.x = p.x
		ram.position.z = p.z
		_last_pos = ram.position
	_update_shards(delta)

	if stage == Stage.HOME and not hatching and not _fading and _door_along(ram.position) >= DOOR_EXIT:
		_leave_home()
	elif stage == Stage.ROAD and not arrived and ram.position.z <= DOOR_Z + 0.01:
		arrived = true
		ram.input_enabled = false
		_status.text = "%s  회사 도착   (F5: 다시)" % ARRIVE_TIME
	_bar.value = progress() * 100.0
	if stage == Stage.ROAD:
		_follow_camera(1.0 - exp(-6.0 * delta))
	else:
		_home_camera(1.0 - exp(-5.0 * delta))


# ---------------------------------------------------------------- 이동
## Ram 이 보는 방향 (수평)
func heading() -> Vector3:
	return -ram.global_transform.basis.z


## 몸(정면 -Z)이 수평 방향 dir 을 볼 때의 회전값
func _yaw_for(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## from 에서 to 로 가려 할 때 실제로 설 수 있는 자리 (벽·경계에서는 미끄러진다)
func _walkable(from: Vector3, to: Vector3) -> Vector3:
	var p := _walk_home(to) if stage == Stage.HOME else _walk_road(to)
	var blocked := false
	if stage == Stage.HOME:
		blocked = _flat(p - HOME_ORIGIN).distance_to(_flat(EGG_POS)) < EGG_BLOCK - 0.01
	else:
		for n in NPCS:
			blocked = blocked or _flat(p).distance_to(n) < NPC_BLOCK - 0.01
	return from if blocked else p


func _walk_home(to: Vector3) -> Vector3:
	var q := _flat(to - HOME_ORIGIN)
	q = _push_out(q, _flat(EGG_POS), EGG_BLOCK)
	# 방(원, 앞쪽은 카메라 발밑까지) 과 현관 굴(띠) 가운데 가까운 쪽으로
	var room := q.limit_length(ROOM_RADIUS)
	room.y = minf(room.y, ROOM_FRONT_Z)
	var d := _flat(DOOR_DIR)
	var side := Vector2(-d.y, d.x)
	var door := d * clampf(q.dot(d), 0.0, DOOR_EXIT + 0.3) + side * clampf(q.dot(side), -DOOR_HALF_WIDTH, DOOR_HALF_WIDTH)
	var best := room if room.distance_squared_to(q) <= door.distance_squared_to(q) else door
	return HOME_ORIGIN + Vector3(best.x, FLOOR_Y, best.y)


func _walk_road(to: Vector3) -> Vector3:
	var q := _flat(to)
	for n in NPCS:
		q = _push_out(q, n, NPC_BLOCK)
	var best := Geometry2D.get_closest_point_to_segment(q, YARD_A, YARD_B)       # 샛길: 선분에서 반 너비까지
	best = best + (q - best).limit_length(YARD_HALF_WIDTH)
	for r in WALK_RECTS:
		var c := Vector2(clampf(q.x, r.position.x, r.end.x), clampf(q.y, r.position.y, r.end.y))
		if c.distance_squared_to(q) < best.distance_squared_to(q):
			best = c
	return Vector3(best.x, FLOOR_Y, best.y)


func _push_out(q: Vector2, center: Vector2, radius: float) -> Vector2:
	var off := q - center
	if off.length() >= radius:
		return q
	return center + (off.normalized() if off.length() > 0.001 else Vector2.RIGHT) * radius


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## 방 가운데에서 현관 굴 방향으로 얼마나 나갔나 (m)
func _door_along(p: Vector3) -> float:
	return _flat(p - HOME_ORIGIN).dot(_flat(DOOR_DIR))


## 집(0) → 회사 정문(1): 집 안은 현관까지 남은 거리, 바깥은 정문까지 남은 거리로 센다
func progress() -> float:
	var home_len := (DOOR_DIR * DOOR_EXIT).distance_to(HATCH_LAND)
	var road_len := ROAD_START.z - DOOR_Z
	var done := 0.0
	if stage == Stage.HOME:
		done = home_len - minf(home_len, (ram.position - HOME_ORIGIN).distance_to(DOOR_DIR * DOOR_EXIT))
	else:
		done = home_len + clampf(ROAD_START.z - ram.position.z, 0.0, road_len)
	return clampf(done / (home_len + road_len), 0.0, 1.0)


## 알에서 나온 뒤 집에서 회사까지 곧장 달려서 걸리는 시간 (초, 화면 전환 포함. 알 깨기 연출은 hatch_seconds)
func travel_seconds() -> float:
	var home_len := (DOOR_DIR * DOOR_EXIT).distance_to(HATCH_LAND)
	var mid := Vector3(0.0, FLOOR_Y, -9.6)
	var road_len := ROAD_START.distance_to(mid) + (mid.z - DOOR_Z)
	return (home_len + road_len) / ram.forward_speed + FADE_TIME * 2.0


func hatch_seconds() -> float:
	return HATCH_BURST + HATCH_JUMP


# ---------------------------------------------------------------- 알 깨기
func _update_hatch(delta: float) -> void:
	_hatch_t += delta
	var t := _hatch_t
	var tilt := 0.0
	for w in HATCH_WOBBLES:                                   # 알이 통째로 기우뚱
		var u: float = (t - w[0]) / w[1]
		if u > 0.0 and u < 1.0:
			tilt = deg_to_rad(w[2]) * sin(PI * u)
	egg.rotation.z = tilt if t < HATCH_BURST else 0.0
	if not _cracked and t >= HATCH_CRACK:
		_cracked = true
		for s in shards:                                      # 금: 조각이 살짝 어긋난다
			var node: Node3D = s.node
			node.position += s.normal * randf_range(0.015, 0.04)
			node.rotate(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(), randf_range(-0.05, 0.05))
		Sfx.play_at(self, Sfx.thud(), egg.position + Vector3.UP * 1.5, -8.0, 2.2)
	if not _burst and t >= HATCH_BURST:
		_burst = true
		for s in shards:                                      # 조각이 바깥·위로 튄다
			var out := Vector3(s.normal.x, 0.0, s.normal.z)
			out = out.normalized() if out.length() > 0.2 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
			s.vel = out * randf_range(2.0, 3.4) + Vector3.UP * randf_range(2.2, 4.6)
			s.axis = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			s.spin = randf_range(4.0, 9.0)
		ram.visible = true
		ram.play_clip("Attack_Uppercut", 0.3)
		Sfx.play_at(self, Sfx.thud(), egg.position + Vector3.UP * 1.5, 0.0, 1.3)
	if not _burst:
		return
	# 머리를 위로 하고 솟구쳐, 몸을 눕히며 방 가운데 쪽에 내려선다
	var u := clampf((t - HATCH_BURST) / HATCH_JUMP, 0.0, 1.0)
	var from := HOME_ORIGIN + EGG_POS + Vector3(0.0, 0.35, 0.0)
	var to := HOME_ORIGIN + HATCH_LAND
	var p := from.lerp(to, u)
	p.y += HATCH_JUMP_HEIGHT * 4.0 * u * (1.0 - u)
	ram.position = p
	ram.rotation = Vector3(deg_to_rad(65.0) * pow(1.0 - u, 1.6), _yaw, 0.0)     # 몸 정면이 -Z 라 +가 머리 위
	ram.set_model_scale(lerpf(0.6, 1.0, clampf(u / 0.3, 0.0, 1.0)))
	if u >= 1.0:
		hatching = false
		ram.set_model_scale(1.0)
		ram.rotation = Vector3(0.0, _yaw, 0.0)
		ram.velocity = Vector3.ZERO
		ram.set_physics_process(true)          # 여기서부터 조작을 받는다
		_last_pos = ram.position
		_status.text = "아침 08:41  ·  문으로 나가면 출근"
		Sfx.play_at(self, Sfx.thud(), ram.position, -4.0, 0.8)


func _update_shards(delta: float) -> void:
	if not _burst:
		return
	for s in shards:
		if s.resting:
			continue
		var node: Node3D = s.node
		var vel: Vector3 = s.vel
		vel.y -= SHARD_GRAVITY * delta
		node.position += vel * delta
		node.rotate(s.axis, s.spin * delta)
		var room := _flat(EGG_POS + node.position)            # 방 벽에 닿으면 그 자리에서 떨어진다
		if room.length() > 3.4:
			room = room.limit_length(3.4)
			node.position.x = room.x - EGG_POS.x
			node.position.z = room.y - EGG_POS.z
			vel.x = 0.0
			vel.z = 0.0
		s.vel = vel
		if node.position.y <= SHARD_REST_Y and vel.y < 0.0:
			s.resting = true
			node.position.y = SHARD_REST_Y
			# 바닥에 눕힌다: 조각의 바깥 면이 위나 아래를 보게
			var n: Vector3 = (node.basis * s.normal).normalized()
			var flat := Quaternion(n, Vector3.UP if n.y >= 0.0 else Vector3.DOWN) * node.quaternion
			var tw := create_tween()
			tw.tween_property(node, "quaternion", flat, 0.12)
			tw.tween_interval(SHARD_STAY)                       # 잠깐 남아 있다가 작아지며 사라진다 (Ram 이 밟고 다니지 않게)
			tw.tween_property(node, "scale", Vector3.ONE * 0.01, 0.4)
			tw.tween_callback(node.hide)


## 시험·확인용: 알 깨기를 건너뛰고 내려선 자리에서 시작한다
func skip_hatch() -> void:
	if not hatching:
		return
	_hatch_t = HATCH_BURST + HATCH_JUMP
	_cracked = true
	_update_hatch(0.0)
	for s in shards:
		s.resting = true
		(s.node as Node3D).visible = false


# ---------------------------------------------------------------- 장면 전환
func _enter(s: Stage) -> void:
	stage = s
	var inside := s == Stage.HOME
	_home_lights.visible = inside
	_sun.visible = not inside
	_env.ambient_light_energy = 0.22 if inside else 0.9
	_env.fog_enabled = not inside
	_env.volumetric_fog_enabled = inside
	ram.velocity = Vector3.ZERO
	ram.input_enabled = not _fading        # 화면이 다 밝아진 뒤에 조작을 받는다
	if inside:
		# 알 속에서 시작: 깨고 나올 때까지 보이지 않고, 이 장면이 몸을 직접 움직인다
		ram.set_physics_process(false)
		ram.position = HOME_ORIGIN + EGG_POS + Vector3(0.0, 0.35, 0.0)
		_yaw = _yaw_for(HATCH_LAND - EGG_POS)
		ram.visible = false
		ram.screen_forward = ((HOME_LOOK - HOME_CAM) * Vector3(1.0, 0.0, 1.0)).normalized()   # 위 = 카메라가 보는 쪽
		cam.global_position = HOME_ORIGIN + HOME_CAM
		cam.fov = HOME_FOV
		_home_camera(1.0)
		_status.text = "아침 08:41"
	else:
		ram.position = ROAD_START
		_yaw = _yaw_for(ROAD_START_HEADING)
		ram.screen_forward = Vector3.FORWARD                                                  # 위 = 회사 쪽
		_follow_camera(1.0)
		_status.text = "오늘 도착 %s" % ARRIVE_TIME
	ram.rotation = Vector3(0.0, _yaw, 0.0)
	_last_pos = ram.position


func _leave_home() -> void:
	_fading = true
	ram.input_enabled = false
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	tw.tween_callback(func() -> void: _enter(Stage.ROAD))
	tw.tween_property(_fade, "color:a", 0.0, FADE_TIME)
	tw.tween_callback(func() -> void:
		_fading = false
		ram.input_enabled = true)


# ---------------------------------------------------------------- 카메라
## 집 안: 한 자리에 서서, 기본 구도와 Ram(깨기 전에는 알) 사이를 본다
func _home_camera(blend: float) -> void:
	var focus := HOME_ORIGIN + EGG_POS + Vector3.UP * 1.3 if not _burst else ram.position + Vector3.UP * 0.7
	var want := (HOME_ORIGIN + HOME_LOOK).lerp(focus, HOME_TRACK)
	_home_look = _home_look.lerp(want, blend)
	cam.look_at(_home_look)


## 카메라가 얼마나 물러났나 (0 = 등 뒤 가까이, 1 = 멀리 위에서 건물과 하늘까지).
## 주택가에서는 0 으로 붙어 있고, 광장 경계를 넘으면서 정문까지 부드럽게 1 이 된다.
func zoom() -> float:
	if stage == Stage.HOME:
		return 0.0
	var p := clampf(inverse_lerp(ZOOM_START_Z, ZOOM_END_Z, ram.position.z), 0.0, 1.0)
	return p * p * (3.0 - 2.0 * p)


func _follow_camera(blend: float) -> void:
	var e := zoom()
	var rp := ram.position
	var off := CAM_NEAR.lerp(CAM_FAR, e)
	var want_pos := Vector3(rp.x * (1.0 - e) + off.x, off.y, rp.z + off.z)
	var want_look := Vector3(rp.x * (1.0 - e) - 0.2, 1.3, rp.z - 10.0).lerp(TOWER_LOOK, e)
	cam.global_position = cam.global_position.lerp(want_pos, blend)
	cam.look_at(want_look)
	cam.fov = lerpf(FOV_NEAR, FOV_FAR, e)


# ---------------------------------------------------------------- 빛
func _build_light() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.58, 0.88)
	sky_mat.sky_horizon_color = Color(0.96, 0.84, 0.70)
	sky_mat.ground_horizon_color = Color(0.80, 0.76, 0.68)
	sky_mat.ground_bottom_color = Color(0.36, 0.40, 0.30)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.ssao_enabled = true
	_env.glow_enabled = true
	_env.glow_intensity = 0.5
	_env.fog_light_color = Color(0.86, 0.84, 0.82)      # 바깥: 멀리 있는 회사가 옅게 보이게
	_env.fog_density = 0.006
	_env.fog_sky_affect = 0.0
	_env.volumetric_fog_density = 0.03                  # 집 안: 창으로 드는 빛이 줄기로 보이게
	_env.volumetric_fog_albedo = Color(1.0, 0.95, 0.88)
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()        # 오른쪽 뒤에서 비추는 낮은 아침 해 (Blender 의 해 방향과 같다)
	_sun.light_color = Color(1.0, 0.86, 0.68)
	_sun.light_energy = 1.3
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 120.0
	add_child(_sun)
	_sun.look_at_from_position(Vector3.ZERO, Vector3(-0.62, -0.42, -0.58))

	# 집 안: 둥근 창으로 드는 따뜻한 빛(알과 그 앞 바닥), 차가운 보조광, 자명종 불빛, 현관 굴에서 새는 빛
	_home_lights = Node3D.new()
	_home_lights.position = HOME_ORIGIN
	add_child(_home_lights)
	var window := SpotLight3D.new()
	window.light_color = Color(1.0, 0.89, 0.72)
	window.light_energy = 24.0
	window.spot_range = 12.0
	window.spot_angle = 24.0
	window.shadow_enabled = true
	window.light_volumetric_fog_energy = 2.0
	_home_lights.add_child(window)
	window.position = Vector3(-1.73, 2.49, -3.26)
	window.look_at(HOME_ORIGIN + Vector3(-0.8, 0.0, -0.5))
	for spec in [[Vector3(0.4, 3.0, 1.3), Color(0.55, 0.68, 0.95), 0.9, 10.0], [Vector3(-1.0, 0.35, 0.6), Color(1.0, 0.55, 0.2), 0.7, 2.6],
			[Vector3(4.0, 0.8, -3.37), Color(0.55, 0.70, 0.95), 1.2, 5.0]]:
		var o := OmniLight3D.new()
		o.position = spec[0]
		o.light_color = spec[1]
		o.light_energy = spec[2]
		o.omni_range = spec[3]
		o.light_volumetric_fog_energy = 0.0
		_home_lights.add_child(o)


# ---------------------------------------------------------------- 화면 표시
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	var theme := Theme.new()
	theme.set_color("font_outline_color", "Label", Color(0.08, 0.08, 0.1))
	theme.set_constant("outline_size", "Label", 6)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	box.theme = theme
	layer.add_child(box)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 34)
	box.add_child(_status)

	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "집"
	row.add_child(l)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(260, 16)
	_bar.max_value = 100
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.70, 0.12)
	_bar.add_theme_stylebox_override("fill", fill)
	row.add_child(_bar)
	var r := Label.new()
	r.text = "회사"
	row.add_child(r)
	box.add_child(row)

	var help := Label.new()
	help.text = "방향키 이동   Space 박치기   E 패링   Shift 대시(방향키와 함께)·백스텝   F5 다시 시작"
	help.add_theme_font_size_override("font_size", 16)
	box.add_child(help)

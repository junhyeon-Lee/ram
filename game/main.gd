## 시험용 층: 사무실 한 칸에 Ram, 박치기로 날릴 집기, 끝에 계단 문.
## 8:50 도착 → 9:00 까지 계단 문에 닿으면 성공, 못 가면 '끌려감' 후 다시 시작 (F5 로도 다시 시작).
extends Node3D

const ROOM_SIZE := Vector2(14.0, 22.0)   # 가로(x) × 세로(z), m
const WALL_HEIGHT := 3.2

var player: RamPlayer
var clock: WorkClock
var _clock_label: Label
var _status_label: Label
var _sanjae_bar: ProgressBar
var _hp_bar: ProgressBar
var _combo_label: Label
var _ended := false


func _ready() -> void:
	Engine.time_scale = 1.0
	_build_environment()
	_build_room()

	player = RamPlayer.new()
	player.name = "Ram"
	player.position = Vector3(0, 0.05, ROOM_SIZE.y * 0.5 - 2.5)
	add_child(player)

	var cam := FollowCamera.new()
	cam.name = "Camera"
	cam.target = player
	cam.fov = 62.0
	add_child(cam)
	cam.make_current()

	clock = WorkClock.new()
	clock.name = "WorkClock"
	clock.time_up.connect(_on_time_up)
	add_child(clock)

	_build_hud()
	player.sanjae_changed.connect(_on_sanjae_changed)
	player.hp_changed.connect(func(hp: float) -> void: _hp_bar.value = hp)
	player.combo_changed.connect(_on_combo_changed)


func _process(_delta: float) -> void:
	_clock_label.text = clock.text()
	if Input.is_action_just_pressed("restart"):
		_restart()


# ---------------------------------------------------------------- 공간
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.80, 0.82, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.87, 0.92)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	add_child(sun)


func _build_room() -> void:
	var floor_col := Color(0.55, 0.57, 0.60)
	var wall_col := Color(0.72, 0.73, 0.75)
	_static_box("Floor", Vector3(ROOM_SIZE.x, 0.2, ROOM_SIZE.y), Vector3(0, -0.1, 0), floor_col)
	var hx := ROOM_SIZE.x * 0.5
	var hz := ROOM_SIZE.y * 0.5
	_static_box("WallL", Vector3(0.3, WALL_HEIGHT, ROOM_SIZE.y), Vector3(-hx, WALL_HEIGHT * 0.5, 0), wall_col)
	_static_box("WallR", Vector3(0.3, WALL_HEIGHT, ROOM_SIZE.y), Vector3(hx, WALL_HEIGHT * 0.5, 0), wall_col)
	_static_box("WallBack", Vector3(ROOM_SIZE.x, WALL_HEIGHT, 0.3), Vector3(0, WALL_HEIGHT * 0.5, hz), wall_col)
	# 앞쪽 벽: 가운데에 계단 문 자리를 비운다
	var gap := 2.4
	var side_w := (ROOM_SIZE.x - gap) * 0.5
	_static_box("WallFrontL", Vector3(side_w, WALL_HEIGHT, 0.3), Vector3(-(gap + side_w) * 0.5, WALL_HEIGHT * 0.5, -hz), wall_col)
	_static_box("WallFrontR", Vector3(side_w, WALL_HEIGHT, 0.3), Vector3((gap + side_w) * 0.5, WALL_HEIGHT * 0.5, -hz), wall_col)

	# 계단 문: 닿으면 이 층 통과
	var door := Area3D.new()
	door.name = "StairsDoor"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(gap, 2.4, 0.8)
	shape.shape = box
	door.add_child(shape)
	door.position = Vector3(0, 1.2, -hz - 0.2)
	door.body_entered.connect(_on_door_entered)
	add_child(door)
	_mesh_box(door, Vector3(gap, 2.4, 0.1), Vector3(0, 0, 0.3), Color(0.25, 0.55, 0.35))

	# 박치기로 날릴 책상·상자 줄
	for row in 4:
		for col in 3:
			var p := Vector3((col - 1) * 3.6, 0.45, hz - 7.0 - row * 3.2)
			_breakable("Desk_%d_%d" % [row, col], Vector3(1.4, 0.9, 0.8), p, Color(0.62, 0.48, 0.34))


func _static_box(n: String, size: Vector3, pos: Vector3, col: Color) -> void:
	var body := StaticBody3D.new()
	body.name = n
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_mesh_box(body, size, Vector3.ZERO, col)
	add_child(body)


func _breakable(n: String, size: Vector3, pos: Vector3, col: Color) -> void:
	var body := Breakable.new()
	body.name = n
	body.position = pos
	body.mass = 8.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_mesh_box(body, size, Vector3.ZERO, col)
	add_child(body)


func _mesh_box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.9
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)


# ---------------------------------------------------------------- 화면 표시
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# 밝은 배경에서도 읽히게 모든 글자에 검은 테두리
	var theme := Theme.new()
	theme.set_color("font_outline_color", "Label", Color(0.08, 0.08, 0.1))
	theme.set_constant("outline_size", "Label", 6)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	box.theme = theme
	layer.add_child(box)

	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 40)
	box.add_child(_clock_label)

	_hp_bar = _bar(box, "HP", Color(0.85, 0.30, 0.25))
	_hp_bar.value = 100
	_sanjae_bar = _bar(box, "SANJAE (R)", Color(0.30, 0.75, 0.95))
	_sanjae_bar.value = 100

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 28)
	_status_label.text = "Arrive 08:50  |  Reach the stairs before 09:00"
	box.add_child(_status_label)

	_combo_label = Label.new()
	_combo_label.add_theme_font_size_override("font_size", 34)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	box.add_child(_combo_label)

	var help := Label.new()
	help.text = "Arrows: move/turn   Space: headbutt   (again after a hit: combo / hold: finisher / Up+Space: charge)\nE: flip parry   Shift: backstep   R: Sanjae-vistan   F5: restart"
	help.add_theme_font_size_override("font_size", 16)
	box.add_child(help)


func _bar(parent: Control, label: String, col: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(220, 18)
	bar.max_value = 100
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	parent.add_child(row)
	return bar


func _on_combo_changed(step: int) -> void:
	_combo_label.text = "COMBO x%d" % step if step >= 2 else ""


func _on_sanjae_changed(gauge: float, active: bool) -> void:
	_sanjae_bar.value = gauge * 100.0
	_sanjae_bar.modulate = Color(1.6, 1.6, 1.6) if active else Color.WHITE


# ---------------------------------------------------------------- 판 끝
func _on_door_entered(body: Node) -> void:
	if body == player and not _ended:
		_end("STAIRS REACHED at %s  -  next floor!" % clock.text())


func _on_time_up() -> void:
	if not _ended:
		_end("09:00  LATE  -  dragged back to your desk...")


func _end(msg: String) -> void:
	_ended = true
	clock.finished = true
	_status_label.text = msg + "   (F5: restart)"
	player.set_physics_process(false)
	Engine.time_scale = 1.0


func _restart() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

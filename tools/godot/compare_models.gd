## 디자인 전·후 비교: 여러 GLB 를 같은 크기·조명·카메라로 찍어 [열 = 모델] × [줄 = 보기] 한 장으로 저장한다.
## 보기: 3/4 앞 · 옆 · 뒤 · 게임 카메라(뒤 위) · 3/4 뒤 · 얼굴. 게임 카메라는 늘 뒤에서 보므로 뒤쪽도 꼭 본다.
## 크기·위치는 첫 모델 기준 하나로 모두 맞춘다(시안끼리 키가 달라도 몸은 같은 크기로). 모델 앞(머리)은 +Z.
## 창이 몇 초 떴다 닫힌다(헤드리스는 그리지 않는다).
##
## 실행: godot --path . --resolution 420x420 --script tools/godot/compare_models.gd -- <out.png> <이름=a.glb[@dx,dy,dz]> ... [--game]
##   @dx,dy,dz  그 모델에서 머리를 옮긴 양(Blender 좌표, m. build_dino.py 의 HEAD_LIFT 차이). 얼굴 카메라가 머리 자리를 따라간다.
##              모델 크기로 얼굴을 잡으면 돌기 높이 같은 것에 따라 카메라가 달라져 톱니 무늬가 달라 보인다.
##   --game     게임 조명(game/main.gd 의 환경·해·바닥 색). 없으면 밝은 확인용 조명.
extends SceneTree

# 이름, 카메라 방향, 거리(키 배수), 보는 높이(키 배수), 얼굴 확대
const VIEWS := [
	["3/4 FRONT", Vector3(0.8, 0.45, 1.0), 2.3, 0.5, false],
	["SIDE", Vector3(-1.0, 0.12, 0.0), 2.3, 0.5, false],
	["BACK", Vector3(0.0, 0.15, -1.0), 2.3, 0.5, false],
	["GAME CAMERA", Vector3(0.0, 0.55, -1.0), 2.3, 0.5, false],
	["BACK 3/4", Vector3(-0.8, 0.35, -1.0), 2.3, 0.5, false],
	["FACE", Vector3(0.55, 0.25, 1.0), 0.8, 0.0, true],
]
const FACE_POINT := Vector3(0.0, 1.04, 0.80)   # build_dino.py 의 얼굴 렌더 대상 (0,-0.80,1.04) 을 glTF 좌표(x, z, -y)로 (HEAD_LIFT 전)

var _models: Array[Node3D] = []
var _names: Array[String] = []
var _head_off: Array[Vector3] = []
var _cam: Camera3D
var _caption: Label
var _shots: Array[Image] = []
var _job := 0
var _wait := 0
var _args: PackedStringArray
var _game_light := false
var _ready_done := false
var _scale := 1.0
var _offset := Vector3.ZERO
var _ref: AABB


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--game":
			_game_light = true
		else:
			_args.append(a)
	if _args.size() < 2:
		push_error("인자: <out.png> <이름=a.glb[@dx,dy,dz]> ... [--game]")
		quit(1)


## 장면 트리가 돌기 시작한 첫 프레임에 올린다 (_initialize 에선 global_transform 을 못 읽는다)
func _process(_d: float) -> bool:
	if not _ready_done:
		_ready_done = true
		_build_stage()
		for i in range(1, _args.size()):
			var kv := _args[i].split("=", true, 1)
			var pv := kv[1].split("@", true, 1)
			var off := Vector3.ZERO
			if pv.size() > 1:
				var c := pv[1].split(",")
				off = Vector3(float(c[0]), float(c[2]), -float(c[1]))   # Blender (x,y,z) → glTF (x,z,-y)
			_names.append(kv[0])
			_head_off.append(off)
			var m := _load_glb(pv[0], i == 1)
			if m == null:
				quit(1)
				return true
			_models.append(m)
		return false
	var total := _models.size() * VIEWS.size()
	if _job >= total:
		return true
	if _wait == 0:
		_set_shot(_job % _models.size(), _job / _models.size())
	_wait += 1
	if _wait >= 4:      # 그림자·톤매핑이 자리 잡게 몇 프레임 기다린다
		_shots.append(root.get_texture().get_image())
		_job += 1
		_wait = 0
		if _job >= total:
			_compose()
	return false


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	var floor_col: Color
	if _game_light:
		env.background_color = Color(0.80, 0.82, 0.86)
		env.ambient_light_color = Color(0.85, 0.87, 0.92)
		env.ambient_light_energy = 0.35
		env.tonemap_exposure = 0.9
		sun.rotation_degrees = Vector3(-55, -35, 0)
		sun.light_energy = 0.75
		floor_col = Color(0.55, 0.57, 0.60)
	else:
		env.background_color = Color(0.90, 0.91, 0.94)
		env.ambient_light_color = Color(0.9, 0.92, 0.96)
		env.ambient_light_energy = 0.5
		sun.rotation_degrees = Vector3(-55, 20, 0)
		sun.light_energy = 0.85
		floor_col = Color(0.92, 0.93, 0.96)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	root.add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = floor_col
	plane.material = mat
	floor.mesh = plane
	root.add_child(floor)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	root.add_child(_cam)
	_cam.make_current()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(12, 8)
	_caption.add_theme_font_size_override("font_size", 18)
	_caption.add_theme_color_override("font_color", Color(0.12, 0.12, 0.15))
	layer.add_child(_caption)


func _load_glb(path: String, is_ref: bool) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("GLB 를 못 읽음: %s (%s)" % [path, error_string(err)])
		return null
	var holder := Node3D.new()
	holder.add_child(doc.generate_scene(state))
	root.add_child(holder)
	if is_ref:
		var box := _aabb(holder)
		_scale = 1.0 / box.size.y
		_offset = Vector3(box.get_center().x, box.position.y, box.get_center().z) * _scale
	holder.scale = Vector3.ONE * _scale
	holder.position = -_offset
	if is_ref:
		_ref = _aabb(holder)
	holder.visible = false
	print("loaded %s  size=%s" % [path, _aabb(holder).size])
	return holder


func _aabb(n: Node) -> AABB:
	var first := true
	var box := AABB()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _set_shot(mi: int, vi: int) -> void:
	for i in _models.size():
		_models[i].visible = i == mi
	var v: Array = VIEWS[vi]
	var target: Vector3
	if v[4]:
		target = (FACE_POINT + _head_off[mi]) * _scale - _offset
	else:
		target = Vector3(_ref.get_center().x, _ref.size.y * v[3], _ref.get_center().z)
	var dir: Vector3 = (v[1] as Vector3).normalized()
	_cam.global_position = target + dir * _ref.size.y * v[2] * 1.6
	_cam.look_at(target)
	_caption.text = "%s  |  %s" % [_names[mi], v[0]]


func _compose() -> void:
	var w := _shots[0].get_width()
	var h := _shots[0].get_height()
	var cols := _models.size()
	var sheet := Image.create(w * cols, h * VIEWS.size(), false, _shots[0].get_format())
	for i in _shots.size():
		sheet.blit_rect(_shots[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	var err := sheet.save_png(_args[0])
	print("SAVED %s (%s)" % [_args[0], error_string(err)])
	quit(0 if err == OK else 1)

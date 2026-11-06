## 화면 확인: 시험용 층을 실제 창에 띄워 N 프레임 뒤 화면을 PNG 로 저장하고 끝낸다.
## 헤드리스는 그리지 않으므로 창이 몇 초 떴다 닫힌다.
## 실행: godot --path . --resolution 960x540 --script tools/godot/capture_frame.gd -- <저장할.png> [프레임=90]
## 출력: 저장 경로, 카메라 위치, 렌더러·GPU
extends SceneTree

var _out := ""
var _frames := 90
var _f := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("저장할 PNG 경로를 -- 뒤에 준다")
		quit(1)
		return
	_out = args[0]
	if args.size() > 1:
		_frames = int(args[1])
	root.add_child(load("res://game/main.tscn").instantiate())


func _process(_delta: float) -> bool:
	_f += 1
	if _f == _frames:
		var img := root.get_texture().get_image()
		var err := img.save_png(_out)
		var cam := root.get_camera_3d()
		print("CAPTURED %s -> %s (%s)" % [img.get_size(), _out, error_string(err)])
		print("camera pos=%s" % (cam.global_position if cam else Vector3.ZERO))
		print("renderer=%s driver=%s gpu=%s" % [RenderingServer.get_current_rendering_method(),
				RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])
		quit(0 if err == OK else 1)
	return false

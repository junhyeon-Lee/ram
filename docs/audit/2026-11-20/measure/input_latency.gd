## 입력 지연: 키 이벤트를 세 가지로 넣어 '몇 번째 물리 틱/화면 프레임에 동작이 시작되나'를 잰다.
## (1) Input.action_press 를 physics_frame 신호 직후에, (2) MainLoop._physics_process 에서,
## (3) Input.parse_input_event(InputEventKey) 를 _process(화면 프레임 끝)에서 — 실제 키보드에 가장 가깝다.
extends SceneTree

const MAX_TICKS := 120 * 30
var ticks := 0
var main: Node
var p: RamPlayer
var mode := -1
var armed_tick := -1
var armed_frame := -1
var log := []
var pending_event := false
var press2 := [0, 0]


func _initialize() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _physics_process(_d: float) -> bool:
	ticks += 1
	if ticks > MAX_TICKS:
		print("TIMEOUT")
		quit(2)
	if mode == 2 and armed_tick == ticks:
		Input.action_press("attack")
		press2 = [Engine.get_physics_frames(), Engine.get_process_frames()]
	return false


func _process(_d: float) -> bool:
	if pending_event:
		pending_event = false
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_SPACE
		ev.pressed = true
		Input.parse_input_event(ev)
		armed_frame = Engine.get_process_frames()
		armed_tick = Engine.get_physics_frames()
	return false


func tick(n := 1) -> void:
	for i in n:
		await physics_frame


func release_all() -> void:
	Input.action_release("attack")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.pressed = false
	Input.parse_input_event(ev)


func wait_action(label: String, t0: int, f0: int) -> void:
	for i in 60:
		await tick()
		if p._state == 1:
			# 지금 보는 값은 지난 틱의 결과
			var done_tick := Engine.get_physics_frames() - 1
			print("%s: action started in physics tick +%d after the press tick, render frame +%d" % [label, done_tick - t0, Engine.get_process_frames() - f0])
			break
	release_all()
	await tick(160)


func _run() -> void:
	await tick(30)
	p = main.player
	p.global_position = Vector3(-5.5, 0.05, 8.0)
	await tick(10)
	for trial in 3:
		# (1)
		p._attack_bag = ["Attack_FlankButt"]
		var t0 := Engine.get_physics_frames()
		var f0 := Engine.get_process_frames()
		Input.action_press("attack")
		await wait_action("(1) action_press after physics_frame signal", t0, f0)
		# (2)
		p._attack_bag = ["Attack_FlankButt"]
		mode = 2
		armed_tick = ticks + 3
		await tick(5)
		mode = -1
		await wait_action("(2) action_press in MainLoop._physics_process", press2[0], press2[1])
		# (3)
		p._attack_bag = ["Attack_FlankButt"]
		pending_event = true
		await tick(1)
		while pending_event:
			await tick(1)
		await wait_action("(3) parse_input_event at end of render frame", armed_tick, armed_frame)
	print("ticks per render frame: physics %d / frames %d" % [Engine.get_physics_frames(), Engine.get_process_frames()])
	quit(0)

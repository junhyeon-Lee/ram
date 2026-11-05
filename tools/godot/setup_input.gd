## 키 배치를 project.godot 에 써 넣는다 (한 번만 돌리면 된다. 바꾸면 다시 돌린다).
## 실행: godot --headless --path . --script tools/godot/setup_input.gd
extends SceneTree

const ACTIONS := {
	"move_forward": [KEY_UP],
	"move_back": [KEY_DOWN],
	"turn_left": [KEY_LEFT],
	"turn_right": [KEY_RIGHT],
	"attack": [KEY_SPACE],      # 박치기 (왼손 엄지)
	"guard": [KEY_E],           # 막기·패링
	"lock_on": [KEY_TAB],       # 락온
	"sanjae": [KEY_R],          # 산재비스탄
	"backstep": [KEY_SHIFT],    # 백대시
	"restart": [KEY_F5],        # 시험용: 판 다시 시작
}


func _init() -> void:
	for action in ACTIONS:
		var events: Array = []
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.device = -1  # 모든 입력 장치
			ev.physical_keycode = key
			events.append(ev)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": events})
	var err := ProjectSettings.save()
	print("input actions saved: ", err == OK)
	quit()

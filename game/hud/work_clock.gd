## 9시 마감 시계: 회사 도착 시각부터 9:00 까지, 게임 시계 2배속 (게임 1분 = 실제 30초)
## 엔진 시간으로 흐르므로 산재비스탄(Engine.time_scale)이 켜지면 같이 느려진다.
class_name WorkClock
extends Node

signal time_up

const SPEED := 2.0                    # 게임 시계 배속
const DEADLINE := 9 * 3600            # 09:00:00 (초)

@export var arrive_minutes := 8 * 60 + 50   # 도착 시각. 집이 좋아질수록 8:30 까지 당겨진다

var game_seconds := 0.0
var finished := false


func _ready() -> void:
	game_seconds = arrive_minutes * 60.0


func _process(delta: float) -> void:
	if finished:
		return
	game_seconds += delta * SPEED
	if game_seconds >= DEADLINE:
		game_seconds = DEADLINE
		finished = true
		time_up.emit()


func text() -> String:
	var s := int(game_seconds)
	return "%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


func real_seconds_left() -> float:
	return (DEADLINE - game_seconds) / SPEED

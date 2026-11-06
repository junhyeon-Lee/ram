## 효과음: 소리 파일이 생기기 전까지 쓰는 합성음. 처음 쓸 때 한 번 만들어 둔다.
## thud: 박치기가 맞는 둔탁한 충돌음 (낮은 사인파 + 짧은 잡음), whoosh: 휘두르는 바람 소리 (걸러진 잡음)
class_name Sfx
extends RefCounted

const RATE := 22050
static var _cache := {}


static func thud() -> AudioStreamWAV:
	if not _cache.has("thud"):
		_cache["thud"] = _make(0.28, func(t: float) -> float:
			var body := sin(TAU * (90.0 - 50.0 * t / 0.28) * t) * exp(-t * 14.0)
			var crack := randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.6
			return (body + crack) * 0.9)
	return _cache["thud"]


static func whoosh() -> AudioStreamWAV:
	if not _cache.has("whoosh"):
		var state := {"y": 0.0}
		_cache["whoosh"] = _make(0.22, func(t: float) -> float:
			# 잡음을 한 번 걸러(저역) 바람처럼, 가운데가 가장 크게
			state.y = state.y * 0.85 + randf_range(-1.0, 1.0) * 0.15
			var env := sin(PI * t / 0.22)
			return state.y * env * 2.2)
	return _cache["whoosh"]


static func _make(seconds: float, fn: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := clampf(fn.call(float(i) / RATE), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## pos 에서 소리를 한 번 내고 끝나면 스스로 사라진다
static func play_at(parent: Node, stream: AudioStream, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()

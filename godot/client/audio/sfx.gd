# 효과음 재생 (client/sound.js 자리): 구운 녹음본 (audio/baked, tools/bake-audio.cjs) 을 재생기 묶음으로 틈.
# 버스: SFX (슬로모션 저역 필터·크기) · SFXDirect (마지막 킬 소리, 필터 안 거침) · 좌우가 있는 소리는 좌우 칸 (PAN_STEPS, 0.1 단위) 버스 (패너) → SFX.
# 재생은 버스마다 AudioStreamPolyphonic 하나 (play_stream 이 AudioStreamPlayer.play() 보다 ~14배 가벼움 — 웹 프레임 비용, 2026-10-31)
# 크기 = 녹음 gain (굽기 전 원래 크기) × 거리 감쇠 × vol, 버스 = SFX_VOLUME × 설정 sfx. 높낮이는 녹음본 여러 개 + ±SFX_DETUNE/2 흔들기
extends Node

const C := preload("res://core/config.gd")
const SM := preload("res://audio/sound_math.gd")

const PAN_STEPS := 10 # 좌우 칸: -1 ~ 1 을 0.1 씩 (21 버스)
const VOICES := 32 # 버스마다 동시에
const BAKED := "res://audio/baked/"

var manifest := {}
var streams := {} # 파일 이름 -> AudioStream (처음 쓸 때 부름)
var pan_players: Array = [] # 좌우 칸마다 폴리포닉 재생기 (가운데 = PAN_STEPS 번)
var direct_player: AudioStreamPlayer
var listener = null # Vector4(x, y, z, yaw) 내 귀 (카메라, 게임 좌표)
var slow_rate := 1.0
var slow_on := false
var lowpass: AudioEffectLowPassFilter
var sfx_bus := -1
var played := 0 # 튼 소리 수 (헤드리스 확인용)


func _ready() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(BAKED + "manifest.json"))
	sfx_bus = _bus("SFX", "Master")
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 20000
	AudioServer.add_bus_effect(sfx_bus, lowpass)
	_bus("SFXDirect", "Master")
	for i in PAN_STEPS * 2 + 1:
		var pan := float(i - PAN_STEPS) / PAN_STEPS
		if i == PAN_STEPS:
			pan_players.append(_poly("SFX")) # 가운데는 패너 없이
			continue
		var b := _bus("SFXPan%d" % i, "SFX")
		if AudioServer.get_bus_effect_count(b) == 0:
			var pe := AudioEffectPanner.new()
			pe.pan = pan
			AudioServer.add_bus_effect(b, pe)
		pan_players.append(_poly("SFXPan%d" % i))
	direct_player = _poly("SFXDirect")
	set_volume(1.0)


func _poly(bus: String) -> AudioStreamPlayer:
	var p := _player(bus)
	var ps := AudioStreamPolyphonic.new()
	ps.polyphony = VOICES
	p.stream = ps
	return p


func _voice(p: AudioStreamPlayer) -> AudioStreamPlaybackPolyphonic:
	if not p.playing:
		p.play()
	return p.get_stream_playback() as AudioStreamPlaybackPolyphonic


static func _bus(name: String, send: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, send)
	return i


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func stream(file: String) -> AudioStream:
	if not streams.has(file):
		streams[file] = load(BAKED + file)
	return streams[file]


# 설정의 효과음 크기 (0~1)
func set_volume(v: float) -> void:
	var db := linear_to_db(maxf(0.0001, C.SFX_VOLUME * v))
	AudioServer.set_bus_volume_db(sfx_bus, db + (linear_to_db(C.SFX_KO.slowGain) if slow_on else 0.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFXDirect"), db)


func has(key: String) -> bool:
	return manifest.get("sfx", {}).has(key)


# 구운 소리 key 를 틈. dist = 내 몸에서 거리 (0 = 내 소리, null = 모름), pos = 소리 난 곳 (게임 좌표 Vector3), vol 배율, delay 초
func play(key: String, dist = null, pos = null, vol := 1.0, delay := 0.0, direct := false) -> void:
	play_list(manifest.get("sfx", {}).get(key, []), dist, pos, vol, delay, direct)


# 녹음 목록 [{file, gain}] 중 하나 (manifest 의 sfx 밖 묶음 — 타이틀 효과 등)
func play_list(list: Array, dist = null, pos = null, vol := 1.0, delay := 0.0, direct := false) -> void:
	if list.is_empty():
		return
	var rec: Dictionary = list[randi() % list.size()]
	var lp := SM.listen(dist, pos, listener)
	var p: AudioStreamPlayer = direct_player if direct else pan_players[clampi(roundi(lp.y * PAN_STEPS), -PAN_STEPS, PAN_STEPS) + PAN_STEPS]
	var st := stream(rec.file)
	var db := linear_to_db(maxf(0.00001, float(rec.gain) * lp.x * vol))
	var pitch := (1.0 + randf_range(-1, 1) * C.SFX_DETUNE * 0.5) * (1.0 if direct else slow_rate)
	played += 1
	if delay > 0:
		get_tree().create_timer(delay).timeout.connect(func(): _voice(p).play_stream(st, 0.0, db, pitch))
	else:
		_voice(p).play_stream(st, 0.0, db, pitch)


# 화면 시간 배율 (KO 슬로모션): 슬로모션이면 효과음 먹먹하고 낮게 (sound.js slowmo)
func slowmo(scale: float) -> void:
	var K: Dictionary = C.SFX_KO
	var slow: bool = scale < 1 and scale > K.slowAbove
	if slow == slow_on:
		return
	slow_on = slow
	slow_rate = K.slowRate if slow else 1.0
	var tw := create_tween()
	tw.tween_property(lowpass, "cutoff_hz", float(K.slowLowpass) if slow else 20000.0, K.ease * 3)
	set_volume(_sfx_setting())


func _sfx_setting() -> float:
	return float(View.settings.get("sfx", 1.0))

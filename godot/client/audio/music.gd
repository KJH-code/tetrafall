# 배경음악·앰비언트·위험 액체 지속음 (client/music.js · title-sound.js · sound.js hazard 자리). 구운 고리 (audio/baked).
# 곡: 판 중 = 맵 테마 곡 (위험이 차오르면 긴장 버전), 대기·결과 = 대기실 곡. 메뉴·대기실은 곡 대신 테마 앰비언트 (웅웅 + 띄엄띄엄 소리).
# 곡이 바뀌면 지금 위치를 비율로 이어서 짧게 엇갈려 바꿈 (JS 는 16분음표 칸 순번을 이어 감 — 같은 효과)
extends Node

const C := preload("res://core/config.gd")
const SM := preload("res://audio/sound_math.gd")
const FADE := 0.35 # 곡 바꿈 엇갈림 (초)

var sfx # sfx.gd (녹음본·버스)
var music_bus := -1
var song_a: AudioStreamPlayer # 지금 곡
var song_b: AudioStreamPlayer # 바뀌며 사라지는 곡
var song_key := ""
var song_paused_at := -1.0 # 앰비언트 동안 멈춘 곡 위치 (비율 0~1)
var amb: AudioStreamPlayer
var amb_theme = null
var amb_next_ping := 0.0
var amb_ping: AudioStreamPlayer
var hz: AudioStreamPlayer
var hz_style := ""
var hz_level := 0.0
var hz_pop: AudioStreamPlayer
var volume := 1.0
var duck_until := 0.0
var duck_gain := 1.0


func _ready() -> void:
	music_bus = sfx._bus("Music", "Master")
	song_a = sfx._player("Music")
	song_b = sfx._player("Music")
	amb = sfx._player("SFX") # 앰비언트는 JS 처럼 효과음 크기를 따름 (title-sound.js out → sound.master)
	amb_ping = sfx._player("SFX")
	hz = sfx._player("SFX")
	hz_pop = sfx._player("SFX")
	set_volume(1.0)


func set_volume(v: float) -> void:
	volume = v
	_apply_bus()


var _bus_db := INF
var _bus_mute = null


# 버스 크기: 바뀔 때만 오디오 서버에 (웹은 오디오 서버 부르기가 비쌈 — 매 프레임 부르지 않게)
func _apply_bus() -> void:
	var db := linear_to_db(maxf(0.00001, C.MUSIC_VOLUME * volume * duck_gain))
	if absf(db - _bus_db) > 0.05:
		_bus_db = db
		AudioServer.set_bus_volume_db(music_bus, db)
	var mute := volume <= 0
	if mute != _bus_mute:
		_bus_mute = mute
		AudioServer.set_bus_mute(music_bus, mute)


# 잠깐 줄임 (KO 마지막 킬 슬로모션)
func duck(seconds: float) -> void:
	duck_until = Time.get_ticks_msec() / 1000.0 + seconds


func _loop_stream(file: String) -> AudioStream:
	var s: AudioStream = sfx.stream(file)
	if s is AudioStreamOggVorbis:
		s.loop = true
	return s


# 매 프레임 (audio.gd): state 로 곡·앰비언트·위험 지속음
func update(state: Dictionary, dt: float, ear_z) -> void:
	# 음악 줄임 (duck): 슬로모션 동안 musicDuck 배, 뒤에 천천히 원래대로
	var now := Time.get_ticks_msec() / 1000.0
	var want_duck: float = C.SFX_KO.musicDuck if now < duck_until else 1.0
	if duck_gain != want_duck:
		duck_gain += (want_duck - duck_gain) * minf(1.0, dt / (0.05 if want_duck < duck_gain else 0.35))
		if absf(duck_gain - want_duck) < 0.001:
			duck_gain = want_duck
		_apply_bus()
	# 앰비언트 (메뉴·대기실) — 있으면 곡은 쉼
	var at = SM.ambient_theme(state, View.menu_theme)
	_ambient(at, now)
	if at != null:
		if song_a.playing:
			song_paused_at = _pos_ratio(song_a)
			_fade_out(song_a)
		return
	_song(SM.song_key(state, SM.mood(state)))
	_hazard(state, dt, ear_z)


func _pos_ratio(p: AudioStreamPlayer) -> float:
	var len := p.stream.get_length() if p.stream else 0.0
	return fmod(p.get_playback_position(), len) / len if len > 0 else 0.0


func _song(key: String) -> void:
	if key == song_key and song_a.playing:
		return
	var rec = sfx.manifest.get("music", {}).get(key)
	if rec == null:
		return
	var ratio := 0.0
	if song_a.playing:
		ratio = _pos_ratio(song_a)
	elif song_paused_at >= 0:
		ratio = song_paused_at
	song_paused_at = -1.0
	# 지금 곡은 b 로 넘겨 사라지게, 새 곡은 a 에서 같은 비율 위치부터
	var old := song_a
	song_a = song_b
	song_b = old
	_fade_out(song_b)
	song_key = key
	var st := _loop_stream(rec.file)
	song_a.stream = st
	var target := linear_to_db(float(rec.gain))
	song_a.volume_db = target - 30
	song_a.play(ratio * st.get_length())
	var tw := create_tween()
	tw.tween_property(song_a, "volume_db", target, FADE)


func _fade_out(p: AudioStreamPlayer) -> void:
	if not p.playing:
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", p.volume_db - 40, FADE)
	tw.tween_callback(p.stop)


func _ambient(theme, now: float) -> void:
	if theme != amb_theme:
		amb_theme = theme
		if amb.playing:
			var old := amb # 사라지는 동안 새 것은 처음부터 천천히 (TITLE_SOUND.fadeIn)
			var tw0 := create_tween()
			tw0.tween_property(old, "volume_db", old.volume_db - 40, FADE * 3)
			tw0.tween_callback(old.queue_free)
			amb = sfx._player("SFX")
		if theme != null and sfx.manifest.get("ambient", {}).has(theme):
			var rec: Dictionary = sfx.manifest.ambient[theme].drone
			amb.stream = _loop_stream(rec.file)
			var target := linear_to_db(float(rec.gain))
			amb.volume_db = target - 40
			amb.play()
			var tw := create_tween()
			tw.tween_property(amb, "volume_db", target, C.TITLE_SOUND.fadeIn)
			amb_next_ping = now + C.TITLE_SOUND.pingEvery[0]
	if amb_theme == null or now < amb_next_ping:
		return
	var pe: Array = C.TITLE_SOUND.pingEvery
	amb_next_ping = now + randf_range(pe[0], pe[1])
	var pings: Array = sfx.manifest.ambient[amb_theme].pings
	var rec: Dictionary = pings[randi() % pings.size()]
	amb_ping.stream = sfx.stream(rec.file)
	amb_ping.volume_db = linear_to_db(float(rec.gain))
	amb_ping.pitch_scale = 1.0 + randf_range(-0.04, 0.04)
	amb_ping.play()


# 위험 액체 지속음: 판 중 위험이 켜져 있으면 표면까지 높이로 크기, 튀는 소리는 초당 pops[종류] 번 (sound.js hazard)
func _hazard(state: Dictionary, dt: float, ear_z) -> void:
	var style := SM.hazard_style(state)
	var live: bool = state.get("phase") == "playing" and state.get("lava", {}).get("active", false)
	var dist = null
	if live and ear_z != null:
		dist = maxf(0.0, float(ear_z) - float(state.lava.z))
	var target := SM.hazard_level(style, live, dist)
	if style != hz_style:
		hz_style = style
		hz.stop()
		hz_level = 0.0
	var rec = sfx.manifest.get("hazard", {}).get(style)
	if rec == null:
		return
	hz_level += (target - hz_level) * minf(1.0, dt / C.SFX_HAZARD.fade)
	if hz_level < 0.002:
		if hz.playing and target == 0:
			hz.stop()
		return
	if not hz.playing:
		hz.stream = _loop_stream(rec.loop.file)
		hz.play(randf() * hz.stream.get_length())
	var hz_db := linear_to_db(maxf(0.00001, float(rec.loop.gain) * hz_level))
	if absf(hz.volume_db - hz_db) > 0.05: # 바뀔 때만 (웹 오디오 서버 부르기 줄임)
		hz.volume_db = hz_db
	if randf() < float(C.SFX_HAZARD.pops.get(style, 0)) * dt and not hz_pop.playing:
		var pop: Dictionary = rec.pops[randi() % rec.pops.size()]
		hz_pop.stream = sfx.stream(pop.file)
		hz_pop.volume_db = linear_to_db(maxf(0.00001, float(pop.gain) * hz_level))
		hz_pop.play()

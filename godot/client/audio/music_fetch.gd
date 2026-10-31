# 곡 따로 받기 (웹만, 2026-10-31): 곡 녹음본 (audio/baked/music.*.ogg, ~4MB) 은 웹 첫 pck 에서 빠지고
# (addons/web_music 내보내기 플러그인 → 웹 빌드 폴더 music/) 쓸 때 여기서 하나씩 받음. PC 는 pck 안 그대로 (sfx.stream).
# 방에 들어가면 미리 받기 시작 (대기실 곡 → 지금 맵 곡 → 긴장 곡 → 나머지 순), 아직 못 받은 곡은 null → 곡 없이 조용히 넘어감
extends Node

const SM := preload("res://audio/sound_math.gd")
const RETRY_MS := 15000 # 받기 실패하면 이만큼 뒤에 다시

var sfx # sfx.gd (PC 는 그쪽 load)
var remote := false # true = 웹 (따로 받기)
var base := "" # 곡 폴더 주소 (…/music/)
var streams := {} # 파일 이름 → AudioStream
var failed := {} # 파일 이름 → 다시 해 볼 시각 (ms)
var queue: Array = [] # 받을 파일 이름 (앞이 먼저)
var busy := "" # 지금 받는 파일
var http: HTTPRequest


func _ready() -> void:
	if OS.has_feature("web"):
		remote = true
		base = str(JavaScriptBridge.eval("new URL('music/', location.href).href", true))
	http = HTTPRequest.new()
	http.use_threads = false
	http.accept_gzip = false # 웹은 브라우저가 이미 풀어 줌 (고도가 또 풀면 깨짐)
	add_child(http)
	http.request_completed.connect(_on_done)


# 받을 순서 (순수 계산): 대기실 곡 → 이 상태 맵의 곡 → 긴장 곡 → 나머지 (manifest 순)
static func order(music: Dictionary, state: Dictionary) -> Array:
	var keys: Array = ["lobby", SM.song_key(state, "battle"), SM.song_key(state, "lava")]
	for k in music:
		keys.append(k)
	var out: Array = []
	for k in keys:
		if music.has(k) and not out.has(k):
			out.append(k)
	return out


# 곡 녹음본 (없으면 null — 웹에서 아직 못 받음)
func stream(file: String) -> AudioStream:
	if not remote:
		return sfx.stream(file)
	if streams.has(file):
		return streams[file]
	want([file], true)
	return null


# 미리 받기: files 를 줄에 (front 면 맨 앞으로)
func want(files: Array, front := false) -> void:
	if not remote:
		return
	var now := Time.get_ticks_msec()
	var add: Array = []
	for f in files:
		if streams.has(f) or f == busy or now < float(failed.get(f, 0)):
			continue
		queue.erase(f)
		add.append(f)
	queue = add + queue if front else queue + add
	_next()


# 방에 들어가 있으면 그 상태 기준 순서로 전부 미리
func prefetch(music: Dictionary, state: Dictionary) -> void:
	if not remote or busy != "" or not queue.is_empty() or streams.size() >= music.size():
		return
	var files: Array = []
	for k in order(music, state):
		files.append(str(music[k].file))
	want(files)


func _next() -> void:
	if busy != "" or queue.is_empty() or base == "":
		return
	busy = str(queue.pop_front())
	if http.request(base + busy) != OK:
		_fail(busy)
		call_deferred("_next")


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var f := busy
	busy = ""
	var s: AudioStream = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		s = AudioStreamOggVorbis.load_from_buffer(body)
	if s != null:
		streams[f] = s
		if queue.is_empty():
			print("웹 곡 받음 %d개 (%.1f초)" % [streams.size(), Time.get_ticks_msec() / 1000.0])
	else:
		_fail(f)
	_next()


func _fail(f: String) -> void:
	busy = ""
	failed[f] = Time.get_ticks_msec() + RETRY_MS

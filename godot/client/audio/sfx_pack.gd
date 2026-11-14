# 효과음 묶음 따로 받기 (웹만, W53 2026-11-14): 효과음 wav 녹음본 (타이틀·앰비언트 핑 제외) 은 웹 첫 pck 에서 빠지고 (addons/web_music 내보내기 플러그인 →
# 웹 빌드 폴더 sfx.pck) 첫 화면이 뜬 뒤 여기서 받아 user://sfx.pck 로 저장 → ProjectSettings.load_resource_pack 으로 붙임 (웹 첫 받기 br ~1.5MB 줄임).
# 받는 동안 (보통 몇 초) 효과음은 조용히 넘어감 (sfx.gd stream 이 null — 캐시 안 함). PC·옛 웹 빌드·묶음이 없는 빌드는 pck 안 그대로라 아무 일 없음.
# 끄기: 웹 주소 ?no-sfx-pack (묶음 안 받음 = 효과음 없음, 확인용). 실패하면 RETRY_MS 뒤 다시 (최대 TRIES)
extends Node

const Opts := preload("res://core/opts.gd")

const PROBE := "res://audio/baked/swing.none.0.wav" # 이게 첫 pck 안에 있으면 쪼개지 않은 빌드 (PC·옛 웹)
const FILE := "user://sfx.pck"
const RETRY_MS := 15000
const TRIES := 4
const START_FRAMES := 30 # 첫 화면 뒤 이만큼 프레임 지나서 받기 시작 (켜는 프레임에 겹치지 않게)

var sfx # sfx.gd — ready 가 되면 알림
var split := false # 이 빌드는 효과음을 따로 받아야 함
var loaded := false # 붙였음 (또는 쪼개지 않은 빌드)
var url := ""
var http: HTTPRequest
var tries := 0
var started_ms := 0
var frames := 0
var _waiting := true


# 순수 계산: 첫 pck 에서 빼 묶음으로 보낸 효과음인가 (addons/web_music/export.gd is_lazy_sfx 와 같은 규칙 — 그건 편집기 전용이라 여기 따로, 테스트가 둘이 같은지 봄)
static func is_lazy(file: String) -> bool:
	return file.ends_with(".wav") and not (file.begins_with("title.") or file.begins_with("ambientPing."))


# 순수 계산: 쪼갠 빌드인가 (웹이고 첫 pck 에 효과음 wav 가 없음)
static func is_split(web: bool, probe_in_pck: bool) -> bool:
	return web and not probe_in_pck


func _ready() -> void:
	split = is_split(Opts.web(), ResourceLoader.exists(PROBE)) and not Opts.args().has("--no-sfx-pack")
	loaded = not is_split(Opts.web(), ResourceLoader.exists(PROBE))
	if not split:
		set_process(false)
		return
	url = str(JavaScriptBridge.eval("new URL('sfx.pck', location.href).href", true))
	http = HTTPRequest.new()
	http.use_threads = false
	http.accept_gzip = false # 웹은 브라우저가 이미 풀어 줌 (고도가 또 풀면 깨짐)
	add_child(http)
	http.request_completed.connect(_on_done)


func _process(_dt: float) -> void:
	frames += 1
	if _waiting and frames >= START_FRAMES:
		_waiting = false
		_fetch()


func _fetch() -> void:
	tries += 1
	started_ms = Time.get_ticks_msec()
	var err := http.request(url)
	if err != OK:
		_retry("시작 실패 %d" % err)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_retry("받기 실패 result=%d code=%d" % [result, code])
		return
	var f := FileAccess.open(FILE, FileAccess.WRITE) # 웹 HTTPRequest 는 download_file 이 안 먹어서 (파일이 안 생김) 본문을 직접 저장
	if f == null or body.is_empty():
		_retry("저장 실패 (본문 %d바이트)" % body.size())
		return
	f.store_buffer(body)
	f.close()
	if not ProjectSettings.load_resource_pack(FILE):
		_retry("붙이기 실패 (본문 %d바이트)" % body.size())
		return
	loaded = true
	set_process(false)
	print("[효과음 묶음] 받아 붙임 %.1f초 (%s 읽힘 %s)" % [(Time.get_ticks_msec() - started_ms) / 1000.0, PROBE.get_file(), load(PROBE) != null])
	if sfx != null:
		sfx.pack_ready()


func _retry(why: String) -> void:
	print("[효과음 묶음] %s (%d/%d)" % [why, tries, TRIES])
	if tries >= TRIES:
		set_process(false)
		return
	await get_tree().create_timer(RETRY_MS / 1000.0).timeout
	_fetch()

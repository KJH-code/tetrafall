# 효과음 묶음 따로 받기 (웹만, W53 2026-11-14): 효과음 wav 녹음본 전부는 웹 첫 pck 에서 빠지고 (addons/web_music 내보내기 플러그인 → 웹 빌드 폴더 묶음 파일) 첫 화면이 뜬 뒤
# 여기서 받아 user://<묶음>.pck 로 저장 → ProjectSettings.load_resource_pack 으로 붙임 (웹 첫 받기 br ~3.6MB 줄임).
# 묶음 = 'sfx' (공통 효과음 wav, sfx.pck) + 테마마다 't_<테마>' (타이틀 착지·빛 터짐·빠져나가기 + 앰비언트 핑, sfx_t_<테마>.pck 약 0.3MB — 한 번 켜면 한 테마만 쓰니 나머지는 뒤에).
# 받는 순서: 이번 메뉴 테마 (타이틀이 바로 씀) → 공통 → 다른 테마 (music.gd 가 필요한 테마를 want 로 앞에 올림). 받는 동안 그 소리는 조용히 넘어감 (sfx.gd stream 이 null — 캐시 안 함).
# PC·옛 웹 빌드·묶음이 없는 빌드는 pck 안 그대로라 아무 일 없음. 끄기: 웹 주소 ?no-sfx-pack (묶음 안 받음 = 효과음 없음, 확인용). 실패하면 RETRY_MS 뒤 다시 (묶음마다 최대 TRIES)
extends Node

const Opts := preload("res://core/opts.gd")
const C := preload("res://core/config.gd")

const PROBE := "res://audio/baked/swing.none.0.wav" # 이게 첫 pck 안에 있으면 쪼개지 않은 빌드 (PC·옛 웹)
const RETRY_MS := 15000
const TRIES := 4
const START_FRAMES := 30 # 첫 화면 뒤 이만큼 프레임 지나서 받기 시작 (켜는 프레임에 겹치지 않게)

var sfx # sfx.gd
var split := false # 이 빌드는 효과음을 따로 받아야 함
var done := {} # 묶음 이름 → true (붙였음)
var queue: Array = [] # 받을 묶음 (앞이 먼저)
var busy := "" # 지금 받는 묶음
var tries := {} # 묶음 → 시도 수
var failed_until := {} # 묶음 → 다시 해 볼 시각 (ms)
var url_base := ""
var http: HTTPRequest
var started_ms := 0
var frames := 0
var first_ms := -1


# 순수 계산: 이 파일이 어느 묶음인가 ("" = 묶음이 아님 = 첫 pck 안, wav 만 묶음에 들어감). 내보내기 플러그인 (addons/web_music/export.gd group_of) 과 같은 규칙 — 그건 편집기 전용이라 여기 따로, 테스트가 둘이 같은지 봄
static func group_of(file: String) -> String:
	if not file.ends_with(".wav"):
		return ""
	var p := file.split(".")
	if p.size() > 2 and (p[0] == "title" or p[0] == "ambientPing"):
		return "t_" + p[1]
	return "sfx"


static func pack_name(group: String) -> String:
	return "sfx.pck" if group == "sfx" else "sfx_%s.pck" % group


# 순수 계산: 쪼갠 빌드인가 (웹이고 첫 pck 에 효과음 wav 가 없음)
static func is_split(web: bool, probe_in_pck: bool) -> bool:
	return web and not probe_in_pck


# 순수 계산: 받을 순서 — 메뉴 테마 묶음 → 공통 → 나머지 테마 (menu_theme 이 모르는 테마면 그것만 뺌)
static func order(themes: Array, menu_theme: String) -> Array:
	var out: Array = []
	if themes.has(menu_theme):
		out.append("t_" + menu_theme)
	out.append("sfx")
	for t in themes:
		if "t_" + str(t) not in out:
			out.append("t_" + str(t))
	return out


func _ready() -> void:
	var probe_in := ResourceLoader.exists(PROBE)
	split = is_split(Opts.web(), probe_in) and not Opts.args().has("--no-sfx-pack")
	if not is_split(Opts.web(), probe_in) or not split:
		set_process(false)
		return
	url_base = str(JavaScriptBridge.eval("new URL('./', location.href).href", true))
	http = HTTPRequest.new()
	http.use_threads = false
	http.accept_gzip = false # 웹은 브라우저가 이미 풀어 줌 (고도가 또 풀면 깨짐)
	add_child(http)
	http.request_completed.connect(_on_done)
	queue = order(C.TITLE_THEMES.keys(), str(View.get("menu_theme")))


# 이 파일을 지금 읽을 수 있나 (묶음이 아니거나, 그 묶음이 붙었거나, 쪼개지 않은 빌드)
func has_file(file: String) -> bool:
	var g := group_of(file)
	return g == "" or not split or bool(done.get(g, false))


# 필요한 묶음을 앞으로 (music.gd 가 앰비언트 테마가 바뀔 때)
func want(group: String) -> void:
	if not split or done.get(group, false) or group == busy or not queue.has(group):
		return
	queue.erase(group)
	queue.push_front(group)


func _process(_dt: float) -> void:
	frames += 1
	if frames >= START_FRAMES and busy == "":
		_next()


func _next() -> void:
	var now := Time.get_ticks_msec()
	for g in queue:
		if now < int(failed_until.get(g, 0)):
			continue
		busy = g
		queue.erase(g)
		tries[g] = int(tries.get(g, 0)) + 1
		started_ms = now
		if first_ms < 0:
			first_ms = now
		var err := http.request(url_base + pack_name(g))
		if err != OK:
			_fail(g, "시작 실패 %d" % err)
		return
	if queue.is_empty():
		set_process(false)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var g := busy
	if g == "":
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail(g, "받기 실패 result=%d code=%d" % [result, code])
		return
	var path := "user://" + pack_name(g) # 웹 HTTPRequest 는 download_file 이 안 먹어서 (파일이 안 생김) 크기을 직접 저장
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null or body.is_empty():
		_fail(g, "저장 실패 (크기 %d바이트)" % body.size())
		return
	f.store_buffer(body)
	f.close()
	if not ProjectSettings.load_resource_pack(path):
		_fail(g, "붙이기 실패 (크기 %d바이트)" % body.size())
		return
	done[g] = true
	busy = ""
	print("[효과음 묶음] %s 붙임 %.1f초 (%d바이트, 남은 %d)" % [g, (Time.get_ticks_msec() - started_ms) / 1000.0, body.size(), queue.size()])
	if queue.is_empty():
		print("[효과음 묶음] 전부 붙임 (%.1f초 동안, %s 열림 %s)" % [(Time.get_ticks_msec() - first_ms) / 1000.0, PROBE.get_file(), load(PROBE) != null])


func _fail(g: String, why: String) -> void:
	print("[효과음 묶음] %s %s (%d/%d)" % [g, why, int(tries.get(g, 0)), TRIES])
	busy = ""
	if int(tries.get(g, 0)) < TRIES:
		failed_until[g] = Time.get_ticks_msec() + RETRY_MS
		queue.append(g)

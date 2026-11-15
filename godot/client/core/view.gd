# 화면 쪽 공용 상태 (자동 로드 View, G0 가 가짐): 서버가 모르는 것 — 시점·관전 대상·설정. 묶음끼리 노드 경로로 서로 부르지 않고 여기로.
# 필드를 더할 땐 이 파일에 한 줄 + 주석 (누가 쓰고 누가 읽는지), 커밋 메시지에 'View 필드 추가'.
# 설정은 user://settings.json 에 기억 (JS 판 localStorage tf-* 자리)
extends Node
const Opts := preload("res://core/opts.gd")

const C := preload("res://core/config.gd")
const UiScale := preload("res://core/ui_scale.gd")
const CharsK := preload("res://chars/chars_config.gd")

signal changed(key: String)

const PATH := "user://settings.json"

# 시점: "first" | "third" | "sky" | "spectate" (G1 카메라가 정하고 씀, G4 HUD 가 읽음)
var mode := "third"
# 관전 대상 플레이어 id (G1 이 정함, G4 가 이름 표시)
var spectate_target = null
# 설정 (G4 설정 창이 바꿈, 전부 읽음). 이름·기본값은 JS 판 설정 (main.js SETTINGS_DEFAULT, tf-settings) 과 같게
var settings := {
	"sens": 1.0, # 마우스 감도 배수 (PlayerInput)
	"sfx": 1.0, # 효과음 크기 0~1 (audio/)
	"music": 1.0, # 음악 크기 0~1 (audio/)
	"fov": C.FOV_DEFAULT, # 시야각 (G1 카메라)
	"shadows": true, # 그림자 (G1)
	"outline": not Opts.web(), # 외곽선 (G3). 웹은 기본 끔 (W29, 설정 창에서 켬)
	"lowGfx": false, # 그래픽 낮춤 (G1·G3·G5). W6 부터는 화질 (gfx) 이 낮음이면 켬 — world/gfx.gd 가 씀
	"gfx": "", # 화질 "auto"|"high"|"medium"|"low" (G4 설정 창이 씀, world/gfx.gd 가 읽어 lowGfx·3D 배율·MSAA 를 정함). 빈 값 = 예전 파일: lowGfx 켬이면 낮음, 아니면 자동
	"adaptRes": true, # 3D 해상도 자동 (적응형, W31 — world/adapt_calc.gd). 새 설치는 켬, 예전 파일에서 화질을 직접 골라 둔 사용자는 끔 (migrate_adapt)
	"third": false, # 3인칭 시작 (G1)
	"reducedMotion": false, # 움직임 줄이기 (G4·G5, JS 는 브라우저 설정)
	"perf": false, # F3 성능 표시 (G6, JS tf-perf)
	"motionFlags": CharsK.EXT_MOTION_FLAGS.duplicate(), # 모션 가산 층 켬·끔 (W49, 설정 창 '모션' 프리셋·개별 토글 — chars/chars_config.gd EXT_MOTION_FLAGS 가 이름·프리셋 표. 기본은 모두 켬 = 새 모션. 인자 --motion·--no-w43 등은 이것과 합집합)
	"uiScale": "auto", # UI 크기 (W9): "auto" (창 크기에 맞춤) 또는 0.8·1·1.25·1.5·2 (JS 브라우저 확대 자리) — core/ui_scale.gd, 설정 창이 바꿈
}
# 지금 UI 배율 (W9, core/ui_scale.gd — View 가 창 크기·설정으로 정함). 화면 픽셀 = UI 좌표 × ui_scale. 초상 (ui/portrait.gd) 이 선명하게 그릴 크기로 읽음
var ui_scale := 1.0
# 메뉴(방 밖) 배경 테마 id (TITLE_THEMES 키, JS menu-theme.js). 메뉴 3D 배경을 그리는 쪽이 정함, audio/ 가 메뉴 앰비언트로 읽음
var menu_theme = null
# 화면 판 빛 색 테마 (JS menu-theme.js markTheme — body data-theme): 메뉴 = 메뉴 테마, 대기실 = 고른 맵 테마. title/title.gd 가 정함, G4 ui_style 이 읽음 (없으면 자수정)
var ui_theme = null
# 타이틀 화면이 떠 있음 (Enter 전·날아가는 동안): G4 ui 가 메뉴 판을 숨김. title/title.gd 가 정함
var title_on := false
# 3D 이름표를 숨길 화면 사각형 (Rect2, 화면 px) — G4 UI 판 (대기실 플레이어 관리·방 판·결과 판 등) 이 보일 때 넣음, G1 (world/bodies.gd thin_labels) 이 읽음
var covers: Array = []

# 화면 시간 배율 (KO 마지막 킬 슬로모션·압사 히트스톱, JS ko.timeScale): G5 fx 가 프레임마다 정함, 화면 움직임 (G1·G2) 이 프레임 dt 에 곱함. 서버·보간과 상관없음
var time_scale := 1.0
# 판 끝 연출 단계 (shared/victory.js): "slow" | "closeup" | "results" | "lobby" 와 클로즈업 승자 id. G1 카메라가 정함, G4 (승리 큰 글씨·결과 표 시각)·G2 (승리 포즈) 가 읽음
var victory_stage := "lobby"
var victory_id = null
# 화면 쪽 소리 신호 (판 그리기·KO 연출이 내고 audio/ 가 받음 — JS renderer.onBlast·onArrowStuck·onHazardRise·ko.on 자리):
# "ui" {key} (화면 소리 그대로: 튜토리얼 해냄 clear·끝 win) · "blast" {x,y,z,big,wood} · "arrowStuck" {x,y,z} · "hazardRise" {style,x,y,z} · "smash"·"koCrush" {x,y,z,me,near} · "final" {x,y,z} · "slowmo" {scale}
signal sound_cue(kind: String, info: Dictionary)
# 화면 창 열기 요청 (G4 메뉴·설정의 버튼 → 그 창을 가진 묶음): "tutorial" (G6 ui/tutorial_ui.gd)
signal open_panel(name: String)


# 저장된 설정 → 3D 해상도 자동 여부 (W31): 값이 있으면 그대로, 없는데 (예전 파일) 화질을 높음·보통·낮음으로 직접 골라 뒀으면 존중해서 끔, 아니면 켬
static func migrate_adapt(d: Dictionary) -> bool:
	if d.has("adaptRes"):
		return bool(d.adaptRes)
	return str(d.get("gfx", "")) not in ["high", "medium", "low"]


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(d) == TYPE_DICTIONARY:
			for k in d:
				settings[k] = d[k]
			settings.adaptRes = migrate_adapt(d)
	settings.uiScale = UiScale.normalize(settings.get("uiScale", "auto"))
	settings.motionFlags = _clean_motion(settings.get("motionFlags"))
	CharsK.set_flags(settings.motionFlags)
	PlayerInput.sensitivity = float(settings.sens)
	_startup_window()
	get_window().size_changed.connect(apply_ui_scale)
	apply_ui_scale()


# UI 배율 적용 (core/ui_scale.gd): 창 크기가 바뀔 때·설정 'UI 크기' 가 바뀔 때. 재시작 없이 바로
func apply_ui_scale() -> void:
	var s := UiScale.apply(get_window(), settings.get("uiScale", "auto"))
	if absf(ui_scale - s) > 1e-4:
		ui_scale = s
		changed.emit("uiScale")


# 처음 창 크기 (W9): 윈도우 화면 배율 150%·200% 면 1280×720 창을 그만큼 키움 (UI 자동 배율도 따라 커짐). 웹·전체 화면·--resolution 이면 안 함
func _startup_window() -> void:
	if Opts.web() or DisplayServer.get_name() == "headless" or OS.has_feature("editor"):
		return
	var w := get_window()
	if w.mode != Window.MODE_WINDOWED:
		return
	for a in OS.get_cmdline_args():
		if a in ["--resolution", "-f", "--fullscreen", "-m", "--maximized", "-w", "--windowed", "--position"]:
			return
	var scr := w.current_screen
	var k := UiScale.screen_scale(DisplayServer.screen_get_scale(scr), DisplayServer.screen_get_dpi(scr), OS.has_feature("windows"))
	var usable := DisplayServer.screen_get_usable_rect(scr)
	var want := UiScale.startup_window(w.size, k, usable.size)
	if want != w.size:
		w.size = want
		w.position = usable.position + (usable.size - want) / 2


func set_mode(m: String) -> void:
	if m != mode:
		mode = m
		changed.emit("mode")


# 저장된 모션 플래그 → 표에 있는 이름만, 값 bool (빠진 이름은 기본값 = 켬). 예전 파일·손으로 고친 파일 방어
static func _clean_motion(d) -> Dictionary:
	var out := {}
	for k in CharsK.EXT_MOTION_FLAGS:
		out[k] = bool(d.get(k, CharsK.EXT_MOTION_FLAGS[k])) if d is Dictionary else bool(CharsK.EXT_MOTION_FLAGS[k])
	return out


func set_setting(key: String, value) -> void:
	settings[key] = value
	if key == "motionFlags":
		settings[key] = _clean_motion(value)
		CharsK.set_flags(settings[key]) # 판 중에도 다음 프레임부터 (Ext 가 프레임마다 CharsK.flag 를 읽음)
	if key == "sens":
		PlayerInput.sensitivity = float(value)
	if key == "uiScale":
		settings[key] = UiScale.normalize(value)
		if is_inside_tree():
			apply_ui_scale()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))
	changed.emit(key)

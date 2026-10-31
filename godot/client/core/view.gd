# 화면 쪽 공용 상태 (자동 로드 View, G0 가 가짐): 서버가 모르는 것 — 시점·관전 대상·설정. 묶음끼리 노드 경로로 서로 부르지 않고 여기로.
# 필드를 더할 땐 이 파일에 한 줄 + 주석 (누가 쓰고 누가 읽는지), 커밋 메시지에 'View 필드 추가'.
# 설정은 user://settings.json 에 기억 (JS 판 localStorage tf-* 자리)
extends Node

const C := preload("res://core/config.gd")

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
	"outline": true, # 외곽선 (G3)
	"lowGfx": false, # 그래픽 낮춤 (G1·G3·G5)
	"third": false, # 3인칭 시작 (G1)
	"reducedMotion": false, # 움직임 줄이기 (G4·G5, JS 는 브라우저 설정)
	"perf": false, # F3 성능 표시 (G6, JS tf-perf)
}
# 메뉴(방 밖) 배경 테마 id (TITLE_THEMES 키, JS menu-theme.js). 메뉴 3D 배경을 그리는 쪽이 정함, audio/ 가 메뉴 앰비언트로 읽음
var menu_theme = null

# 화면 쪽 소리 신호 (판 그리기·KO 연출이 내고 audio/ 가 받음 — JS renderer.onBlast·onArrowStuck·onHazardRise·ko.on 자리):
# "blast" {x,y,z,big,wood} · "arrowStuck" {x,y,z} · "hazardRise" {style,x,y,z} · "smash"·"koCrush" {x,y,z,me,near} · "final" {x,y,z} · "slowmo" {scale}
signal sound_cue(kind: String, info: Dictionary)


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(d) == TYPE_DICTIONARY:
			for k in d:
				settings[k] = d[k]
	PlayerInput.sensitivity = float(settings.sens)


func set_mode(m: String) -> void:
	if m != mode:
		mode = m
		changed.emit("mode")


func set_setting(key: String, value) -> void:
	settings[key] = value
	if key == "sens":
		PlayerInput.sensitivity = float(value)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))
	changed.emit(key)

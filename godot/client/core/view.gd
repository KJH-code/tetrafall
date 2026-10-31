# 화면 쪽 공용 상태 (자동 로드 View, G0 가 가짐): 서버가 모르는 것 — 시점·관전 대상·설정. 묶음끼리 노드 경로로 서로 부르지 않고 여기로.
# 필드를 더할 땐 이 파일에 한 줄 + 주석 (누가 쓰고 누가 읽는지), 커밋 메시지에 'View 필드 추가'.
# 설정은 user://settings.json 에 기억 (JS 판 localStorage tf-* 자리)
extends Node

signal changed(key: String)

const PATH := "user://settings.json"

# 시점: "first" | "third" | "sky" | "spectate" (G1 카메라가 정하고 씀, G4 HUD 가 읽음)
var mode := "third"
# 관전 대상 플레이어 id (G1 이 정함, G4 가 이름 표시)
var spectate_target = null
# 설정 (G4 설정 창이 바꿈, 전부 읽음). 이름은 JS 판 설정과 같게
var settings := {
	"lowGraphics": false, # 그래픽 낮춤 (G1·G3·G5)
	"reducedMotion": false, # 움직임 줄이기 (G4·G5)
	"sensitivity": 1.0, # 마우스 감도 배수 (PlayerInput)
	"volume": 1.0, # 효과음 (G5)
	"music": 0.6, # 음악 (G5)
	"perf": false, # F3 성능 표시 (G6)
}


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(d) == TYPE_DICTIONARY:
			for k in d:
				settings[k] = d[k]
	PlayerInput.sensitivity = float(settings.sensitivity)


func set_mode(m: String) -> void:
	if m != mode:
		mode = m
		changed.emit("mode")


func set_setting(key: String, value) -> void:
	settings[key] = value
	if key == "sensitivity":
		PlayerInput.sensitivity = float(value)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))
	changed.emit(key)

# 조작 키 설정 (client/keys.js 그대로): 행동마다 키 하나. 키 이름은 브라우저 e.code 와 같은 글자 ("KeyW", "Space", "Mouse0")
# → JS 판 tf-keys 와 같은 값, 설정 창 글자도 같음. 저장은 user://keys.json (웹이면 브라우저 저장소)
extends RefCounted

const C := preload("res://core/config.gd")

# 설정 창 순서대로. group 은 설정 창 소제목
const ACTIONS := [
	{"id": "fwd", "label": "앞으로", "def": "KeyW", "group": "이동"},
	{"id": "back", "label": "뒤로", "def": "KeyS", "group": "이동"},
	{"id": "left", "label": "왼쪽", "def": "KeyA", "group": "이동"},
	{"id": "right", "label": "오른쪽", "def": "KeyD", "group": "이동"},
	{"id": "jump", "label": "점프·2단 점프", "def": "Space", "group": "이동"},
	{"id": "dash", "label": "대시", "def": "ShiftLeft", "group": "이동"},
	{"id": "attack", "label": "평타 (밀치기)", "def": "Mouse0", "group": "공격"},
	{"id": "item", "label": "든 아이템 쓰기", "def": "Mouse2", "group": "공격"},
	{"id": "skill", "label": "스킬", "def": "KeyF", "group": "공격"},
	{"id": "ult", "label": "필살기", "def": "KeyR", "group": "공격"},
	{"id": "rotL", "label": "회전 · 설치 방향 ←", "def": "KeyQ", "group": "블록"},
	{"id": "rotR", "label": "회전 · 설치 방향 →", "def": "KeyE", "group": "블록"},
	{"id": "pieceUp", "label": "블록 앞으로", "def": "ArrowUp", "group": "블록"},
	{"id": "pieceDown", "label": "블록 뒤로", "def": "ArrowDown", "group": "블록"},
	{"id": "pieceLeft", "label": "블록 왼쪽", "def": "ArrowLeft", "group": "블록"},
	{"id": "pieceRight", "label": "블록 오른쪽", "def": "ArrowRight", "group": "블록"},
	{"id": "drop", "label": "블록 바로 낙하", "def": "Enter", "group": "블록"},
	{"id": "viewL", "label": "하늘 시점 돌리기 ↺ (블록 마스터·조종)", "def": "KeyZ", "group": "블록"},
	{"id": "viewR", "label": "하늘 시점 돌리기 ↻", "def": "KeyC", "group": "블록"},
	{"id": "view", "label": "1인칭 ↔ 3인칭", "def": "KeyV", "group": "기타"},
	{"id": "emote", "label": "이모트 바퀴 (누르고 있기)", "def": "KeyG", "group": "기타"},
	{"id": "help", "label": "조작법 보기 (누르고 있기)", "def": "KeyH", "group": "기타"},
	{"id": "practice", "label": "연습 창 열기·닫기 (연습 방) · 점수표 (킬 점수전, 누르고 있기)", "def": "Tab", "group": "기타"},
	{"id": "perf", "label": "성능 표시 켜기·끄기 (FPS·구간 ms)", "def": "F3", "group": "기타"},
	{"id": "tutSkip", "label": "튜토리얼 이 단계 넘기기", "def": "KeyN", "group": "기타"},
]

const SAVE_PATH := "user://keys.json"
const SAME := {"ShiftRight": "ShiftLeft", "ControlRight": "ControlLeft", "AltRight": "AltLeft", "MetaRight": "MetaLeft"}
const MOUSE := ["좌클릭", "휠 클릭", "우클릭", "마우스 뒤", "마우스 앞"]
const NAMED := {
	"Space": "Space", "ShiftLeft": "Shift", "ControlLeft": "Ctrl", "AltLeft": "Alt", "MetaLeft": "Win", "Enter": "Enter", "Tab": "Tab", "Backspace": "←Back",
	"CapsLock": "Caps", "Escape": "Esc", "ArrowUp": "↑", "ArrowDown": "↓", "ArrowLeft": "←", "ArrowRight": "→",
	"Backquote": "`", "Minus": "-", "Equal": "=", "BracketLeft": "[", "BracketRight": "]", "Backslash": "\\", "Semicolon": ";", "Quote": "'", "Comma": ",", "Period": ".", "Slash": "/",
}


static func default_binds() -> Dictionary:
	var out := {}
	for a in ACTIONS:
		out[a.id] = a.def
	return out


static func norm_code(code: String) -> String:
	return SAME.get(code, code)


# 화면에 보일 이름: KeyF → F, Digit1 → 1, Mouse2 → 우클릭, Numpad5 → 숫자판 5
static func key_label(code: String) -> String:
	if code == "":
		return "없음"
	if code.begins_with("Mouse"):
		var i := int(code.substr(5))
		return MOUSE[i] if i >= 0 and i < MOUSE.size() else "마우스 %s" % code.substr(5)
	if code.begins_with("Key"):
		return code.substr(3)
	if code.begins_with("Digit"):
		return code.substr(5)
	if code.begins_with("Numpad"):
		return "숫자판 %s" % code.substr(6)
	return NAMED.get(code, code)


# 저장된 키 (없거나 깨졌으면 기본값). 없는 행동은 기본값으로 채움
static func load_binds() -> Dictionary:
	var out := default_binds()
	if not FileAccess.file_exists(SAVE_PATH):
		return out
	var saved = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(saved) != TYPE_DICTIONARY:
		return out
	for a in ACTIONS:
		if saved.get(a.id) is String and saved[a.id] != "":
			out[a.id] = saved[a.id]
	return out


static func save_binds(binds: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(binds))


# 겹치는 키: { code: [행동 id, ...] } (둘 이상인 것만)
static func conflicts(binds: Dictionary) -> Dictionary:
	var by := {}
	for a in ACTIONS:
		var code: String = binds[a.id]
		if not by.has(code):
			by[code] = []
		by[code].append(a.id)
	var out := {}
	for code in by:
		if by[code].size() > 1:
			out[code] = by[code]
	return out


# 여러 키를 묶어 한 덩어리 글자로: 이동 4개가 다 글자 키면 붙여서 (WASD), 아니면 '/' 로
static func group_label(binds: Dictionary, ids: Array) -> String:
	var labels := []
	var single := true
	for id in ids:
		var l := key_label(binds[id])
		labels.append(l)
		if l.length() != 1 or not (l >= "A" and l <= "Z" or l >= "0" and l <= "9"):
			single = false
	return "".join(labels) if ids.size() == 4 and single else "/".join(labels)


# 이모트 바퀴 칸 고르기: w = 바퀴를 연 뒤 마우스를 움직인 양 (x 오른쪽, y 아래). 위가 0, 시계 방향으로 n 칸. minPx 보다 덜 움직였으면 -1
static func wheel_slot(w: Vector2, n: int, min_px: float) -> int:
	if n <= 0 or w.length() < min_px:
		return -1
	var ang := atan2(w.x, -w.y)
	return ((roundi(ang / (TAU / n)) % n) + n) % n


# 고도 입력 이벤트 → 브라우저 e.code 글자 (같은 키 설정을 쓰려고). 모르는 키는 ""
static func event_code(e: InputEvent) -> String:
	if e is InputEventMouseButton:
		return {MOUSE_BUTTON_LEFT: "Mouse0", MOUSE_BUTTON_MIDDLE: "Mouse1", MOUSE_BUTTON_RIGHT: "Mouse2", MOUSE_BUTTON_XBUTTON1: "Mouse3", MOUSE_BUTTON_XBUTTON2: "Mouse4"}.get(e.button_index, "")
	if not e is InputEventKey:
		return ""
	var k: int = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
	if k >= KEY_A and k <= KEY_Z:
		return "Key" + char(k)
	if k >= KEY_0 and k <= KEY_9:
		return "Digit" + char(k)
	if k >= KEY_KP_0 and k <= KEY_KP_9:
		return "Numpad%d" % (k - KEY_KP_0)
	if k >= KEY_F1 and k <= KEY_F12:
		return "F%d" % (k - KEY_F1 + 1)
	return {
		KEY_SPACE: "Space", KEY_SHIFT: "ShiftLeft", KEY_CTRL: "ControlLeft", KEY_ALT: "AltLeft", KEY_META: "MetaLeft",
		KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter", KEY_TAB: "Tab", KEY_BACKSPACE: "Backspace", KEY_CAPSLOCK: "CapsLock", KEY_ESCAPE: "Escape",
		KEY_UP: "ArrowUp", KEY_DOWN: "ArrowDown", KEY_LEFT: "ArrowLeft", KEY_RIGHT: "ArrowRight",
		KEY_QUOTELEFT: "Backquote", KEY_MINUS: "Minus", KEY_EQUAL: "Equal", KEY_BRACKETLEFT: "BracketLeft", KEY_BRACKETRIGHT: "BracketRight",
		KEY_BACKSLASH: "Backslash", KEY_SEMICOLON: "Semicolon", KEY_APOSTROPHE: "Quote", KEY_COMMA: "Comma", KEY_PERIOD: "Period", KEY_SLASH: "Slash",
	}.get(k, "")

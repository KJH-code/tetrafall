# W4 조작감·카메라가 JS 와 같은지 (client/input.js·main.js·render.js 를 숫자로 대조해 고친 것):
# 마우스 풀면 바퀴·도움말·점수표 닫기 · 창이 떠 있어도 키 뗌 · 판 시작·들어옴·튜토리얼 단계에 시점 방향 · 보간 시계 슬로모션 · 셀카 중 흔들림
extends RefCounted

const C := preload("res://core/config.gd")
const PI_ := preload("res://core/player_input.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


# input.js releaseAll: 마우스가 풀리면 (Esc) 눌린 키 + 이모트 바퀴 + 도움말·점수표까지 닫음
func test_unlock_releases_wheel_and_held_panels() -> void:
	var keep_locked := PlayerInput.locked
	var got := []
	var on_ui := func(id, pressed): got.append([id, pressed])
	var wheels := []
	var on_wheel := func(s): wheels.append(s)
	PlayerInput.ui_action.connect(on_ui)
	PlayerInput.wheel_changed.connect(on_wheel)
	PlayerInput.keys = {"KeyW": true, "KeyG": true}
	PlayerInput.wheel = Vector2(12, 3)
	PlayerInput.lock_mouse(false)
	check(PlayerInput.keys.is_empty(), "눌린 키 비움")
	check(PlayerInput.wheel == null and wheels == [-2], "바퀴 닫힘 %s" % [wheels])
	check(got.has(["help", false]) and got.has(["practice", false]), "도움말·점수표 닫기 %s" % [got])
	PlayerInput.ui_action.disconnect(on_ui)
	PlayerInput.wheel_changed.disconnect(on_wheel)
	PlayerInput.locked = keep_locked


func _key(k: Key, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = pressed
	return e


# JS keyup 은 글 칠 때도 받음: 창·글자 칸이 떠 있어도 뗌은 받아 키가 눌린 채로 남지 않음. 누름은 안 받음, 성능 표시 키만 (글자 칸이 아니면)
func test_blocked_input_still_releases() -> void:
	var keep := [PlayerInput.ui_blocking, PlayerInput.typing, PlayerInput.binds]
	PlayerInput.set_binds(PI_.Keys.default_binds())
	var fwd: String = PlayerInput.binds.fwd
	PlayerInput.keys = {fwd: true}
	PlayerInput.ui_blocking = true
	PlayerInput.typing = false
	var w: InputEventKey = _key(KEY_W, false)
	check(PI_.Keys.norm_code(PI_.Keys.event_code(w)) == fwd, "앞으로 키가 W (%s)" % fwd)
	PlayerInput._input(w)
	check(not PlayerInput.held("fwd"), "막혀 있어도 뗌은 받음")
	PlayerInput._input(_key(KEY_W, true))
	check(not PlayerInput.held("fwd"), "막혀 있으면 누름은 안 받음")
	var got := []
	var on_ui := func(id, pressed): got.append([id, pressed])
	PlayerInput.ui_action.connect(on_ui)
	var perf_code: String = PlayerInput.binds.perf
	var f3 := _key(KEY_F3, true)
	check(PI_.Keys.event_code(f3) == perf_code, "성능 표시 키 F3 (%s)" % perf_code)
	PlayerInput._input(f3)
	check(got == [["perf", true]], "메뉴·대기실에서도 F3 %s" % [got])
	got.clear()
	PlayerInput.typing = true
	PlayerInput._input(f3)
	check(got.is_empty(), "글자 칸이면 F3 도 안 받음 %s" % [got])
	PlayerInput.ui_action.disconnect(on_ui)
	PlayerInput.keys = {}
	PlayerInput.ui_blocking = keep[0]
	PlayerInput.typing = keep[1]
	PlayerInput.set_binds(keep[2])

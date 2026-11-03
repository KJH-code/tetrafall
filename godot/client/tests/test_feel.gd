# W4 조작감·카메라가 JS 와 같은지 (client/input.js·main.js·render.js 를 숫자로 대조해 고친 것):
# 마우스 풀면 바퀴·도움말·점수표 닫기 · 창이 떠 있어도 키 뗌 · 판 시작·들어옴·튜토리얼 단계에 시점 방향 · 보간 시계 슬로모션 · 셀카 중 흔들림
extends RefCounted

const C := preload("res://core/config.gd")
const PI_ := preload("res://core/player_input.gd")
const StoreS := preload("res://core/store.gd")
const CamRig := preload("res://world/cam_rig.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


# shared/config.js spawnPointsFor: 기본 판은 SPAWN_POINTS 그대로, 큰 판은 같은 안쪽 거리로 가운데를 봄
func test_spawn_points_for_matches_js() -> void:
	var pts: Array = PI_.spawn_points_for(C.GRID_W, C.GRID_D)
	check(pts.size() == C.SPAWN_POINTS.size(), "자리 수 %d" % pts.size())
	for i in pts.size():
		var a: Dictionary = pts[i]
		var b: Dictionary = C.SPAWN_POINTS[i]
		check(absf(a.x - b.x) < 1e-9 and absf(a.y - b.y) < 1e-9 and absf(a.yaw - b.yaw) < 1e-12, "자리 %d %s / JS %s" % [i, a, b])
	var big: Array = PI_.spawn_points_for(13, 13)
	check(absf(big[0].yaw - PI / 4.0) < 1e-12 and big[0].x == 2.5, "13칸 첫 자리 %s" % big[0])
	check(absf(big[4].yaw - PI / 2.0) < 1e-12 and big[4].x == 6.5 and big[4].y == 2.5, "13칸 다섯째 자리 %s" % big[4])


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


# 마우스를 잡은 채 판이 끝나거나 방을 나가면 풀림 (안 풀면 대기실·메뉴에서 커서가 안 보임). 판 중·연습 방은 그대로
func test_mouse_released_between_rounds_and_on_leave() -> void:
	var keep_locked := PlayerInput.locked
	var keep_room: Dictionary = Store.room
	Store.room = {"code": "TEST", "practice": false}
	for ph in ["over", "lobby"]:
		PlayerInput.locked = true
		PlayerInput._on_state({"phase": ph}, {})
		check(not PlayerInput.locked, "판 사이(%s)에 마우스 풀림" % ph)
	PlayerInput.locked = true
	PlayerInput._on_state({"phase": "playing"}, {})
	check(PlayerInput.locked, "판 중엔 그대로 잡힘")
	Store.room = {"code": "PRACT", "practice": true}
	PlayerInput.locked = true
	PlayerInput._on_state({"phase": "lobby"}, {})
	check(PlayerInput.locked, "연습 방은 풀지 않음")
	PlayerInput.locked = true
	PlayerInput._on_left_room("")
	check(not PlayerInput.locked, "방을 나가면 마우스 풀림")
	Store.room = keep_room
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


# main.js: 들어오면 내 자리 방향 (welcome.slot), 판 번호가 바뀌면 그 판 크기의 시작 방향, 튜토리얼 단계 처음엔 서버가 준 방향
func test_aim_resets_like_js() -> void:
	var keep := [Store.state, Store._players_by_id, Store.my_id, PlayerInput.yaw, PlayerInput.pitch]
	PlayerInput._on_message({"type": "welcome", "id": 5, "slot": 2, "room": {}})
	check(absf(PlayerInput.yaw - C.SPAWN_POINTS[2].yaw) < 1e-12 and PlayerInput.pitch == 0.0, "들어옴: 자리 2 방향 %s" % PlayerInput.yaw)
	PlayerInput._on_message({"type": "welcome", "id": 5, "slot": 3, "room": {}, "rejoined": true})
	check(absf(PlayerInput.yaw - C.SPAWN_POINTS[2].yaw) < 1e-12, "재접속은 스냅샷 방향 (welcome 으로 안 바꿈)")
	var me := {"id": 5, "slot": 4, "alive": true, "yaw": 0.3, "x": 1.0, "y": 1.0, "z": 0.0}
	Store.my_id = 5
	Store._players_by_id = {5: me}
	var st1 := {"phase": "lobby", "round": {"n": 0}, "field": {"w": 13, "d": 13}, "players": [me]}
	var st2 := {"phase": "countdown", "round": {"n": 1}, "field": {"w": 13, "d": 13}, "players": [me]}
	PlayerInput.set_yaw_pitch(2.0, 0.4)
	PlayerInput._on_state(st1, st1)
	check(PlayerInput.yaw == 2.0 and PlayerInput.pitch == 0.4, "같은 판이면 그대로")
	PlayerInput._on_state(st2, st1)
	check(absf(PlayerInput.yaw - PI / 2.0) < 1e-12 and PlayerInput.pitch == 0.0, "새 판: 13칸 자리 4 방향 π/2 (%s)" % PlayerInput.yaw)
	PlayerInput._on_event({"type": "tutorialStep", "who": 5, "yaw": -1.25})
	check(PlayerInput.yaw == -1.25, "튜토리얼 단계 방향 %s" % PlayerInput.yaw)
	PlayerInput._on_event({"type": "tutorialStep", "who": 6, "yaw": 0.5})
	check(PlayerInput.yaw == -1.25, "남의 단계는 무시")
	Store.state = keep[0]
	Store._players_by_id = keep[1]
	Store.my_id = keep[2]
	PlayerInput.set_yaw_pitch(keep[3], keep[4])


# 보간 화면 시계 (main.js dt = min(0.1, 프레임) × ko.timeScale): 슬로모션이면 사람 위치도 느리게, 긴 멈춤은 0.1초까지만
func test_interp_clock_dt_like_js() -> void:
	check(absf(StoreS.clock_dt_ms(0.016, 1.0) - 16.0) < 1e-9, "보통 프레임 16ms")
	check(absf(StoreS.clock_dt_ms(0.016, C.KO_FINAL_SCALE) - 4.0) < 1e-9, "마지막 킬 슬로모션 ×%s" % C.KO_FINAL_SCALE)
	check(absf(StoreS.clock_dt_ms(0.5, 1.0) - 100.0) < 1e-9, "긴 멈춤은 100ms 까지")


# render.js: 셀카 (내 이모트)·승자 클로즈업 중에도 camHook (흔들림·마지막 킬 줌·화면 끝 KO 빛) — 예전엔 건너뛰어 끝 빛이 멈춘 채 남음
func test_cam_hook_runs_during_selfie() -> void:
	var keep := [Store.state, Store._players_by_id, Store.my_id]
	var me := {"id": 5, "slot": 0, "alive": true, "yaw": 0.0, "x": 3.0, "y": 3.0, "z": 0.0, "emote": 1}
	Store.my_id = 5
	Store._players_by_id = {5: me}
	Store.state = {"phase": "playing", "round": {"n": 1}, "field": {"w": 10, "d": 10}, "players": [me], "pieces": []}
	var rig = CamRig.new()
	root().add_child(rig)
	var calls := [0]
	rig.hook = func(_cam): calls[0] += 1
	check(rig.close_id() == 5, "이모트 중이면 셀카 카메라")
	rig.place(0.016, {5: Vector3(3, 3, 0)}, func(_x, _y, _z): return false)
	check(calls[0] == 1, "셀카 중 camHook %d번" % calls[0])
	var cam: Camera3D = rig.cam
	rig.free()
	if is_instance_valid(cam) and cam.get_parent() == null:
		cam.free() # 러너 (_initialize) 동안엔 root 가 아직 트리 밖이라 _ready 가 안 불려 카메라가 rig 의 자식이 아님 → 따로 지움 (종료 시 Camera RID 누수)
	Store.state = keep[0]
	Store._players_by_id = keep[1]
	Store.my_id = keep[2]

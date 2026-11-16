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


# 마인크래프트처럼: 판이 시작되면 마우스를 자동으로 잡음 (클릭 안 해도). 메뉴·글자 칸이 열려 있거나 방 밖이면 안 잡음, 판 중간엔 다시 안 잡음
func test_mouse_auto_captured_at_round_start() -> void:
	var keep_locked := PlayerInput.locked
	var keep_room: Dictionary = Store.room
	var keep_block := PlayerInput.ui_blocking
	var keep_id = Store.my_id
	Store.my_id = 1 # 방 안 (in_room)
	Store.room = {"code": "TEST", "practice": false}
	PlayerInput.ui_blocking = false
	PlayerInput.locked = false
	PlayerInput._on_state({"phase": "countdown"}, {"phase": "lobby"})
	check(PlayerInput.locked, "카운트다운 시작에 자동으로 잡힘")
	PlayerInput.lock_mouse(false) # Esc
	PlayerInput._on_state({"phase": "playing"}, {"phase": "countdown"})
	check(not PlayerInput.locked, "판 중간 (카운트다운→플레이) 엔 다시 안 잡음")
	PlayerInput._on_state({"phase": "playing"}, {})
	check(PlayerInput.locked, "들어올 때 이미 판 중이면 잡음")
	PlayerInput.lock_mouse(false)
	PlayerInput.ui_blocking = true
	PlayerInput._on_state({"phase": "countdown"}, {"phase": "lobby"})
	check(not PlayerInput.locked, "설정·글자 칸이 열려 있으면 안 잡음")
	PlayerInput.ui_blocking = false
	Store.my_id = null # 방 밖
	PlayerInput._on_state({"phase": "countdown"}, {"phase": "lobby"})
	check(not PlayerInput.locked, "방 밖에서는 안 잡음")
	Store.room = keep_room
	Store.my_id = keep_id
	PlayerInput.ui_blocking = keep_block
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


# ---- c7 화면 가장자리 테 (ui/screen_edge.gd): 맞음·경직 알림이 가운데 장면과 아래 사람 판을 안 덮음 ----
const Edge := preload("res://ui/screen_edge.gd")


# 띠 두께 합 ≤ 화면 높이의 12%, 가운데 76% 사각형은 알파 0 (창 크기 둘)
func test_c7_edge_frame_keeps_center_clear() -> void:
	var E: Dictionary = Edge.EDGE
	check(absf(E.outer - 0.025) < 1e-9 and absf(E.inner - 0.09) < 1e-9 and E.outer + E.inner <= 0.12, "띠 두께: 바깥 2.5%% + 안쪽 9%% (%s)" % (E.outer + E.inner))
	for size in [Vector2(1280, 720), Vector2(960, 540)]:
		var b: Vector2 = Edge.band_px(size)
		check(absf(b.x - size.y * 0.025) < 1e-3 and absf(b.y - size.y * 0.09) < 1e-3 and b.x + b.y <= size.y * 0.12, "%s 띠 %s (합 ≤ 높이의 12%%)" % [size, b])
		# 가운데 76% 사각형 (가로·세로 12% ~ 88%) 안은 전부 0
		var lit := 0
		for iy in 39:
			for ix in 39:
				var pt := Vector2(size.x * (0.12 + 0.76 * ix / 38.0), size.y * (0.12 + 0.76 * iy / 38.0))
				if Edge.alpha_at(size, pt, 1.0) != 0.0:
					lit += 1
		check(lit == 0, "%s 가운데 76%% 에 테가 닿음 (%d 점)" % [size, lit])
		# 바깥 띠 = 받은 알파 그대로, 안쪽 띠 = inner_k 배에서 0 으로 줄어듦, 네 변 모두
		var mid: Vector2 = size / 2.0
		for pt in [Vector2(1, mid.y), Vector2(size.x - 1, mid.y), Vector2(mid.x, 1), Vector2(mid.x, size.y - 1), Vector2(2, 2)]:
			check(absf(Edge.alpha_at(size, pt, 0.8) - 0.8) < 1e-6, "%s 바깥 띠 %s 알파" % [size, pt])
		var prev := 1.0
		for i in 12:
			var d: float = b.x + b.y * (i + 0.5) / 12.0
			var a: float = Edge.alpha_at(size, Vector2(d, mid.y), 1.0)
			check(a < prev and a > 0.0 and a <= E.inner_k and absf(a - Edge.alpha_at(size, Vector2(mid.x, size.y - d), 1.0)) < 1e-6, "%s 안쪽 띠 d=%s 알파 %s (줄어듦, 위아래·좌우 같음)" % [size, d, a])
			prev = a
		check(Edge.alpha_at(size, Vector2(b.x + b.y + 0.5, mid.y), 1.0) == 0.0 and Edge.alpha_at(size, mid, 1.0) == 0.0, "띠 안쪽은 0")
		# 그리는 사다리꼴 8개: 가운데 사각형과 안 겹치고, 꼭짓점 알파가 alpha_at 과 같음
		var qs: Array = Edge.quads(size)
		check(qs.size() == 8, "사다리꼴 8개 (변 넷 × 바깥·안쪽)")
		var center: Rect2 = Rect2(size * 0.12, size * 0.76)
		for q in qs:
			var box := Rect2(q[0][0], Vector2.ZERO)
			for v in q[0]:
				box = box.expand(v)
			check(not box.intersects(center) and Rect2(Vector2.ZERO, size).grow(0.01).encloses(box), "사다리꼴 %s 이 가운데를 덮거나 화면 밖" % [q[0]])
			check(q[0].size() == 4 and q[1].size() == 4, "꼭짓점 넷")
		for q in qs.slice(0, 4):
			check(q[1][0] == 1.0 and q[1][2] == 1.0, "바깥 띠는 한 알파")
		for q in qs.slice(4):
			check(absf(q[1][0] - E.inner_k) < 1e-6 and q[1][2] == 0.0 and q[1][3] == 0.0, "안쪽 띠는 inner_k → 0")
		# 한 번에 그리는 삼각형 묶음 (그리기 1번): 사다리꼴 8개 = 삼각형 16개, 꼭짓점 알파 = 그 자리의 alpha_at (모서리 맞물림 포함)
		var t: Array = Edge.tri_arrays(size)
		check(t[0].size() == 48 and t[1].size() == 32 and t[2].size() == 32, "삼각형 16개·꼭짓점 32개 (%d·%d)" % [t[0].size(), t[1].size()])
		var bad := 0
		for i in t[0]:
			if i < 0 or i >= t[1].size():
				bad += 1
		for i in t[1].size():
			var want: float = Edge.alpha_at(size, t[1][i], 1.0)
			# 띠 경계의 꼭짓점은 두 값 (바깥 1 · 안쪽 inner_k) 중 하나
			if absf(t[2][i] - want) > 1e-4 and not (absf(want - 1.0) < 1e-4 and absf(t[2][i] - E.inner_k) < 1e-4):
				bad += 1
		check(bad == 0, "%s 삼각형 묶음 꼭짓점 번호·알파 어긋남 %d" % [size, bad])
	# 번쩍 색: 좁아진 만큼 진하게 (× 1.8, 1 을 안 넘음), 색은 그대로
	var hit: Color = Edge.flash_tint(Color(1, 0.824, 0, 0.45))
	check(absf(hit.a - 0.81) < 1e-6 and hit.r == 1.0 and absf(hit.g - 0.824) < 1e-6 and hit.b == 0.0, "맞음 노랑 0.45 → 바깥 띠 0.81 (%s)" % hit)
	check(Edge.flash_tint(Color(1, 1, 1, 0.9)).a == 1.0 and absf(Edge.flash_tint(Color(1, 0, 0, 0.22)).a - 0.396) < 1e-6, "알파 상한 1")
	check(absf(E.fade - 0.4) < 1e-9 and absf(E.stun_fade - 0.15) < 1e-9 and absf((E.stun as Color).a - 0.75) < 1e-6 and (E.stun as Color).r == 1.0 and (E.stun as Color).g == 0.0, "사라지는 시간·경직 색은 그대로 (0.4초·0.15초·빨강 0.75)")


# 번쩍·경직 테는 HUD 보다 먼저 그려지고 (z_index < 0), 화면 전체를 덮는 번쩍 판이 없음
func test_c7_edge_below_hud() -> void:
	var HudExtra := preload("res://ui/hud_extra.gd")
	var h = HudExtra.new()
	h._ready() # 러너에선 트리가 안 돌아 직접
	for e in [h.flash, h.vignette]:
		check(e.get_script() == Edge and e.get_parent() == h, "번쩍·경직 = 가장자리 테 노드")
		check(e.z_index < 0 and e.z_as_relative and h.z_index == 0, "HUD (0) 보다 먼저 그림 (z_index %d)" % e.z_index)
		check(not e.visible and e.modulate.a == 0.0 and e.mouse_filter == Control.MOUSE_FILTER_IGNORE, "꺼진 채로 시작 · 마우스를 안 막음")
		check(e.anchor_right == 1.0 and e.anchor_bottom == 1.0, "화면 전체 크기 (테만 그림)")
	for c in h.get_children():
		check(not (c is ColorRect and c.anchor_right == 1.0 and c.anchor_bottom == 1.0), "화면 전체 ColorRect 가 남아 있음: %s" % c)
		check(not (c is TextureRect and c.anchor_right == 1.0 and c.anchor_bottom == 1.0), "화면 전체 그림 판이 남아 있음: %s" % c)
		if c.get_script() != Edge:
			check(c.z_index >= 0, "HUD 나머지 (콤보·경직 글자·시계 …) 는 테 위: %s" % c)
	check((h.vignette.tint as Color).is_equal_approx(Edge.EDGE.stun), "경직 테 = 빨강 0.75")
	# 맞음 번쩍: 켜지고 색 = 노랑, 바깥 띠 알파 0.81 (트리 밖이라 사라짐 tween 은 안 돎)
	h.flash_screen(Color(1, 0.824, 0, 0.45))
	check(h.flash.visible and h.flash.modulate.a == 1.0 and (h.flash.tint as Color).is_equal_approx(Color(1, 0.824, 0, 0.81)), "번쩍 켜짐 %s" % h.flash.tint)
	check(not h.vignette.visible, "번쩍이 경직 테를 켜지 않음")
	h.vignette.set_level(0.5)
	check(h.vignette.visible and h.vignette.modulate.a == 0.5, "경직 테 세기")
	h.vignette.set_level(0.0)
	check(not h.vignette.visible, "세기 0 이면 안 그림")
	h.free()

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


# 띠 두께 합 ≤ 화면 높이의 12%, 가운데 76% 사각형은 알파 0 (창 크기 둘). c7-fix F6: 알파가 바깥에서 0 까지 끊김 없이 (띠 경계에 계단 없음)
func test_c7_edge_frame_keeps_center_clear() -> void:
	var E: Dictionary = Edge.EDGE
	check(absf(E.outer - 0.008) < 1e-9 and absf(E.inner - 0.107) < 1e-9 and E.outer + E.inner <= 0.12, "띠 두께: 바깥 0.8%% + 안쪽 10.7%% (%s)" % (E.outer + E.inner))
	check(not E.has("inner_k"), "안쪽 띠가 따로 시작하는 알파 (계단) 는 없음")
	var kn: Array = E.knee
	check(kn.size() == 2 and float(kn[0]) > 0.0 and float(kn[0]) < 1.0 and float(kn[1]) > 0.0 and float(kn[1]) < 1.0 - float(kn[0]), "꺾임 %s: 띠 안쪽 자리 · 곧은 선보다 아래 (처음에 빨리 줄어 빛처럼 번짐)" % [kn])
	for size in [Vector2(1280, 720), Vector2(960, 540)]:
		var b: Vector2 = Edge.band_px(size)
		check(absf(b.x - size.y * 0.008) < 1e-3 and absf(b.y - size.y * 0.107) < 1e-3 and b.x + b.y <= size.y * 0.12, "%s 띠 %s (합 ≤ 높이의 12%%)" % [size, b])
		# 가운데 76% 사각형 (가로·세로 12% ~ 88%) 안은 전부 0
		var lit := 0
		for iy in 39:
			for ix in 39:
				var pt := Vector2(size.x * (0.12 + 0.76 * ix / 38.0), size.y * (0.12 + 0.76 * iy / 38.0))
				if Edge.alpha_at(size, pt, 1.0) != 0.0:
					lit += 1
		check(lit == 0, "%s 가운데 76%% 에 테가 닿음 (%d 점)" % [size, lit])
		# 바깥 띠 = 받은 알파 그대로, 네 변 모두 (c8: 위쪽은 윗변 줄임 m(y) 만큼 옅음 — 윗변 점·구석)
		var mid: Vector2 = size / 2.0
		for pt in [Vector2(1, mid.y), Vector2(size.x - 1, mid.y), Vector2(mid.x, 1), Vector2(mid.x, size.y - 1), Vector2(2, 2)]:
			check(absf(Edge.alpha_at(size, pt, 0.8) - 0.8 * Edge.top_mul(size, pt.y)) < 1e-6, "%s 바깥 띠 %s 알파" % [size, pt])
		# 꺾임 점: 0 → 바깥 띠 끝 (1) → 꺾임 → 끝 (0), 거리는 늘고 알파는 안 늘어남
		var st: Array = Edge.stops(size)
		check(st.size() == 4 and st[0] == [0.0, 1.0] and absf(st[1][0] - b.x) < 1e-6 and st[1][1] == 1.0 and absf(st[3][0] - (b.x + b.y)) < 1e-6 and st[3][1] == 0.0, "%s 꺾임 점 %s" % [size, st])
		check(absf(st[2][0] - (b.x + b.y * float(kn[0]))) < 1e-6 and absf(st[2][1] - float(kn[1])) < 1e-6, "%s 꺾임 자리·알파" % size)
		# 계단 없음 (F6): 가장자리에서 띠 끝 너머까지 반 화소씩 걸으며 — 한 화소에 줄어드는 알파가 번지는 띠의 가장 가파른 기울기를 안 넘고, 다시 커지지 않음
		var steep: float = maxf((1.0 - float(kn[1])) / (b.y * float(kn[0])), float(kn[1]) / (b.y * (1.0 - float(kn[0]))))
		# c10: 옆변은 가로로 side 배 가늘어짐 — 옆변의 (d × side) 자리가 아랫변의 d 자리와 같은 알파, 가로로 걷는 기울기 한도는 세로 한도 ÷ side
		var side: float = float(E.side)
		var prev := 1.0
		var worst := 0.0
		var d := 0.0
		while d <= b.x + b.y + 2.0:
			var a: float = Edge.alpha_at(size, Vector2(d * side, mid.y), 1.0)
			check(a <= prev + 1e-6 and absf(a - Edge.alpha_at(size, Vector2(mid.x, size.y - d), 1.0)) < 1e-6, "%s d=%s 알파 %s (안 커짐, 위아래·좌우 같음)" % [size, d, a])
			worst = maxf(worst, prev - a)
			prev = a
			d += 0.5
		check(worst <= steep * 0.5 + 1e-6 and steep < 0.05, "%s 반 화소 걸음에 알파가 %.4f 넘게 떨어짐 (얻음 %.4f) — 띠 경계 계단" % [size, steep * 0.5, worst])
		var prev_x := 1.0
		var worst_x := 0.0
		var x := 0.0
		while x <= (b.x + b.y) * side + 2.0:
			var ax: float = Edge.alpha_at(size, Vector2(x, mid.y), 1.0)
			check(ax <= prev_x + 1e-6, "%s 옆변 x=%s 알파 %s (안 커짐)" % [size, x, ax])
			worst_x = maxf(worst_x, prev_x - ax)
			prev_x = ax
			x += 0.5
		check(worst_x <= steep / side * 0.5 + 1e-6, "%s 옆변 가로 반 화소 걸음에 알파가 %.4f 넘게 떨어짐 (얻음 %.4f) — 띠 경계 계단" % [size, steep / side * 0.5, worst_x])
		check(absf(Edge.alpha_at(size, Vector2(b.x * side + 0.01, mid.y), 1.0) - 1.0) < 1e-3, "%s 바깥 띠 바로 안쪽도 같은 알파 (예전엔 0.55배로 떨어짐)" % size)
		check(Edge.alpha_at(size, Vector2((b.x + b.y) * side + 0.5, mid.y), 1.0) == 0.0 and Edge.alpha_at(size, mid, 1.0) == 0.0, "띠 안쪽은 0")
		# 그리는 사다리꼴 12개 (변 넷 × 꺾임 점 사이 띠 셋): 가운데 사각형과 안 겹치고, 띠마다 꼭짓점 알파가 꺾임 점 값
		var qs: Array = Edge.quads(size)
		check(qs.size() == 12, "사다리꼴 12개 (변 넷 × 띠 셋)")
		var center: Rect2 = Rect2(size * 0.12, size * 0.76)
		for q in qs:
			var box := Rect2(q[0][0], Vector2.ZERO)
			for v in q[0]:
				box = box.expand(v)
			check(not box.intersects(center) and Rect2(Vector2.ZERO, size).grow(0.01).encloses(box), "사다리꼴 %s 이 가운데를 덮거나 화면 밖" % [q[0]])
			check(q[0].size() == 4 and q[1].size() == 4, "꼭짓점 넷")
		for band in 3:
			for q in qs.slice(band * 4, band * 4 + 4):
				check(absf(q[1][0] - float(st[band][1])) < 1e-6 and absf(q[1][1] - float(st[band][1])) < 1e-6 and absf(q[1][2] - float(st[band + 1][1])) < 1e-6 and absf(q[1][3] - float(st[band + 1][1])) < 1e-6, "띠 %d 알파 %s → %s" % [band, st[band][1], st[band + 1][1]])
		# 한 번에 그리는 삼각형 묶음 (그리기 1번): 모든 꼭짓점 알파 = 그 자리의 alpha_at (띠 경계 꼭짓점도 한 값 — 계단 없음).
		# c8: 옆 변 사다리꼴 6개를 윗변 줄임이 끝나는 높이에서 둘로 → 사다리꼴 18개 = 삼각형 36개 (예전 12개·24개)
		var t: Array = Edge.tri_arrays(size)
		check(t[0].size() == 108 and t[1].size() == 72 and t[2].size() == 72, "삼각형 36개·꼭짓점 72개 (%d·%d)" % [t[0].size(), t[1].size()])
		var bad := 0
		for i in t[0]:
			if i < 0 or i >= t[1].size():
				bad += 1
		for i in t[1].size():
			if absf(t[2][i] - Edge.alpha_at(size, t[1][i], 1.0)) > 1e-4:
				bad += 1
		check(bad == 0, "%s 삼각형 묶음 꼭짓점 번호·알파 어긋남 %d" % [size, bad])
	# 번쩍 색: 좁아진 만큼 진하게 (× 1.8, 1 을 안 넘음), 색은 그대로
	var hit: Color = Edge.flash_tint(Color(1, 0.824, 0, 0.45))
	check(absf(hit.a - 0.81) < 1e-6 and hit.r == 1.0 and absf(hit.g - 0.824) < 1e-6 and hit.b == 0.0, "맞음 노랑 0.45 → 바깥 띠 0.81 (%s)" % hit)
	check(Edge.flash_tint(Color(1, 1, 1, 0.9)).a == 1.0 and absf(Edge.flash_tint(Color(1, 0, 0, 0.22)).a - 0.396) < 1e-6, "알파 상한 1")
	check(absf(E.fade - 0.4) < 1e-9 and absf(E.stun_fade - 0.15) < 1e-9 and absf((E.stun as Color).a - 0.75) < 1e-6 and (E.stun as Color).r == 1.0 and (E.stun as Color).g == 0.0, "사라지는 시간·경직 색은 그대로 (0.4초·0.15초·빨강 0.75)")


# c7-fix F5: 3인칭이면 아래 묶음 (아이템·F·R·버프) 이 왼쪽 아래 구석 — 가운데 아래는 내 발밑 색 고리·'나' 흰 테 자리 (720p 에서 y≈595). 1인칭은 예전 그대로 가운데
func test_c7_stack_leaves_my_ring() -> void:
	var HudExtra := preload("res://ui/hud_extra.gd")
	var K: Dictionary = HudExtra.STACK
	var sizes := [Vector2(120, 26), Vector2(250, 28), Vector2(90, 22)] # 아이템·F·R·버프
	for vp in [Vector2(1280, 720), Vector2(960, 540)]:
		for cards_h in [0.0, 96.0]:
			# 1인칭: 가운데, 아래에서 위로 gap 6 (예전 식 그대로)
			var mid: Array = HudExtra.stack_layout(vp, sizes, cards_h, false)
			var y: float = vp.y - ((cards_h + 18.0) if cards_h > 0.0 else 16.0)
			for i in sizes.size():
				y -= sizes[i].y
				check(mid[i].is_equal_approx(Vector2((vp.x - sizes[i].x) / 2.0, y)), "%s 1인칭 칸 %d 자리 %s" % [vp, i, mid[i]])
				y -= 6.0
			# 3인칭: 왼쪽 구석 — 화면 가운데 1/3 (내 발 둘레) 에 아무 칸도 안 걸침, 화면 안, 아래 판 위
			var cor: Array = HudExtra.stack_layout(vp, sizes, cards_h, true, 0.0 if cards_h > 0.0 else 50.0)
			var foot := Rect2(vp.x / 3.0, vp.y * 0.6, vp.x / 3.0, vp.y * 0.4)
			var floor_y: float = vp.y - ((cards_h + float(K.above_cards)) if cards_h > 0.0 else (float(K.corner_bottom) + 50.0 + float(K.gap)))
			for i in sizes.size():
				var r := Rect2(cor[i], sizes[i])
				check(cor[i].x == float(K.corner_x) and not r.intersects(foot), "%s 3인칭 칸 %d 이 가운데 아래 (내 발) 를 덮음 %s" % [vp, i, r])
				check(r.position.y >= 0.0 and r.end.y <= floor_y + 1e-6 and (i == 0 or r.end.y <= cor[i - 1].y - float(K.gap) + 1e-6), "%s 3인칭 칸 %d 이 아래 판·내 %% 와 겹치거나 화면 밖 %s" % [vp, i, r])
	check(float(K.corner_x) == 22.0 and float(K.corner_bottom) == 18.0, "구석 자리 = 내 % 구석 (ui/hud.gd: x 22, 아래 18) 과 같은 값")
	check(HudExtra.stack_layout(Vector2(1280, 720), [], 0.0, true).is_empty(), "보이는 칸이 없으면 빈 목록")


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


# ---- c8 판 중 화면 마감: 킬 피드 한 줄 · 무기 이름 · 이벤트 알림 한 줄 · 테 윗변 줄임 · 묶음 자리 한 곳 ----
const UC := preload("res://ui/ui_calc.gd")


# 같은 스냅샷 묶음에 'kill' 이 있으면 'death' 는 피드·세기에 안 넣음 (예전: 가벼운 스냅샷으로 오면 같은 줄이 두 번). 'kill' 을 안 보내는 서버는 그대로
func test_c8_feed_one_row_per_death() -> void:
	var death := {"type": "death", "who": 1, "by": 7, "cause": "fall", "weapon": "push"}
	var kill := {"type": "kill", "victim": 1, "killer": 7, "cause": "fall", "weapon": "push"}
	check(not UC.death_feeds([death, kill]), "[death, kill] 묶음: death 는 피드에 안 넣음 (kill 이 맡음)")
	check(not UC.death_feeds([kill, death]) and not UC.death_feeds([{"type": "hit"}, death, {"type": "respawn"}, kill]), "순서·다른 이벤트가 섞여도")
	check(UC.death_feeds([death]), "[death] 만 (kill 을 안 보내는 서버): 예전 그대로 넣음")
	check(UC.death_feeds([]) and UC.death_feeds([{"type": "hit"}, {"type": "mark"}]), "빈 묶음·상관없는 이벤트")
	# hud.gd 가 그 판단을 씀 (death 갈래에서 지금 묶음 Store.state.events 로)
	var src := FileAccess.get_file_as_string("res://ui/hud.gd")
	check(src.contains("U.death_feeds(Store.state.get(\"events\", []))"), "hud.gd death 갈래가 U.death_feeds 를 부름")


# 서버가 보내는 무기 종류 (godot/server Tetrafall.Core GameUtil.cs WEAPON_LOG 29키) 는 전부 한글 이름 — 영문 키가 킬 피드·관전 안내에 그대로 안 나옴
func test_c8_weapon_ko_covers_server_kinds() -> void:
	var kinds := ["ghost", "push", "shell", "bigshell", "groundshot", "leapwave", "spin", "spinend", "note", "riff", "glide", "amp", "ampend", "pounce", "execute", "wallkick", "blast",
		"bigbomb", "projectile", "shock", "bomb", "control", "thrown", "slam", "hook", "charge", "slash", "wall", "blockslam"]
	check(kinds.size() == 29, "서버 표 29키")
	for k in kinds:
		var ko: String = UC.weapon_ko(k)
		check(ko != k and ko != "", "무기 %s 의 한글 이름이 없음 (%s)" % [k, ko])
	check(UC.weapon_ko("ampend") == "앰프 마무리" and UC.weapon_ko("spinend") == "소용돌이 마무리", "마무리 타격 이름")
	check(UC.cause_text("fall", "ampend") == "낙사 (앰프 마무리)", "킬 피드 원인 칸 %s" % UC.cause_text("fall", "ampend"))
	check(UC.weapon_ko("amp") == "앰프 음파" and UC.weapon_ko("spin") == "분노 소용돌이" and UC.weapon_ko(null) == "" and UC.weapon_ko("zzz") == "zzz", "예전 이름·빈 값·모르는 종류는 그대로")


# 돌발 이벤트: 시작 알림 ('돌풍 ↑') 이 떠 있는 동안 진행 띠 ('돌풍 ↑ 5초') 는 숨김 → 위 가운데 한 줄. 알림이 사라지면 띠
func test_c8_event_chip_hidden_under_toast() -> void:
	check(not UC.event_chip_on("돌풍 ↑ 5초", true), "알림이 떠 있으면 띠 숨김")
	check(UC.event_chip_on("돌풍 ↑ 5초", false), "알림이 없으면 띠")
	check(not UC.event_chip_on("", false) and not UC.event_chip_on("", true), "진행 중인 이벤트가 없으면 띠 없음")
	# hud_extra 가 그 알림 줄을 기억해 씀 (러너에선 트리가 안 돌아 알림 줄을 직접 넣음 — toast 의 사라짐 tween 은 트리 안에서만)
	var HudExtra := preload("res://ui/hud_extra.gd")
	var h = HudExtra.new()
	h._ready()
	var st := {"phase": "playing", "roundEvent": {"kind": "rain", "left": 4200.0}}
	h._event_chip(st)
	check(h.event_chip.visible and h.event_chip.text == "블록 폭우 5초", "알림 없이 진행 중: 띠 '%s'" % h.event_chip.text)
	var l := Label.new()
	l.text = "블록 폭우!"
	h.toasts.add_child(l)
	h.event_toast = l
	h._event_chip(st)
	check(not h.event_chip.visible, "시작 알림이 떠 있는 동안 띠 숨김")
	l.free() # 알림이 사라짐 (또는 넘쳐서 먼저 지워짐)
	h._event_chip(st)
	check(h.event_chip.visible and h.event_toast == null, "알림이 사라지면 띠가 다시 보임")
	h._event_chip({"phase": "over", "roundEvent": {"kind": "rain", "left": 4200.0}})
	check(not h.event_chip.visible, "판 중이 아니면 띠 없음 (예전 그대로)")
	h.free()


# 맞음·경직 테: 윗변 쪽만 옅게 (y = 0 에서 × top, 화면 높이 × top_ramp 아래는 그대로) — 위 HUD 를 덜 덮음. 배율은 자리 (y) 로만 정해 모서리에 계단이 없음
func test_c8_edge_top_dim() -> void:
	var E: Dictionary = Edge.EDGE
	check(absf(float(E.top) - 0.4) < 1e-9 and absf(float(E.top_ramp) - 0.3) < 1e-9, "윗변 배율 0.4 · 줄임 끝 높이 30%% (%s·%s)" % [E.top, E.top_ramp])
	check(float(E.top_ramp) > float(E.outer) + float(E.inner) and float(E.top_ramp) < 1.0 - float(E.outer) - float(E.inner), "줄임 끝 높이가 옆 변 띠 안 (모서리 맞물림 아래·아랫변 위)")
	var kn: Array = E.knee
	for size in [Vector2(1280, 720), Vector2(960, 540)]:
		var b: Vector2 = Edge.band_px(size)
		var mid: Vector2 = size / 2.0
		var ramp: float = size.y * float(E.top_ramp)
		var a := 0.8
		# 배율 m(y): 0 → top, ramp 이상 → 1, 사이는 곧게
		check(absf(Edge.top_mul(size, 0.0) - 0.4) < 1e-9 and Edge.top_mul(size, ramp) == 1.0 and Edge.top_mul(size, size.y) == 1.0, "%s m(0) = 0.4 · m(ramp 이상) = 1" % size)
		check(absf(Edge.top_mul(size, ramp / 2.0) - 0.7) < 1e-6 and absf(Edge.top_mul(size, ramp / 4.0) - 0.55) < 1e-6, "%s 사이는 곧게" % size)
		# 윗변 바깥 띠 ≈ 0.4a, 옆 변 (줄임 끝 아래)·아랫변 = a
		var top_a: float = Edge.alpha_at(size, Vector2(mid.x, 1), a)
		check(absf(top_a - a * Edge.top_mul(size, 1.0)) < 1e-6 and top_a > 0.4 * a - 1e-6 and top_a < 0.41 * a, "%s 윗변 (mid.x, 1) 알파 %.4f ≈ 0.4a" % [size, top_a])
		check(absf(Edge.alpha_at(size, Vector2(1, mid.y), a) - a) < 1e-6 and absf(Edge.alpha_at(size, Vector2(size.x - 1, mid.y), a) - a) < 1e-6, "%s 옆 변 가운데 = a" % size)
		check(absf(Edge.alpha_at(size, Vector2(mid.x, size.y - 1), a) - a) < 1e-6 and absf(Edge.alpha_at(size, Vector2(2, size.y - 2), a) - a) < 1e-6, "%s 아랫변·아래 구석 = a" % size)
		for y in [ramp, ramp + 1.0, size.y * 0.5, size.y * 0.8]:
			check(absf(Edge.alpha_at(size, Vector2(1, y), a) - a) < 1e-6 and absf(Edge.alpha_at(size, Vector2(size.x - 1, y), a) - a) < 1e-6, "%s 옆 변 y=%s (줄임 끝 아래) = a" % [size, y])
		# 옆 변 위쪽은 내려올수록 진해짐 (0.4a → a), 다시 옅어지지 않음
		var prev := 0.0
		var y0 := 1.0
		while y0 <= ramp + 2.0:
			var v: float = Edge.alpha_at(size, Vector2(1, y0), a)
			check(v >= prev - 1e-6 and v <= a + 1e-6, "%s 옆 변 y=%s 알파 %s (내려올수록 안 줄어듦)" % [size, y0, v])
			prev = v
			y0 += 1.0
		# 모서리에 계단 없음: 꺾임선 (c10: 축척 대각선 (d × side, d)) 근처에서 윗변 쪽·옆 변 쪽으로 반 화소 옮긴 값의 차가 번지는 띠의 가장 가파른 기울기 (반 화소 몫) 안 — 변마다 다른 배율이면 0.6a 가 한 번에 뜀.
		# 가로로 옮긴 값이 낀 차의 한도는 ÷ side (옆변 띠는 가로로 side 배 가늘어 그만큼 가파름), 세로로만 옮긴 차는 예전 한도
		var side: float = float(E.side)
		var steep: float = maxf((1.0 - float(kn[1])) / (b.y * float(kn[0])), float(kn[1]) / (b.y * (1.0 - float(kn[0]))))
		var worst := 0.0
		var worst_h := 0.0
		var d := 2.0
		while d <= b.x + b.y:
			for cx in [d * side, size.x - d * side]:
				var on: float = Edge.alpha_at(size, Vector2(cx, d), 1.0)
				var to_top: float = Edge.alpha_at(size, Vector2(cx + (0.5 if cx < mid.x else -0.5), d), 1.0) # 윗변 쪽 (대각선 안쪽 가로로)
				var to_side: float = Edge.alpha_at(size, Vector2(cx, d + 0.5), 1.0) # 옆 변 쪽 (세로로)
				worst = maxf(worst, absf(on - to_side))
				worst_h = maxf(worst_h, maxf(absf(to_top - to_side), absf(on - to_top)))
			d += 1.0
		check(worst <= steep * 0.5 + 1e-6, "%s 모서리 꺾임선에서 세로 반 화소에 알파가 %.4f 넘게 뜀 (얻음 %.4f) — 계단" % [size, steep * 0.5, worst])
		check(worst_h <= steep / side * 0.5 + 1e-6, "%s 모서리 꺾임선에서 가로 반 화소에 알파가 %.4f 넘게 뜀 (얻음 %.4f) — 계단" % [size, steep / side * 0.5, worst_h])
		# 그리는 꼭짓점: 옆 변을 줄임 끝 높이에서 나눈 자리에 꼭짓점 (띠 경계 넷 × 좌우), 같은 자리 꼭짓점은 같은 알파 (변마다 다른 값이 아님)
		var t: Array = Edge.tri_arrays(size)
		var at_ramp := 0
		var seen := {}
		var clash := 0
		for i in t[1].size():
			var v2: Vector2 = t[1][i]
			if absf(v2.y - ramp) < 1e-4:
				at_ramp += 1
				check(absf(t[2][i] - Edge.alpha_at(size, v2, 1.0)) < 1e-4, "%s 나눈 자리 꼭짓점 %s 알파" % [size, v2])
			var key := "%.3f,%.3f" % [v2.x, v2.y]
			if seen.has(key) and absf(float(seen[key]) - t[2][i]) > 1e-5:
				clash += 1
			seen[key] = t[2][i]
		check(at_ramp == 24, "%s 줄임 끝 높이의 꼭짓점 %d개 (옆 변 띠 6개 × 나눈 조각 둘 × 둘)" % [size, at_ramp])
		check(clash == 0, "%s 같은 자리인데 알파가 다른 꼭짓점 %d개" % [size, clash])
		var tl := -1.0
		for i in t[1].size():
			if (t[1][i] as Vector2).is_equal_approx(Vector2.ZERO):
				tl = t[2][i]
		check(absf(tl - 0.4) < 1e-6, "왼위 구석 꼭짓점 알파 배율 %.3f (0.4)" % tl)
	# 나누기: 세로 변이 그 높이를 지날 때만 둘로, 아니면 그대로
	var side_q := [PackedVector2Array([Vector2(0, 100), Vector2(0, 0), Vector2(10, 10), Vector2(10, 90)]), PackedFloat32Array([1.0, 1.0, 0.5, 0.5])]
	var parts: Array = Edge.split_at(side_q, 40.0)
	check(parts.size() == 2 and parts[0][0][1] == Vector2(0, 40) and parts[0][0][2] == Vector2(10, 40) and parts[1][0][0] == Vector2(0, 40) and parts[1][0][3] == Vector2(10, 40), "옆 변 사다리꼴을 y 40 에서 둘로 %s" % [parts])
	check(parts[0][1] == PackedFloat32Array([1.0, 1.0, 0.5, 0.5]) and parts[1][1] == PackedFloat32Array([1.0, 1.0, 0.5, 0.5]), "나눈 자리 꼭짓점 알파 = 그 변의 값")
	check(Edge.split_at(side_q, 5.0).size() == 1 and Edge.split_at(side_q, 200.0).size() == 1, "안쪽 변이 안 지나거나 밖이면 그대로")
	var top_q := [PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(90, 10), Vector2(10, 10)]), PackedFloat32Array([1.0, 1.0, 0.5, 0.5])]
	check(Edge.split_at(top_q, 5.0).size() == 1, "윗·아랫변 사다리꼴은 안 나눔")


# 3인칭 구석 자리 (내 % · 아래 묶음) 는 한 곳에서: hud.gd 가 숫자 대신 hud_extra.gd STACK 을 읽음
func test_c8_stack_one_source() -> void:
	var src := FileAccess.get_file_as_string("res://ui/hud.gd")
	# (hud.gd 엔 사냥꾼 히트마커가 조준점에서 띄우는 Vector2(22, 22) 가 따로 있음 — 구석 자리와 상관없는 값이라 내 % 자리 줄만 봄)
	check(src != "" and not src.contains("Vector2(22, vp.y") and not src.contains("damage_label.size.y - 18"), "hud.gd 에 구석 자리 숫자 (Vector2(22, vp.y - … - 18)) 가 남아 있음")
	var at := src.find("damage_label.position = Vector2(")
	check(at >= 0 and src.find("damage_label.position = Vector2(", at + 1) < 0, "내 % 구석 자리를 정하는 줄은 하나")
	check(src.contains("HudExtra.STACK.corner_x") and src.contains("HudExtra.STACK.corner_bottom"), "hud.gd 가 STACK.corner_x·corner_bottom 을 읽음")
	var HudExtra := preload("res://ui/hud_extra.gd")
	check(float(HudExtra.STACK.corner_x) == 22.0 and float(HudExtra.STACK.corner_bottom) == 18.0, "값은 예전 그대로 (22·18)")


# ---- c10 관전 따라가기 카메라 (world/spec_cam.gd · cam_rig.gd) + 가까운 떨어지는 칸 옅게 (pieces_view.gd) ----
const SpecCam := preload("res://world/spec_cam.gd")
const CamM := preload("res://world/cam_math.gd")
const Co := preload("res://core/coords.gd")
const CellLod := preload("res://world/cell_lod.gd")
const PV := preload("res://world/pieces_view.gd")
const HM := preload("res://world/hunt_marks.gd")


# 관전 판 하나를 차림: 나 (id 1) 는 죽었고 id 2·3 이 살아 있음. 돌려주는 값으로 _spec_restore
func _spec_setup(pieces: Array) -> Array:
	var keep := [Store.state, Store._players_by_id, Store.my_id, View.spectate_target, PlayerInput.yaw, PlayerInput.pitch, View.mode, CellLod.test_cam]
	var me := {"id": 1, "slot": 0, "alive": false, "yaw": 0.0, "x": 1.0, "y": 1.0, "z": 0.0}
	var a := {"id": 2, "slot": 1, "alive": true, "yaw": 0.0, "x": 5.5, "y": 5.5, "z": 0.0}
	var b := {"id": 3, "slot": 2, "alive": true, "yaw": 0.0, "x": 5.5, "y": 8.5, "z": 0.0}
	Store.my_id = 1
	Store._players_by_id = {1: me, 2: a, 3: b}
	Store.state = {"phase": "playing", "round": {"n": 1}, "field": {"w": 12, "d": 12}, "players": [me, a, b], "pieces": pieces}
	View.spectate_target = 2
	PlayerInput.yaw = 0.0
	PlayerInput.pitch = 0.0
	return keep


func _spec_restore(keep: Array, rig) -> void:
	if rig != null:
		var cam: Camera3D = rig.cam
		rig.free()
		if is_instance_valid(cam) and cam.get_parent() == null:
			cam.free() # 러너 동안엔 _ready 가 안 불려 카메라가 rig 의 자식이 아님 (test_cam_hook_runs_during_selfie 와 같음)
	Store.state = keep[0]
	Store._players_by_id = keep[1]
	Store.my_id = keep[2]
	View.spectate_target = keep[3]
	PlayerInput.yaw = keep[4]
	PlayerInput.pitch = keep[5]
	View.mode = keep[6]
	CellLod.test_cam = keep[7]


const SPEC_SHOWN := {1: Vector3(1, 1, 0), 2: Vector3(5.5, 5.5, 0), 3: Vector3(5.5, 8.5, 0)}
const SPEC_BLOCK := [{"shape": "O", "cells": [[3, 5, 2]]}] # 대상 (id 2) 에서 카메라로 가는 시선 (yaw 0, 내려다봄 0.45) 위의 떨어지는 칸


func _no_grid(_x, _y, _z) -> bool:
	return false


# 기본 시선: 마우스 pitch 0 이 0.45 rad 내려다봄, 바로 위는 안 넘음. 수치 표
func test_c10_spec_pitch() -> void:
	var S: Dictionary = SpecCam.SPEC
	check(absf(float(S.tilt) - 0.45) < 1e-9 and absf(float(S.look_up) - 1.4) < 1e-9 and absf(float(S.ease) - 4.0) < 1e-9, "tilt 0.45 · look_up 1.4 · ease 4 (%s)" % [S])
	check(S.fade == [1.2, 2.6] and absf(float(S.fade_alpha) - 0.2) < 1e-9, "옅게 [1.2, 2.6] m · 알파 0.2")
	check(absf(SpecCam.orbit_pitch(0.0) + 0.45) < 1e-9, "pitch 0 → -0.45 (%s)" % SpecCam.orbit_pitch(0.0))
	check(absf(SpecCam.orbit_pitch(0.3) + 0.15) < 1e-9 and absf(SpecCam.orbit_pitch(-0.5) + 0.95) < 1e-9, "마우스 조작은 그대로 (pitch - tilt)")
	check(absf(SpecCam.orbit_pitch(-1.4) - (-PI / 2 + 0.05)) < 1e-9 and absf(SpecCam.orbit_pitch(-9.0) - (-PI / 2 + 0.05)) < 1e-9, "바로 위 (-90도 + 0.05) 에서 멈춤")
	# 트리 안 rig: 바라볼 점 = 대상 발 + 1.4, 카메라는 그 점에서 0.45 rad 위·SPECTATE_DIST 뒤
	var keep := _spec_setup([])
	var rig = CamRig.new()
	root().add_child(rig)
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	var e: Dictionary = CamM.orbit_eye({"x": 5.5, "y": 5.5, "z": 1.4}, 0.0, -0.45, C.SPECTATE_DIST)
	check(absf(rig.eye.x - e.x) < 1e-6 and absf(rig.eye.y - e.y) < 1e-6 and absf(rig.eye.z - e.z) < 1e-6, "관전 카메라 자리 %s (기대 %s)" % [rig.eye, e])
	check(rig.eye.z > 1.4 + 1.9 and rig.cam.position.distance_to(Co.gxyz(e.x, e.y, e.z)) < 1e-4, "대상 머리 위에서 내려다봄 (z %.2f)" % rig.eye.z)
	var fwd: Vector3 = -rig.cam.transform.basis.z
	check(fwd.distance_to((Co.gxyz(5.5, 5.5, 1.4) - Co.gxyz(e.x, e.y, e.z)).normalized()) < 1e-4, "대상 발 + 1.4 m 를 바라봄")
	_spec_restore(keep, rig)


# 시선 위에 떨어지는 칸이 있으면 그 칸 앞 (margin) 으로 당김, 없으면 SPECTATE_DIST 그대로
func test_c10_spec_falling_cell_blocks() -> void:
	var cells: Dictionary = SpecCam.cells_of(SPEC_BLOCK + [{"shape": "I", "cells": [[1.0, 2.0, 7.0], [1, 2, 8]]}])
	check(cells.size() == 3 and cells.has(Vector3i(3, 5, 2)) and cells.has(Vector3i(1, 2, 7)) and cells.has(Vector3i(1, 2, 8)), "칸 모음 %s" % [cells])
	check(SpecCam.cells_of(null).is_empty() and SpecCam.cells_of([]).is_empty(), "조각이 없으면 빈 모음")
	var grid := func(_x, _y, z): return z < 0.0
	var hit: Callable = SpecCam.blocked(grid, cells)
	check(hit.call(3.5, 5.5, 2.5) and hit.call(3.01, 5.99, 2.01) and not hit.call(4.01, 5.5, 2.5) and not hit.call(3.5, 5.5, 3.01), "떨어지는 칸 안만 막힘")
	check(hit.call(9.0, 9.0, -0.5) and not hit.call(9.0, 9.0, 0.5), "격자도 그대로 막힘")
	var keep := _spec_setup([])
	var rig = CamRig.new()
	root().add_child(rig)
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	check(rig.spec_dist != null and absf(float(rig.spec_dist) - 4.5) < 1e-9 and absf(C.SPECTATE_DIST - 4.5) < 1e-9, "막는 것이 없으면 4.5 (%s)" % [rig.spec_dist])
	_spec_restore(keep, rig)
	keep = _spec_setup(SPEC_BLOCK)
	rig = CamRig.new()
	root().add_child(rig)
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	# 시선이 칸 [3,5,2] 에 들어가는 첫 걸음 = 1.7 m (x = 5.5 - cos(0.45) × t < 4) → 그 앞 margin 0.3
	check(rig.spec_dist != null and float(rig.spec_dist) < 4.5 and absf(float(rig.spec_dist) - (1.7 - C.SPECTATE_CAM_MARGIN)) < 1e-6, "떨어지는 칸 앞 margin 으로 당김 (%s, 기대 1.4)" % [rig.spec_dist])
	var e: Dictionary = CamM.orbit_eye({"x": 5.5, "y": 5.5, "z": 1.4}, 0.0, -0.45, float(rig.spec_dist))
	check(absf(rig.eye.x - e.x) < 1e-6 and absf(rig.eye.z - e.z) < 1e-6 and not cells.has(Vector3i(floori(rig.eye.x), floori(rig.eye.y), floori(rig.eye.z))), "카메라가 칸 앞 (칸 속이 아님) %s" % [rig.eye])
	_spec_restore(keep, rig)


# 거리: 막히면 한 프레임에 당기고, 풀리면 ease 로 천천히. 대상·판이 바뀌거나 따라가기를 그만두면 처음부터
func test_c10_spec_dist_eases() -> void:
	var keep := _spec_setup([])
	var rig = CamRig.new()
	root().add_child(rig)
	rig.spec.round = 1
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	check(absf(float(rig.spec_dist) - 4.5) < 1e-9, "처음 4.5")
	Store.state.pieces = SPEC_BLOCK
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	var near: float = float(rig.spec_dist)
	check(absf(near - 1.4) < 1e-6, "막히면 한 프레임에 당김 (%s)" % near)
	Store.state.pieces = []
	rig.place(0.1, SPEC_SHOWN, _no_grid)
	var want: float = near + (4.5 - near) * (1.0 - exp(-float(SpecCam.SPEC.ease) * 0.1))
	check(absf(float(rig.spec_dist) - want) < 1e-9 and float(rig.spec_dist) > near + 0.5 and float(rig.spec_dist) < 4.5 - 1.0, "풀리면 ease 4 로 천천히 (%s, 기대 %s)" % [rig.spec_dist, want])
	var prev: float = float(rig.spec_dist)
	for i in 40:
		rig.place(0.1, SPEC_SHOWN, _no_grid)
		check(float(rig.spec_dist) >= prev - 1e-9 and float(rig.spec_dist) <= 4.5 + 1e-9, "멀어지기만 하고 4.5 를 안 넘음")
		prev = float(rig.spec_dist)
	check(absf(prev - 4.5) < 1e-3, "4초 뒤엔 다시 4.5 (%s)" % prev)
	# 대상이 바뀌면 지난 거리를 잊음 (당겨진 채에서 새 대상은 바로 4.5)
	Store.state.pieces = SPEC_BLOCK
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	check(absf(float(rig.spec_dist) - 1.4) < 1e-6, "다시 당김")
	View.spectate_target = 3
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	check(absf(float(rig.spec_dist) - 4.5) < 1e-9, "대상이 바뀌면 처음부터 (%s)" % [rig.spec_dist])
	# 판이 바뀌어도
	View.spectate_target = 2
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	Store.state.pieces = []
	rig.spec.round = 2
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	check(absf(float(rig.spec_dist) - 4.5) < 1e-9, "판이 바뀌면 처음부터 (%s)" % [rig.spec_dist])
	# 전체 보기 (따라가는 대상 없음) 로 가면 잊음
	View.spectate_target = null
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	check(rig.spec_dist == null, "따라가기가 아니면 거리를 잊음")
	_spec_restore(keep, rig)


# 가까운 칸 알파: 1.2 m 안 = 0.2, 2.6 m 밖 = 1, 사이는 안 줄어듦
func test_c10_spec_cell_alpha() -> void:
	check(absf(SpecCam.cell_alpha(0.0) - 0.2) < 1e-9 and absf(SpecCam.cell_alpha(1.2) - 0.2) < 1e-9, "1.2 m 안 = 0.2")
	check(absf(SpecCam.cell_alpha(2.6) - 1.0) < 1e-9 and absf(SpecCam.cell_alpha(30.0) - 1.0) < 1e-9, "2.6 m 밖 = 1")
	check(absf(SpecCam.cell_alpha(1.9) - 0.6) < 1e-9, "가운데 = 0.6 (%s)" % SpecCam.cell_alpha(1.9))
	var prev := 0.0
	var d := 0.0
	while d <= 4.0:
		var a: float = SpecCam.cell_alpha(d)
		check(a >= prev - 1e-9 and a >= 0.2 - 1e-9 and a <= 1.0 + 1e-9, "d=%s 알파 %s (멀수록 안 옅어짐)" % [d, a])
		prev = a
		d += 0.05


# 관전일 때: 카메라에서 2.6 m 안의 떨어지는 칸만 옅은 묶음으로 (먼 칸부터), 불투명 묶음에서 빠짐. 옅은 칸이 있는 동안은 같은 스냅샷도 다시 씀
func test_c10_spec_fade_near_cells() -> void:
	var keep := _spec_setup([])
	var pv = PV.new()
	pv._ready()
	pv.mats = [StandardMaterial3D.new(), StandardMaterial3D.new()]
	var st := {"pieces": [
		{"shape": "T", "cells": [[2, 2, 2], [3, 2, 2], [4, 2, 2], [9, 2, 2]], "sky": false, "shadowVisible": true, "shadow": [[2, 2], [3, 2], [4, 2], [9, 2]], "landZ": 0, "eta": 500.0},
		{"shape": "I", "cells": [[2, 3, 2]], "sky": true}]}
	var at := Co.gxyz(2.5, 2.5, 3.5) # 칸 [2,2,2] 가운데에서 1 m 위
	CellLod.test_cam = {"pos": at, "fov": 75.0}
	View.mode = "spectate"
	pv.update(st, 1, {}, 0.0)
	# 거리: [2,2,2] 1.0 · [3,2,2] 1.414 · [2,3,2] 1.414 (하늘 블록) · [4,2,2] 2.236 · [9,2,2] 6.6 (멂)
	var dm: MultiMesh = pv.fade_mmi.multimesh
	check(pv.fade_n == 4 and dm.visible_instance_count == 4, "옅은 칸 4 (얻음 %d)" % pv.fade_n)
	check(pv.cells_mmi.multimesh.visible_instance_count == 1 and pv.sky_mmi.multimesh.visible_instance_count == 0, "나머지 1칸만 불투명 묶음, 가까운 하늘 블록도 옅은 쪽 (%d·%d)" % [pv.cells_mmi.multimesh.visible_instance_count, pv.sky_mmi.multimesh.visible_instance_count])
	# c10-fix F2: 옅은 칸은 반투명 재질의 사본 (그리는 순서만 뒤 — 착지 테·판 빛·발밑 고리가 칸 너머로 비침). 원본은 그대로 (하늘 블록·하늘 시점 칸이 같이 씀)
	var fmat: Material = pv.fade_mmi.material_override
	check(fmat != null and fmat != pv.mats[1] and fmat == pv.fade_mat and fmat is StandardMaterial3D and pv.fade_mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "반투명 재질의 사본 · 그림자 끔")
	check(int(SpecCam.SPEC.fade_order) == 9 and fmat.render_priority == 9 and (pv.mats[1] as Material).render_priority == 0, "옅은 칸 순서 9 (원본 0 그대로)")
	check(fmat.render_priority > 8 and fmat.render_priority < preload("res://world/world_config.gd").LABEL_PRIORITY - 1 and preload("res://world/world_config.gd").FOOT_RING.order < fmat.render_priority, "착지 테 1·판 빛 5·발밑 고리·표식 8 뒤, 이름표 앞")
	check(pv.sky_mmi.material_override == pv.mats[1] and pv.sky_far_mmi.material_override == pv.mats[1] and pv.cells_mmi.material_override == pv.mats[0], "하늘 블록·보통 칸 재질은 예전 그대로")
	var last := INF
	var seen_min := 1.0
	check(pv.faded.size() == 4, "옅은 칸 목록 4")
	for i in pv.faded.size(): # (헤드리스에서는 MultiMesh 에 쓴 값을 되읽을 수 없어 쓴 목록을 봄)
		var origin: Vector3 = (pv.faded[i][1] as Transform3D).origin
		var dist: float = at.distance_to(origin)
		var a: float = (pv.faded[i][2] as Color).a
		check(dist <= last + 1e-6 and absf(dist - float(pv.faded[i][0])) < 1e-5 and dist < 2.6, "먼 칸부터 (%d번 %.2f m)" % [i, dist])
		last = dist
		seen_min = minf(seen_min, a)
		var base: float = C.SKY_PIECE_OPACITY if origin.distance_to(Co.gxyz(2.5, 3.5, 2.5)) < 1e-4 else 1.0
		check(absf(a - base * SpecCam.cell_alpha(dist)) < 1e-4, "%d번 칸 알파 %.3f (거리 %.2f)" % [i, a, dist])
	check(absf(last - 1.0) < 1e-5 and absf(seen_min - 0.2) < 1e-4, "가장 가까운 칸 (1 m) = 0.2 (%s)" % seen_min)
	# c10-fix F8: 같은 스냅샷이고 옅게 그릴 칸 모음이 그대로면 (카메라가 조금 움직임) 옅은 칸의 알파·순서만 다시 — 다른 묶음·그림자·착지 테는 안 씀
	var w0: int = pv.writes
	var r0: int = pv.refades
	var at2 := at + Vector3(0, 0.2, 0) # 0.2 m 위로: [2,2,2] 1.2 · [3,2,2]·[2,3,2] 1.562 · [4,2,2] 2.332 (모두 2.6 안 그대로)
	CellLod.test_cam = {"pos": at2, "fov": 75.0}
	pv.update(st, 1, {}, 0.0)
	check(pv.writes == w0 and pv.refades == r0 + 1 and pv.fade_n == 4 and dm.visible_instance_count == 4, "같은 칸 모음: 다 다시 안 쓰고 옅은 칸만 (writes %d → %d, refades %d)" % [w0, pv.writes, pv.refades - r0])
	var last2 := INF
	for i in pv.faded.size():
		var origin: Vector3 = (pv.faded[i][1] as Transform3D).origin
		var dist: float = at2.distance_to(origin)
		var base: float = C.SKY_PIECE_OPACITY if origin.distance_to(Co.gxyz(2.5, 3.5, 2.5)) < 1e-4 else 1.0
		check(dist <= last2 + 1e-6 and absf(dist - float(pv.faded[i][0])) < 1e-5 and absf((pv.faded[i][2] as Color).a - base * SpecCam.cell_alpha(dist)) < 1e-4, "알파만 다시: %d번 칸 %.3f (거리 %.2f)" % [i, (pv.faded[i][2] as Color).a, dist])
		last2 = dist
	check(pv.cells_mmi.multimesh.visible_instance_count == 1, "다른 묶음은 그대로")
	pv.update(st, 1, {}, 0.0)
	check(pv.writes == w0 and pv.refades == r0 + 2, "가만히 있어도 옅은 칸만")
	check(PV.near_ids(st.pieces, at, 2.6) == PackedInt32Array([0, 1, 2, 4]) and PV.near_ids(st.pieces, at2, 2.6) == PackedInt32Array([0, 1, 2, 4]) and PV.near_ids(st.pieces, at + Vector3(0, 1.0, 0), 2.6) == PackedInt32Array([0, 1, 4]) and PV.near_ids([], at, 2.6).is_empty(), "가까운 칸 번호 (조각·칸 순서)")
	CellLod.test_cam = {"pos": at, "fov": 75.0}
	pv.update(st, 1, {}, 0.0)
	# 옅게 그릴 칸 모음이 바뀌면 (어떤 칸이 2.6 m 경계를 넘음) 같은 스냅샷이어도 칸 묶음을 다시 나눔 — 그림자 칸·착지 테는 그대로 (writes 는 안 늘고 cell_writes 가 늚)
	var w: int = pv.writes + pv.cell_writes
	var full: int = pv.writes
	var rims: int = pv.rim_mmi.multimesh.visible_instance_count
	CellLod.test_cam = {"pos": at + Vector3(0, 1.0, 0), "fov": 75.0}
	pv.update(st, 1, {}, 0.0)
	check(pv.writes + pv.cell_writes == w + 1 and pv.writes == full and pv.fade_n == 3, "카메라가 1 m 물러남: 칸 묶음만 다시 나누고 옅은 칸 3 (%d)" % pv.fade_n)
	check(pv.cells_mmi.multimesh.visible_instance_count == 2, "옅은 칸에서 빠진 칸은 보통 묶음으로")
	check(pv.shadow_mmi.multimesh.visible_instance_count == 4 and pv.rim_mmi.multimesh.visible_instance_count == rims and rims > 0, "그림자 칸 4·착지 테 %d 는 그대로" % rims)
	check(absf((pv.faded[2][2] as Color).a - SpecCam.cell_alpha(2.0)) < 1e-4 and (pv.faded[2][2] as Color).a > 0.2 + 0.3, "가장 가까운 칸 (2 m) 은 덜 옅음")
	# 카메라가 멀어지면 한 번 더 써서 되돌리고, 그 뒤엔 예전처럼 건너뜀
	CellLod.test_cam = {"pos": at + Vector3(0, 30, 0), "fov": 75.0}
	pv.update(st, 1, {}, 0.0)
	check(pv.writes + pv.cell_writes == w + 2 and pv.writes == full and pv.fade_n == 0 and dm.visible_instance_count == 0, "멀어지면 옅은 칸 0")
	check(pv.cells_mmi.multimesh.visible_instance_count + pv.far_mmi.multimesh.visible_instance_count == 4 and pv.sky_mmi.multimesh.visible_instance_count + pv.sky_far_mmi.multimesh.visible_instance_count == 1, "칸이 제 묶음으로 돌아옴")
	pv.update(st, 1, {}, 0.0)
	check(pv.writes + pv.cell_writes == w + 2, "가까운 칸이 없으면 같은 스냅샷은 건너뜀 (W15)")
	# 관전이 끝나면 (1·3인칭) 옅은 칸을 한 번 다시 써서 되돌림
	CellLod.test_cam = {"pos": at, "fov": 75.0}
	pv.update(st, 1, {}, 0.0)
	check(pv.fade_n == 4, "다시 가까이: 옅은 칸 4")
	View.mode = "third"
	pv.update(st, 1, {}, 0.0)
	check(pv.fade_n == 0 and dm.visible_instance_count == 0 and pv.cells_mmi.multimesh.visible_instance_count + pv.far_mmi.multimesh.visible_instance_count == 4, "관전이 끝나면 칸이 제 묶음으로")
	View.mode = "spectate"
	check(PV.near_any(st.pieces, at, 2.6) and not PV.near_any(st.pieces, at + Vector3(0, 30, 0), 2.6) and not PV.near_any([], at, 2.6), "가까운 칸 있나")
	pv.free()
	_spec_restore(keep, null)


# c10-fix F2: 옅은 칸 재질 사본은 원본 (G3 가 제자리에서 바꾸는 반투명 재질) 의 셰이더·값을 옅게 그리기 시작할 때 다시 베낌, 재질이 바뀌면 (테마) 새로 뜸
func test_c10_fix_fade_material_follows() -> void:
	var G3 = load("res://shaders/g3.gd")
	var keep := _spec_setup([])
	var pv = PV.new()
	pv._ready()
	var a: ShaderMaterial = G3.piece_material("meadow", false, {"rim": 0.4, "transparent": true, "opacity": 1.0})
	pv.mats = [G3.piece_material("meadow", false, {"rim": 0.4}), a]
	var st := {"pieces": [{"shape": "T", "cells": [[2, 2, 2]], "sky": false}]}
	var at := Co.gxyz(2.5, 2.5, 3.5)
	CellLod.test_cam = {"pos": at, "fov": 75.0}
	View.mode = "spectate"
	pv.update(st, 1, {}, 0.0)
	var f := pv.fade_mmi.material_override as ShaderMaterial
	check(f != null and f != a and f.shader == a.shader and f.render_priority == int(SpecCam.SPEC.fade_order) and a.render_priority == 0, "사본: 같은 셰이더 (새 셰이더 없음 — 미리 데우기 표 그대로) · 순서만 뒤")
	check(FileAccess.get_file_as_string("res://shaders/piece_alpha.gdshader").contains("render_mode depth_draw_always;"), "칸 셰이더는 그대로 깊이를 씀 (옅은 칸끼리·칸 면끼리 앞뒤가 맞음)")
	for u in a.shader.get_shader_uniform_list():
		check(f.get_shader_parameter(u.name) == a.get_shader_parameter(u.name), "사본 값 %s 같음" % u.name)
	# 원본이 제자리에서 바뀜 (그래픽 낮춤·판 빛 테두리): 다음에 옅게 그리기 시작할 때 따라감
	a.set_shader_parameter("rim", 0.0)
	a.set_shader_parameter("crack", 0.0)
	CellLod.test_cam = {"pos": at + Vector3(0, 30, 0), "fov": 75.0}
	pv.update(st, 1, {}, 0.0)
	check(pv.fade_n == 0, "멀어짐: 옅은 칸 0")
	CellLod.test_cam = {"pos": at, "fov": 75.0}
	pv.update(st, 1, {}, 0.0)
	check(pv.fade_n == 1 and pv.fade_mmi.material_override == f and float(f.get_shader_parameter("rim")) == 0.0 and float(f.get_shader_parameter("crack")) == 0.0 and f.render_priority == int(SpecCam.SPEC.fade_order), "다시 옅게: 같은 사본이 원본 값을 따라감 (순서는 그대로)")
	# 재질이 바뀌면 (테마 적용 set_look) 사본도 새로
	var b: ShaderMaterial = G3.piece_material("desert", false, {"transparent": true, "opacity": 1.0})
	pv.mats = [pv.mats[0], b]
	pv.update(st.duplicate(true), 1, {}, 0.0)
	var f2 := pv.fade_mmi.material_override as ShaderMaterial
	check(f2 != f and f2 != b and f2.get_shader_parameter("face_tex") == b.get_shader_parameter("face_tex") and f2.render_priority == int(SpecCam.SPEC.fade_order), "새 재질의 사본")
	pv.free()
	_spec_restore(keep, null)


class FakeBody:
	extends RefCounted
	var k := 1.0
	var calls := 0

	func set_see_thru(v: float) -> void:
		k = v
		calls += 1


class FakeBodies:
	extends RefCounted
	var nodes := {}


# c10-fix F1 순수 계산: 선분·상자, 시선을 막는 몸 (눈 → 바라볼 점·눈 → 대상 발), 문턱 여유
func test_c10_fix_spec_sight_blockers() -> void:
	var S: Dictionary = SpecCam.SPEC
	check(absf(float(S.thin_keep) - 0.32) < 1e-9 and float(S.thin_keep) >= 0.25 and float(S.thin_keep) <= 0.4, "남길 비율 0.32 (25~40%% — 다 지우지 않음)")
	check(S.thin_pad == [0.12, 0.28] and float(S.thin_pad[0]) < float(S.thin_pad[1]) and int(S.thin_hold_ms) == 120 and absf(float(S.thin_ease_s) - 0.12) < 1e-9, "문턱 [0.12, 0.28] m · 붙듦 120 ms · 0.12 초에 걸쳐")
	var lo := Vector3(1, 1, 0)
	var hi := Vector3(2, 2, 2)
	check(SpecCam.seg_hits_box(Vector3(0, 1.5, 1), Vector3(3, 1.5, 1), lo, hi), "가로지름")
	check(SpecCam.seg_hits_box(Vector3(1.5, 1.5, 1), Vector3(9, 9, 9), lo, hi) and SpecCam.seg_hits_box(Vector3(9, 9, 9), Vector3(1.5, 1.5, 1), lo, hi), "끝점이 안")
	check(not SpecCam.seg_hits_box(Vector3(0, 1.5, 1), Vector3(0.9, 1.5, 1), lo, hi), "닿기 전에 끝남")
	check(not SpecCam.seg_hits_box(Vector3(0, 0, 1), Vector3(3, 0.9, 1), lo, hi) and not SpecCam.seg_hits_box(Vector3(0, 1.5, 2.1), Vector3(3, 1.5, 2.1), lo, hi), "옆·위로 비낌")
	check(SpecCam.seg_hits_box(Vector3(0, 1.5, 3), Vector3(3, 1.5, 0), lo, hi) and not SpecCam.seg_hits_box(Vector3(0, 1.5, 6), Vector3(3, 1.5, 3), lo, hi), "비스듬히")
	check(not SpecCam.seg_hits_box(Vector3(1.5, 0, 1), Vector3(1.5, 0.5, 1), lo, hi) and SpecCam.seg_hits_box(Vector3(1.5, 0, 1), Vector3(1.5, 1.0, 1), lo, hi), "축과 나란한 선분")
	# 관전 카메라 (대상 발 (5.5, 5.5, 0), yaw 0, 0.45 rad 내려다봄, 4.5 m): 눈 ≈ (1.45, 5.5, 3.36)
	var e: Dictionary = CamM.orbit_eye({"x": 5.5, "y": 5.5, "z": 1.4}, 0.0, -0.45, C.SPECTATE_DIST)
	var eye := Vector3(e.x, e.y, e.z)
	var ends := [Vector3(5.5, 5.5, 1.4), Vector3(5.5, 5.5, 0)]
	var H: float = C.PLAYER_HALF
	var T: float = C.PLAYER_HEIGHT
	var others := {
		3: Vector3(4.3, 5.5, 0), # 눈과 대상 사이 (눈 → 발 선분이 몸통을 지남)
		4: Vector3(5.5, 6.1, 0), # 대상 바로 옆 (0.6 m) — 화면 옆, 시선은 안 막음
		5: Vector3(6.3, 5.5, 0), # 대상 뒤
		6: Vector3(2.0, 5.5, 2.4), # 렌즈 바로 앞 (높은 곳에 선 몸 — 눈 → 바라볼 점 선분)
		7: Vector3(4.3, 7.5, 0), # 멀리 옆
		8: Vector3(4.3, 5.5, 4.0), # 시선 위 (하늘 계단 위)
	}
	var hit: Array = SpecCam.sight_blockers(eye, ends, others, float(S.thin_pad[0]), H, T)
	check(hit == [3, 6], "막는 몸 = 사이에 선 몸·렌즈 앞 몸만 (%s)" % [hit])
	check(SpecCam.sight_blockers(eye, ends, others, float(S.thin_pad[1]), H, T) == [3, 6], "넓은 문턱에서도 옆 (0.6 m)·뒤 사람은 아님")
	check(SpecCam.sight_blockers(eye, ends, {}, 0.12, H, T).is_empty() and SpecCam.sight_blockers(eye, [], others, 0.12, H, T).is_empty(), "사람·시선이 없으면 없음")
	# 문턱 여유: 시선에서 0.2 m 비낀 몸은 좁은 문턱 밖·넓은 문턱 안
	var side := {9: Vector3(4.3, 5.5 + H + 0.2, 0)}
	check(SpecCam.sight_blockers(eye, ends, side, float(S.thin_pad[0]), H, T).is_empty() and SpecCam.sight_blockers(eye, ends, side, float(S.thin_pad[1]), H, T) == [9], "0.2 m 비낀 몸: 좁은 문턱 밖 · 넓은 문턱 안")
	# 대상 이름표: 화면에서 겹치면 가까운 것이 이기던 규칙 (Labels.thin) 에서 관전 따라가기 대상이 맨 먼저 — 바로 옆 사람이 카메라에 더 가까우면 대상 이름표가 사라졌음
	const Labels := preload("res://world/labels.gd")
	check(Labels.thin_dist(3.2, false) == 3.2 and Labels.thin_dist(3.2, true) == -1.0 and Labels.thin_dist(0.0, false) > Labels.thin_dist(0.0, true), "겹침 고르기 거리: 대상은 −1 (누구보다 먼저)")
	var gap := Vector2(60, 30)
	var near_other := {"px": Vector2(100, 100), "dist": 2.0, "gap": gap}
	var far_target := {"px": Vector2(110, 105), "dist": 5.0, "gap": gap}
	check(Labels.thin([near_other, far_target]) == [true, false], "예전 규칙: 가까운 남의 이름표가 이김")
	far_target["dist"] = Labels.thin_dist(5.0, true)
	check(Labels.thin([near_other, far_target]) == [false, true], "대상 이름표가 이김 (겹친 남의 이름표가 숨음)")
	check(Labels.thin([{"px": Vector2(400, 100), "dist": 2.0, "gap": gap}, far_target]) == [true, true], "안 겹치면 둘 다")
	var bsrc := FileAccess.get_file_as_string("res://world/bodies.gd")
	check(bsrc.contains("var follow = View.spectate_target if str(View.mode) == \"spectate\" else null") and bsrc.contains("Labels.thin_dist(dists[i], l == first)"), "bodies.gd: 관전 따라가기일 때만 대상 이름표 먼저")


# c10-fix F1 순수 계산: 옅어지고 (thin_ease_s) · 문턱 사이에선 그대로 · 벗어나도 thin_hold_ms 는 옅은 채 · 그 뒤 되돌아와 빠짐 (깜빡이지 않음)
func test_c10_fix_spec_thin_step() -> void:
	var S: Dictionary = SpecCam.SPEC
	var keep_k := float(S.thin_keep)
	var st := {}
	var t := 1000.0
	st = SpecCam.thin_step(st, [3], [3], t, 0.03)
	check(st.has(3) and float(st[3].k) < 1.0 and float(st[3].k) > keep_k and float(st[3].at) == t, "막기 시작: 조금 옅어짐 (%s)" % [st])
	var last := float(st[3].k)
	for i in 6:
		t += 30.0
		st = SpecCam.thin_step(st, [3], [3], t, 0.03)
		check(float(st[3].k) <= last + 1e-9 and float(st[3].k) >= keep_k - 1e-9, "단조로 옅어짐 (%.3f)" % float(st[3].k))
		last = float(st[3].k)
	check(absf(last - keep_k) < 1e-9, "0.12 초 뒤 남길 비율 %.2f (얻음 %.3f)" % [keep_k, last])
	# 좁은 문턱은 벗어났지만 넓은 문턱 안: 계속 막는 것으로 (at 이 새로 찍힘). 처음부터 넓은 문턱에만 있던 몸은 안 옅어짐
	t += 30.0
	st = SpecCam.thin_step(st, [], [3, 4], t, 0.03)
	check(absf(float(st[3].k) - keep_k) < 1e-9 and float(st[3].at) == t and not st.has(4), "문턱 사이: 옅은 몸은 그대로, 새 몸은 안 옅어짐")
	# 좁은 문턱에 드나들어도 (한 프레임씩 번갈아) 값이 안 흔들림
	for i in 6:
		t += 16.0
		st = SpecCam.thin_step(st, [3] if i % 2 == 0 else [], [3] if i % 2 == 0 else [], t, 0.016)
		check(absf(float(st[3].k) - keep_k) < 1e-9, "한 프레임씩 드나듦: 옅은 채 (%d)" % i)
	# 완전히 벗어남: thin_hold_ms 동안은 옅은 채, 그 뒤 thin_ease_s 에 걸쳐 되돌아오고 빠짐
	var left := t
	t += 16.0
	st = SpecCam.thin_step(st, [], [], t, 0.016)
	var free_at := float(st[3].at)
	check(free_at <= left and absf(float(st[3].k) - keep_k) < 1e-9, "벗어난 직후: 옅은 채")
	t = free_at + float(S.thin_hold_ms) - 1.0
	st = SpecCam.thin_step(st, [], [], t, 0.016)
	check(absf(float(st[3].k) - keep_k) < 1e-9, "붙드는 동안: 옅은 채")
	t = free_at + float(S.thin_hold_ms) + 1.0
	st = SpecCam.thin_step(st, [], [], t, 0.03)
	check(float(st[3].k) > keep_k and float(st[3].k) < 1.0, "붙듦이 끝남: 되돌아오기 시작 (%.3f)" % float(st[3].k))
	var steps := 0
	while st.has(3) and steps < 20:
		t += 30.0
		st = SpecCam.thin_step(st, [], [], t, 0.03)
		steps += 1
	check(st.is_empty() and steps <= 5, "0.12 초 안에 다 되돌아와 빠짐 (%d걸음)" % steps)
	# 되돌아오는 중에 다시 막으면 그 값에서 다시 옅어짐
	st = SpecCam.thin_step({3: {"k": 0.8, "at": 0.0}}, [3], [3], 5000.0, 0.03)
	check(float(st[3].k) < 0.8 and float(st[3].at) == 5000.0, "다시 막음")
	check(SpecCam.thin_step({}, [], [5], 0.0, 0.03).is_empty(), "아무도 안 막음")


# c10-fix F1 트리 안 rig: 관전 따라가기에서만, 시선을 막는 몸만 옅게 (대상·옆 사람·죽은 사람은 그대로). 1·3인칭·전체 보기·승자 클로즈업으로 바뀌면 바로 되돌림
func test_c10_fix_spec_thin_rig() -> void:
	var keep := _spec_setup([])
	var keep_v := [View.victory_stage, View.victory_id]
	var blocker := {"id": 4, "slot": 3, "alive": true, "yaw": 0.0, "x": 4.3, "y": 5.5, "z": 0.0}
	var dead := {"id": 5, "slot": 4, "alive": false, "yaw": 0.0, "x": 3.6, "y": 5.5, "z": 0.0}
	Store._players_by_id[4] = blocker
	Store._players_by_id[5] = dead
	Store.state.players.append(blocker)
	Store.state.players.append(dead)
	var shown := SPEC_SHOWN.duplicate()
	shown[4] = Vector3(4.3, 5.5, 0)
	shown[5] = Vector3(3.6, 5.5, 0)
	var fb := FakeBodies.new()
	for id in [1, 2, 3, 4, 5]:
		fb.nodes[id] = {"body": FakeBody.new()}
	var rig = CamRig.new()
	root().add_child(rig)
	rig.bodies = fb
	var keep_k := float(SpecCam.SPEC.thin_keep)
	rig.place(0.03, shown, _no_grid)
	check(rig.thin.has(4) and rig.thin.size() == 1 and fb.nodes[4].body.k < 1.0 and fb.nodes[4].body.k > keep_k, "막는 몸 (id 4) 만 옅어지기 시작 (%s)" % [rig.thin])
	for i in 5:
		rig.place(0.03, shown, _no_grid)
	check(absf(fb.nodes[4].body.k - keep_k) < 1e-9, "0.12 초 뒤 남길 비율 %.2f (얻음 %.3f)" % [keep_k, fb.nodes[4].body.k])
	check(fb.nodes[2].body.calls == 0 and fb.nodes[3].body.calls == 0 and fb.nodes[1].body.calls == 0 and fb.nodes[5].body.calls == 0, "대상 (2)·옆 사람 (3)·죽은 사람 (1·5) 은 안 건드림")
	# 카메라 자리는 예전 그대로 (몸에는 안 당김)
	var e: Dictionary = CamM.orbit_eye({"x": 5.5, "y": 5.5, "z": 1.4}, 0.0, -0.45, C.SPECTATE_DIST)
	check(absf(rig.eye.x - e.x) < 1e-6 and absf(rig.eye.z - e.z) < 1e-6 and absf(float(rig.spec_dist) - C.SPECTATE_DIST) < 1e-9, "카메라 자리·거리는 그대로")
	# 같은 id 의 몸이 바뀌면 (몸을 새로 만듦) 새 몸을 옅게 하고 앞 몸은 되돌림
	var old_body = fb.nodes[4].body
	fb.nodes[4] = {"body": FakeBody.new()}
	rig.place(0.03, shown, _no_grid)
	check(old_body.k == 1.0 and absf(fb.nodes[4].body.k - keep_k) < 1e-9, "몸이 바뀜: 새 몸 옅게 · 앞 몸 되돌림")
	# 승자 클로즈업이 시작되면 바로 되돌림
	View.victory_stage = "closeup"
	View.victory_id = 2
	rig.place(0.03, shown, _no_grid)
	check(fb.nodes[4].body.k == 1.0 and rig.thin.is_empty(), "승자 클로즈업: 되돌림")
	View.victory_stage = keep_v[0]
	View.victory_id = keep_v[1]
	for i in 6:
		rig.place(0.03, shown, _no_grid)
	check(absf(fb.nodes[4].body.k - keep_k) < 1e-9, "다시 관전: 옅게")
	# 전체 보기 (대상 없음)
	View.spectate_target = null
	rig.place(0.03, shown, _no_grid)
	check(fb.nodes[4].body.k == 1.0 and rig.thin.is_empty() and rig._thin_bodies.is_empty(), "전체 보기: 바로 되돌림")
	View.spectate_target = 2
	for i in 6:
		rig.place(0.03, shown, _no_grid)
	check(absf(fb.nodes[4].body.k - keep_k) < 1e-9, "다시 관전: 옅게 (2)")
	# 1·3인칭 (내가 살아 있음): 바로 되돌리고 그 뒤로는 안 건드림
	Store._players_by_id[1].alive = true
	for mode in ["third", "first"]:
		rig.force = mode
		rig.place(0.03, shown, _no_grid)
		check(fb.nodes[4].body.k == 1.0 and rig.thin.is_empty(), "%s: 남의 몸 그대로" % mode)
		var calls: int = fb.nodes[4].body.calls
		rig.place(0.03, shown, _no_grid)
		check(fb.nodes[4].body.calls == calls and fb.nodes[3].body.calls == 0, "%s: 그 뒤로는 안 건드림" % mode)
		Store._players_by_id[1].alive = false
		rig.force = ""
		for i in 6:
			rig.place(0.03, shown, _no_grid)
		check(absf(fb.nodes[4].body.k - keep_k) < 1e-9, "%s 뒤 다시 관전: 옅게" % mode)
		Store._players_by_id[1].alive = true
	Store._players_by_id[1].alive = false
	rig.force = ""
	# 막던 몸이 비켜남: 붙드는 동안은 옅은 채 (깜빡임 막기), 몸 묶음이 없으면 (테스트·상자 몸) 아무것도 안 함
	rig.place(0.03, shown, _no_grid)
	shown[4] = Vector3(4.3, 8.0, 0)
	rig.place(0.03, shown, _no_grid)
	check(rig.thin.has(4) and fb.nodes[4].body.k < 1.0, "비켜난 직후: 아직 옅음")
	rig.thin[4].at -= float(SpecCam.SPEC.thin_hold_ms) + 1.0 # 붙드는 시간이 지난 것으로
	for i in 6:
		rig.place(0.03, shown, _no_grid)
	check(fb.nodes[4].body.k == 1.0 and rig.thin.is_empty() and rig._thin_bodies.is_empty(), "붙듦이 끝나면 되돌아옴")
	rig.bodies = null
	shown[4] = Vector3(4.3, 5.5, 0)
	rig.place(0.03, shown, _no_grid)
	check(rig.thin.has(4) and rig._thin_bodies.is_empty(), "몸 묶음이 없으면 계산만")
	View.victory_stage = keep_v[0]
	View.victory_id = keep_v[1]
	_spec_restore(keep, rig)


# 관전이 아니면 그대로: 1·3인칭 카메라 자리는 예전 식 (떨어지는 칸에 안 당김), 옅은 칸 묶음은 늘 비어 있음
func test_c10_spec_only_spectate() -> void:
	var keep := _spec_setup(SPEC_BLOCK + [{"shape": "O", "cells": [[2, 1, 2], [3, 1, 2], [2, 0, 2], [1, 1, 2]]}]) # 3인칭 카메라 길 위에도 떨어지는 칸
	Store._players_by_id[1].alive = true
	var shown := SPEC_SHOWN.duplicate()
	shown[1] = Vector3(5.5, 1.5, 0)
	var s: Vector3 = shown[1]
	for pitch in [0.0, -0.4]:
		PlayerInput.pitch = pitch
		var rig = CamRig.new()
		root().add_child(rig)
		rig.force = "third"
		rig.place(0.016, shown, _no_grid)
		# 예전 식 (cam_rig.gd 3인칭 갈래 그대로)
		var pivot := {"x": s.x + sin(0.0) * C.TP_SIDE, "y": s.y - cos(0.0) * C.TP_SIDE, "z": s.z + C.TP_PIVOT_UP}
		var orbit := maxf(-PI / 2 + 0.05, pitch - C.TP_TILT)
		var e: Dictionary = CamM.orbit_eye(pivot, 0.0, orbit, C.TP_DIST)
		check(absf(rig.eye.x - e.x) < 1e-9 and absf(rig.eye.y - e.y) < 1e-9 and absf(rig.eye.z - maxf(s.z + C.TP_MIN_Z, e.z)) < 1e-9, "3인칭 카메라 자리 %s (예전 식 %s)" % [rig.eye, e])
		check(absf(float(rig.tp_dist) - C.TP_DIST) < 1e-9 and rig.spec_dist == null, "3인칭 거리 그대로 (떨어지는 칸에 안 당김), 관전 거리 없음")
		var to3 := Co.gxyz(pivot.x + cos(pitch) * C.TP_LOOK_AHEAD, pivot.y, pivot.z + sin(pitch) * C.TP_LOOK_AHEAD)
		check((-rig.cam.transform.basis.z).distance_to((to3 - rig.cam.position).normalized()) < 1e-4, "3인칭 바라보는 쪽")
		rig.force = "first"
		rig.place(0.016, shown, _no_grid)
		check(absf(rig.eye.x - s.x) < 1e-9 and absf(rig.eye.y - s.y) < 1e-9 and absf(rig.eye.z - (s.z + C.EYE_HEIGHT)) < 1e-9 and rig.spec_dist == null, "1인칭 카메라 = 눈높이 %s" % [rig.eye])
		check((-rig.cam.transform.basis.z).distance_to(Co.dir(0.0, pitch)) < 1e-4, "1인칭 바라보는 쪽")
		var cam: Camera3D = rig.cam
		rig.free()
		if is_instance_valid(cam) and cam.get_parent() == null:
			cam.free()
	# 떨어지는 칸: 관전이 아니면 카메라가 칸 바로 옆이어도 옅은 묶음 0, 같은 스냅샷은 건너뜀
	var pv = PV.new()
	pv._ready()
	pv.mats = [StandardMaterial3D.new(), StandardMaterial3D.new()]
	var st := {"pieces": [{"shape": "T", "cells": [[2, 2, 2], [3, 2, 2]], "sky": false}, {"shape": "I", "cells": [[2, 3, 2]], "sky": true}]}
	CellLod.test_cam = {"pos": Co.gxyz(2.5, 2.5, 3.5), "fov": 75.0}
	for mode in ["first", "third", "sky"]:
		View.mode = mode
		var st2 := st.duplicate(true)
		pv.update(st2, 1, {}, 1.0 if mode == "sky" else 0.0)
		var w: int = pv.writes
		check(pv.fade_n == 0 and pv.fade_mmi.multimesh.visible_instance_count == 0, "%s: 옅은 칸 0 (얻음 %d)" % [mode, pv.fade_n])
		check(pv.cells_mmi.multimesh.visible_instance_count == 2 and pv.sky_mmi.multimesh.visible_instance_count == 1, "%s: 칸은 제 묶음" % mode)
		pv.update(st2, 1, {}, 1.0 if mode == "sky" else 0.0)
		check(pv.writes == w, "%s: 같은 스냅샷은 건너뜀" % mode)
	# 재질 [불투명, 반투명] 이 없으면 (G3 없음) 관전이어도 안 함
	pv.mats = null
	View.mode = "spectate"
	pv.update(st.duplicate(true), 1, {}, 0.0)
	check(pv.fade_n == 0 and pv.cells_mmi.multimesh.visible_instance_count == 2, "재질 없으면 그대로")
	pv.free()
	_spec_restore(keep, null)


# 맞음·경직 테 옆변: 가로 두께가 side 배 (0.55), 윗·아랫변 두께·알파는 그대로, 모서리 꺾임선 (축척 대각선) 에 계단 없음
func test_c10_edge_side_thin() -> void:
	var E: Dictionary = Edge.EDGE
	var side: float = float(E.side)
	check(absf(side - 0.55) < 1e-9 and side >= 0.5 and side <= 0.65, "옆변 배율 0.55 (%s)" % side)
	var kn: Array = E.knee
	for size in [Vector2(1280, 720), Vector2(960, 540)]:
		var b: Vector2 = Edge.band_px(size)
		var mid: Vector2 = size / 2.0
		var a := 0.8
		var thick: float = (float(E.outer) + float(E.inner)) * size.y # 윗·아랫변 띠 두께 (예전 값)
		check(absf(b.x + b.y - thick) < 1e-3, "%s 띠 두께 합 %s" % [size, thick])
		# 옆변: 바깥 띠 = a, 두께 × side 부터는 0 (예전 두께 자리는 이제 빈 곳)
		check(absf(Edge.alpha_at(size, Vector2(1, mid.y), a) - a) < 1e-6 and absf(Edge.alpha_at(size, Vector2(size.x - 1, mid.y), a) - a) < 1e-6, "%s (1, mid.y) = a" % size)
		for x in [thick * side, thick * side + 1.0, thick * 0.8, thick, mid.x]: # (띠 끝 자리는 부동소수 오차만큼만 남음)
			check(Edge.alpha_at(size, Vector2(x, mid.y), a) < 1e-5 and Edge.alpha_at(size, Vector2(size.x - x, mid.y), a) < 1e-5, "%s 옆변 x=%.1f 은 0" % [size, x])
		check(Edge.alpha_at(size, Vector2(thick * side + 0.01, mid.y), a) == 0.0 and Edge.alpha_at(size, Vector2(size.x - thick * side - 0.01, mid.y), a) == 0.0, "%s 옆변 띠 끝 밖은 딱 0" % size)
		check(Edge.alpha_at(size, Vector2(thick * side - 1.0, mid.y), a) > 0.0 and Edge.alpha_at(size, Vector2(size.x - thick * side + 1.0, mid.y), a) > 0.0, "%s 옆변 띠 끝 바로 안은 아직 보임" % size)
		check(absf(Edge.alpha_at(size, Vector2(b.x * side - 0.01, mid.y), a) - a) < 1e-3 and Edge.alpha_at(size, Vector2(b.x * side + 1.0, mid.y), a) < a, "%s 옆변 바깥 띠 두께 = %.2f 화소" % [size, b.x * side])
		# 윗·아랫변 두께는 예전 값: 띠 끝 (thick) 바로 안은 보이고 그 밖은 0, 바깥 띠 두께 b.x
		check(Edge.alpha_at(size, Vector2(mid.x, size.y - thick + 1.0), a) > 0.0 and Edge.alpha_at(size, Vector2(mid.x, size.y - thick - 0.01), a) == 0.0, "%s 아랫변 두께 그대로" % size)
		check(Edge.alpha_at(size, Vector2(mid.x, thick - 1.0), a) > 0.0 and Edge.alpha_at(size, Vector2(mid.x, thick + 0.01), a) == 0.0, "%s 윗변 두께 그대로" % size)
		check(absf(Edge.alpha_at(size, Vector2(mid.x, size.y - b.x + 0.01), a) - a) < 1e-3 and absf(Edge.alpha_at(size, Vector2(mid.x, size.y - 1), a) - a) < 1e-6, "%s 아랫변 바깥 띠 그대로" % size)
		# 같은 깊이 (d) 면 옆변 (d × side) 과 아랫변 (d) 이 같은 알파
		for d in [0.0, 2.0, b.x, b.x + b.y * 0.2, b.x + b.y * float(kn[0]), b.x + b.y * 0.7, thick]:
			check(absf(Edge.alpha_at(size, Vector2(d * side, mid.y), a) - Edge.alpha_at(size, Vector2(mid.x, size.y - d), a)) < 1e-6, "%s d=%.1f 옆변·아랫변 같은 알파" % [size, d])
		# 모서리 꺾임선 (d × side, d) 근처 반 화소 뜀: 세로 걸음은 예전 한도, 가로 걸음은 ÷ side (네 구석 모두, 안팎 양쪽으로)
		var steep: float = maxf((1.0 - float(kn[1])) / (b.y * float(kn[0])), float(kn[1]) / (b.y * (1.0 - float(kn[0]))))
		var worst_v := 0.0
		var worst_h := 0.0
		var d2 := 1.0
		while d2 <= thick + 1.0:
			for cx in [d2 * side, size.x - d2 * side]:
				for cy in [d2, size.y - d2]:
					var on: float = Edge.alpha_at(size, Vector2(cx, cy), 1.0)
					for o in [-0.5, 0.5]:
						worst_h = maxf(worst_h, absf(on - Edge.alpha_at(size, Vector2(cx + o, cy), 1.0)))
						worst_v = maxf(worst_v, absf(on - Edge.alpha_at(size, Vector2(cx, cy + o), 1.0)))
			d2 += 0.5
		check(worst_v <= steep * 0.5 + 1e-6, "%s 꺾임선 세로 반 화소 뜀 %.4f (한도 %.4f)" % [size, worst_v, steep * 0.5])
		check(worst_h <= steep / side * 0.5 + 1e-6, "%s 꺾임선 가로 반 화소 뜀 %.4f (한도 %.4f)" % [size, worst_h, steep / side * 0.5])
		# 그리는 꼭짓점: 띠 사각형이 (d × side, d) 로 들어감, 삼각형 묶음 하나 (꼭짓점 72개) 그대로
		var st: Array = Edge.stops(size)
		for i in st.size():
			var r: Array = Edge._rect(size, float(st[i][0]))
			var dd: float = float(st[i][0])
			check(r[0].is_equal_approx(Vector2(dd * side, dd)) and r[2].is_equal_approx(Vector2(size.x - dd * side, size.y - dd)), "%s 띠 사각형 %d %s" % [size, i, r])
		var t: Array = Edge.tri_arrays(size)
		check(t[0].size() == 108 and t[1].size() == 72, "삼각형 36개·꼭짓점 72개 그대로")
		var max_in := 0.0
		for v in t[1]:
			max_in = maxf(max_in, minf(v.x, size.x - v.x))
		check(absf(max_in - thick * side) < 1e-3, "%s 꼭짓점이 옆에서 들어온 깊이 %.2f (= 두께 × side %.2f)" % [size, max_in, thick * side])


# 하늘 시점 (블록 마스터·블록 조종) 에서 남이 붙인 사냥꾼 표식 칸은 숨김, 그 밖은 예전 식 그대로
func test_c10_hunt_sky_hide() -> void:
	for n in [0, 1, 3]:
		for blink in [false, true]:
			for mine in [false, true]:
				for third in [false, true]:
					var old: bool = n > 0 and not blink and not (mine and not third)
					for by_me in [false, true]:
						check(HM.pips_shown(n, blink, mine, third, false, by_me) == old, "하늘 시점이 아니면 예전과 같음 (n %d · blink %s · mine %s · third %s)" % [n, blink, mine, third])
					check(not HM.pips_shown(n, blink, mine, third, true, false), "하늘 + 내가 붙인 것 아님 → 숨김")
					check(HM.pips_shown(n, blink, mine, third, true, true) == old, "하늘 + 내가 붙인 것 → 예전과 같음")
	check(HM.pips_shown(2, false, false, false, false, false) and not HM.pips_shown(2, false, false, false, true, false) and HM.pips_shown(2, false, false, false, true, true), "보기: 남의 표식 2칸")
	var src := FileAccess.get_file_as_string("res://world/body_fx.gd")
	check(src.contains("g.visible = HM.pips_shown(n, blink, mine, third.call(), str(View.mode) == \"sky\", by_me)"), "body_fx.gd 가 pips_shown 을 씀")


# ---- c11 관전 화면 마감: 유령 조준 상자가 대상을 안 덮게 (world/ghost_aim.gd · spec_cam.gd) + 안내 띠 접기 (ui/hud.gd) ----
const Hud := preload("res://ui/hud.gd")


# 조준 상자 면 알파 배율: 화면에서 대상 (몸 + 이름표) 사각형과 겹치면 ghost_fill_hit, 12px 안도 겹침, 떨어지면 1, 따라가기가 아니면 늘 1
func test_c11_spec_ghost_fill() -> void:
	var S: Dictionary = SpecCam.SPEC
	var hit := float(S.ghost_fill_hit)
	check(hit <= 0.3 and hit >= 0.0 and absf(float(S.ghost_pad) - 12.0) < 1e-9, "겹칠 때 면 알파 배율 %s (0.3 이하) · 여유 12px" % hit)
	var target := Rect2(600, 250, 70, 220) # 대상 몸 + 이름표
	check(SpecCam.ghost_fill(Rect2(630, 300, 70, 70), target, true) == hit, "겹침 → %s" % hit)
	check(SpecCam.ghost_fill(Rect2(610, 260, 20, 20), target, true) == hit and SpecCam.ghost_fill(Rect2(500, 100, 400, 500), target, true) == hit, "상자가 대상 안·대상이 상자 안도 겹침")
	check(SpecCam.ghost_fill(Rect2(681, 300, 70, 70), target, true) == hit and SpecCam.ghost_fill(Rect2(682, 300, 70, 70), target, true) == hit, "옆으로 11·12px 떨어짐 → 겹침으로 침")
	check(SpecCam.ghost_fill(Rect2(683, 300, 70, 70), target, true) == 1.0 and SpecCam.ghost_fill(Rect2(900, 300, 70, 70), target, true) == 1.0, "13px 넘게 떨어짐 → 1")
	check(SpecCam.ghost_fill(Rect2(620, 168, 70, 70), target, true) == hit and SpecCam.ghost_fill(Rect2(620, 167, 70, 70), target, true) == 1.0, "위로도 12px 까지만")
	check(SpecCam.ghost_fill(Rect2(630, 300, 70, 70), target, false) == 1.0 and SpecCam.ghost_fill(target, target, false) == 1.0, "따라가기가 아니면 (전체 보기) 늘 1 — 면 + 테두리 예전 그대로")
	check(SpecCam.ghost_fill(Rect2(630, 300, 70, 70), target, true, {"ghost_fill_hit": 0.25, "ghost_pad": 0.0}) == 0.25 and SpecCam.ghost_fill(Rect2(671, 300, 70, 70), target, true, {"ghost_fill_hit": 0.25, "ghost_pad": 0.0}) == 1.0, "값은 표에서 읽음")
	# 따라가기 갈래가 대상 자리를 넘기고, 그 밖 (전체 보기) 은 비움
	var keep := _spec_setup([])
	var rig = CamRig.new()
	root().add_child(rig)
	var ga = preload("res://world/ghost_aim.gd").new()
	rig.ghost_aim = ga
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	check(ga.follow == Vector3(5.5, 5.5, 0), "따라가기: 조준이 대상 화면 자리를 받음 (%s)" % [ga.follow])
	View.spectate_target = null
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	check(ga.follow == null, "전체 보기: 비움")
	View.spectate_target = 3
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	check(ga.follow == Vector3(5.5, 8.5, 0), "대상이 바뀌면 그 자리")
	Store._players_by_id[1].alive = true
	rig.place(0.016, SPEC_SHOWN, _no_grid)
	check(ga.follow == null, "살아 있으면 비움")
	check(ga.face_fill(rig.cam) == 1.0, "조준·대상이 없으면 면 그대로")
	ga.free()
	_spec_restore(keep, rig)


# 화면 점들의 바깥 사각형
func test_c11_spec_screen_rect() -> void:
	var r: Rect2 = SpecCam.screen_rect(PackedVector2Array([Vector2(640, 300), Vector2(700, 360), Vector2(610, 372), Vector2(655, 290)]))
	check(r.position.is_equal_approx(Vector2(610, 290)) and r.size.is_equal_approx(Vector2(90, 82)), "네 점의 바깥 사각형 %s" % r)
	var one: Rect2 = SpecCam.screen_rect(PackedVector2Array([Vector2(12, -7)]))
	check(one.position.is_equal_approx(Vector2(12, -7)) and one.size == Vector2.ZERO, "점 하나 → 크기 0 (화면 밖 자리도 그대로) %s" % one)
	check(SpecCam.screen_rect(PackedVector2Array()) == Rect2(), "점이 없으면 빈 사각형")
	var pts := PackedVector2Array([Vector2(5, 9), Vector2(-3, 2), Vector2(8, -1)])
	var rr: Rect2 = SpecCam.screen_rect(pts)
	for p in pts:
		check(rr.grow(1e-6).has_point(p), "점 %s 이 사각형 %s 안" % [p, rr])
	check(rr.position.is_equal_approx(Vector2(-3, -1)) and rr.end.is_equal_approx(Vector2(8, 9)), "꼭 맞는 사각형 %s" % rr)


# 안내 띠: 관전 시작·조작 뒤 8초 동안은 두 줄 (사망 원인 / 대상 · 조작 안내), 지나면 한 줄 (사망 원인 · 대상), 조작하면 다시 두 줄
func test_c11_spec_hint_collapse() -> void:
	check(absf(float(SpecCam.SPEC.hint_ms) - 8000.0) < 1e-9, "조작 줄 8초")
	var head := "사망: 낙사 — P5(봇)의 밀치기"
	var who := "P2(봇) 따라가는 중"
	var keys := "마우스 돌리기 · 휠 거리 · Space 다음 사람 · 클릭 블록 떨어뜨리기 · 우클릭 전체 보기"
	var t_last := 1000.0
	for now in [1000.0, 8999.0]:
		check(SpecCam.hint_full(now, t_last), "%d ms 뒤 → 펼침" % int(now - t_last))
		var txt: String = Hud.spec_text(head, who, keys, "", SpecCam.hint_full(now, t_last))
		check(txt.split("\n").size() == 2 and txt == "%s\n%s · %s" % [head, who, keys], "두 줄 (예전 글 그대로): %s" % txt)
	check(not SpecCam.hint_full(9000.0, t_last) and not SpecCam.hint_full(60000.0, t_last), "8000 ms 부터 접힘")
	var one: String = Hud.spec_text(head, who, keys, "", SpecCam.hint_full(9000.0, t_last))
	check(one.split("\n").size() == 1 and one == "%s · %s" % [head, who] and not one.contains("휠 거리"), "한 줄 (사망 원인 · 대상): %s" % one)
	t_last = 9000.0 # 조작 (대상 바뀜·전체 보기 토글·휠 거리) → 그때부터 다시
	check(SpecCam.hint_full(9000.0, t_last) and SpecCam.hint_full(16999.0, t_last) and not SpecCam.hint_full(17000.0, t_last), "t_last 가 바뀌면 다시 8초")
	check(Hud.spec_text(head, who, keys, "", SpecCam.hint_full(9000.0, t_last)).split("\n").size() == 2, "다시 두 줄")
	# 셋째 줄 '살아 있음' (아래 판이 없을 때) 은 접혀도 그대로
	var alive := "▶ P2(봇) 61%   P3(봇) 46%"
	var full3: String = Hud.spec_text(head, "전체 보기", keys, alive, true)
	var fold3: String = Hud.spec_text(head, "전체 보기", keys, alive, false)
	check(full3.split("\n").size() == 3 and full3.ends_with("\n살아 있음: %s" % alive), "펼침 + 살아 있음 = 세 줄")
	check(fold3.split("\n").size() == 2 and fold3 == "%s · 전체 보기\n살아 있음: %s" % [head, alive], "접힘 + 살아 있음 = 두 줄: %s" % fold3)
	check(not SpecCam.hint_full(8000.0, 0.0, {"hint_ms": 8000.0}) and SpecCam.hint_full(7999.0, 0.0, {"hint_ms": 8000.0}) and SpecCam.hint_full(0.0, 0.0, {"hint_ms": 8000.0}), "0·7999 → 펼침, 8000 → 접힘")
	var src := FileAccess.get_file_as_string("res://ui/hud.gd")
	check(src.contains("SpecCam.hint_full(now_ms, spec_hint_at)") and src.contains("if key != spec_hint_key:"), "hud.gd _spectate 가 hint_full·값 비교를 씀")

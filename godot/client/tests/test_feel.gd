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
		var prev := 1.0
		var worst := 0.0
		var d := 0.0
		while d <= b.x + b.y + 2.0:
			var a: float = Edge.alpha_at(size, Vector2(d, mid.y), 1.0)
			check(a <= prev + 1e-6 and absf(a - Edge.alpha_at(size, Vector2(mid.x, size.y - d), 1.0)) < 1e-6, "%s d=%s 알파 %s (안 커짐, 위아래·좌우 같음)" % [size, d, a])
			worst = maxf(worst, prev - a)
			prev = a
			d += 0.5
		check(worst <= steep * 0.5 + 1e-6 and steep < 0.05, "%s 반 화소 걸음에 알파가 %.4f 넘게 떨어짐 (얻음 %.4f) — 띠 경계 계단" % [size, steep * 0.5, worst])
		check(absf(Edge.alpha_at(size, Vector2(b.x + 0.01, mid.y), 1.0) - 1.0) < 1e-3, "%s 바깥 띠 바로 안쪽도 같은 알파 (예전엔 0.55배로 떨어짐)" % size)
		check(Edge.alpha_at(size, Vector2(b.x + b.y + 0.5, mid.y), 1.0) == 0.0 and Edge.alpha_at(size, mid, 1.0) == 0.0, "띠 안쪽은 0")
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
		# 모서리에 계단 없음: 45도 선 (d, d) 근처에서 윗변 쪽·옆 변 쪽으로 반 화소 옮긴 값의 차가 번지는 띠의 가장 가파른 기울기 (반 화소 몫) 안 — 변마다 다른 배율이면 0.6a 가 한 번에 뜀
		var steep: float = maxf((1.0 - float(kn[1])) / (b.y * float(kn[0])), float(kn[1]) / (b.y * (1.0 - float(kn[0]))))
		var worst := 0.0
		var d := 2.0
		while d <= b.x + b.y:
			for cx in [d, size.x - d]:
				var on: float = Edge.alpha_at(size, Vector2(cx, d), 1.0)
				var to_top: float = Edge.alpha_at(size, Vector2(cx + (0.5 if cx < mid.x else -0.5), d), 1.0) # 윗변 쪽 (대각선 안쪽 가로로)
				var to_side: float = Edge.alpha_at(size, Vector2(cx, d + 0.5), 1.0) # 옆 변 쪽 (세로로)
				worst = maxf(worst, maxf(absf(to_top - to_side), maxf(absf(on - to_top), absf(on - to_side))))
			d += 1.0
		check(worst <= steep * 0.5 + 1e-6, "%s 모서리 45도 선에서 반 화소에 알파가 %.4f 넘게 뜀 (얻음 %.4f) — 계단" % [size, steep * 0.5, worst])
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

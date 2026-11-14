# 서버 이벤트 대조 그물: C# 서버 (godot/server/src/Tetrafall.Core) 가 보내는 이벤트 type 을 전부 모아, 고도 클라 처리기 파일 어디에도
# 그 이름 글자 ("<type>") 가 없으면 빠짐으로 본다 (서버에 새 이벤트를 넣고 화면이 흘리는 것을 막음). 일부러 안 받는 것은 UNHANDLED_OK 에 이유와 함께.
# + 이 그물로 찾아 메운 처리 (tutorialStep·ghostDropFail·masterStall) 와 대기실 상태 글·새 방 기본 옵션의 순수 계산
extends RefCounted

const C := preload("res://core/config.gd")
const U := preload("res://ui/ui_calc.gd")
const Input_ := preload("res://core/player_input.gd")
const CamRig := preload("res://world/cam_rig.gd")
const HudExtra := preload("res://ui/hud_extra.gd")
const Lobby := preload("res://ui/lobby.gd")
const Menu := preload("res://ui/menu.gd")
const Prefs := preload("res://ui/ui_prefs.gd")
const RoundEventText := preload("res://ui/round_event_text.gd")

const SERVER_DIR := "../server/src/Tetrafall.Core/" # res:// (godot/client) 기준. 바로 아래 *.cs 만 (bin·obj 하위 폴더는 안 읽음)
const TYPE_RE := "P\\(\"type\", ?\"([A-Za-z]+)\"\\)" # 이벤트·메시지 쓰기: o.P("type", "이름")
const TYPES_MIN := 93 # 2026-11-14 에 센 수 — 줄면 정규식·폴더가 어긋난 것 (그물이 빈 채로 통과하지 않게)
# 서버 이벤트를 받는 파일 (Store.game_event 를 잇는 곳 + 그 처리기가 넘겨 부르는 곳)
const HANDLERS := [
	"res://chars/body.gd",
	"res://world/world.gd", "res://world/marks.gd", "res://world/hook_fx.gd", "res://world/shots.gd", "res://world/bblocks.gd", "res://world/body_fx.gd", "res://world/cam_rig.gd",
	"res://fx/fx.gd",
	"res://audio/audio.gd",
	"res://ui/hud.gd", "res://ui/hud_extra.gd", "res://ui/practice.gd", "res://ui/tutorial_ui.gd",
	"res://core/player_input.gd",
]
# 처리기에 없어도 되는 type → 이유
const UNHANDLED_OK := {"state": "스냅샷 메시지 자체 — core/store.gd 가 받음, 이벤트 아님"}

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# 서버 코드에서 type 이름 모으기 (정렬, 겹침 없음)
static func server_types(dir_path: String) -> Array:
	var re := RegEx.new()
	re.compile(TYPE_RE)
	var seen := {}
	for f in DirAccess.get_files_at(dir_path):
		if not f.ends_with(".cs"):
			continue
		for m in re.search_all(FileAccess.get_file_as_string(dir_path.path_join(f))):
			seen[m.get_string(1)] = true
	var out := seen.keys()
	out.sort()
	return out


# 빠진 type: texts (처리기 파일 글) 어디에도 "<type>" 글자가 없고 ok (예외 표) 에도 없는 것
static func missing(types: Array, texts: Array, ok: Dictionary) -> Array:
	var out := []
	for t in types:
		if ok.has(t):
			continue
		var quoted := "\"%s\"" % t
		var found := false
		for s in texts:
			if str(s).contains(quoted):
				found = true
				break
		if not found:
			out.append(t)
	return out


func _handler_texts() -> Array:
	var texts := []
	for path in HANDLERS:
		var s := FileAccess.get_file_as_string(path)
		check(s != "", "처리기 파일을 못 읽음: %s" % path)
		texts.append(s)
	return texts


func _types() -> Array:
	return server_types(ProjectSettings.globalize_path("res://").path_join(SERVER_DIR))


func test_server_events_all_handled() -> void:
	var types := _types()
	check(types.size() >= TYPES_MIN, "서버 type %d개 (%d개 이상이어야 — 폴더·정규식 확인)" % [types.size(), TYPES_MIN])
	for t in ["hit", "death", "roundEvent", "tutorialStep", "ghostDropFail", "masterStall", "state"]:
		check(types.has(t), "서버 type 에 '%s' 가 없음 (모으기가 어긋남)" % t)
	var miss := missing(types, _handler_texts(), UNHANDLED_OK)
	check(miss.is_empty(), "서버가 보내는데 클라 처리기에 없는 이벤트 %d개: %s" % [miss.size(), ", ".join(miss)])
	# 예외 표는 실제로 서버에 있는 type 만 (없어진 이름이 남아 있지 않게) + 이유 글
	for k in UNHANDLED_OK:
		check(types.has(k), "UNHANDLED_OK 의 '%s' 는 서버에 없는 type" % k)
		check(str(UNHANDLED_OK[k]) != "", "UNHANDLED_OK '%s' 이유 없음" % k)
	check(UNHANDLED_OK.size() == 1 and UNHANDLED_OK.has("state"), "예외는 state 하나만: %s" % str(UNHANDLED_OK.keys()))


# 그물이 실제로 잡는지: 없는 type 을 넣으면 빠짐에 나오고, 예외 표에 넣으면 빠짐
func test_cover_reports_missing() -> void:
	var texts := _handler_texts()
	var types := _types()
	types.append("zzNoSuch")
	var miss := missing(types, texts, UNHANDLED_OK)
	check(miss == ["zzNoSuch"], "가짜 type 만 빠짐에 나와야: %s" % str(miss))
	check(missing(types, texts, {"state": "", "zzNoSuch": "시험"}).is_empty(), "예외 표에 넣으면 빠짐 아님")
	# 따옴표까지 맞아야 함 (다른 낱말 속에 든 것은 처리로 안 침), 예외 표가 비면 state 도 빠짐
	check(missing(["hit"], ["match t:\n\t\"hitStop\":\n"], {}) == ["hit"], "낱말 속 글자는 처리 아님")
	check(missing(["hit"], ["x", "\t\t\"hit\":"], {}).is_empty(), "둘째 파일에 있으면 처리")
	check(missing(["hit"], [], {}) == ["hit"], "처리기 글이 없으면 전부 빠짐")
	check(missing(_types(), texts, {}) == ["state"], "예외 표 없이: %s" % str(missing(_types(), texts, {})))


# tutorialStep (Tutorial.cs: {i, id, yaw, who}): 내 것이면 그 단계에서 볼 쪽 yaw, 남의 것·다른 type 이면 null
func test_tutorial_step_turns_view() -> void:
	var e := {"type": "tutorialStep", "i": 2.0, "id": "dash", "yaw": 1.25, "who": 3.0} # JSON 숫자는 float
	var y = Input_.step_yaw(e, 3)
	check(y != null and is_equal_approx(float(y), 1.25), "내 것: %s" % str(y))
	check(Input_.step_yaw(e, 4) == null, "남의 것은 null")
	check(Input_.step_yaw(e, null) == null, "방 밖 (my_id null) 은 null")
	var zero = Input_.step_yaw({"type": "tutorialStep", "yaw": 0.0, "who": 0.0}, 0)
	check(zero != null and is_zero_approx(float(zero)), "yaw 0·id 0 도 내 것 (null 과 다름): %s" % str(zero))
	check(Input_.step_yaw({"type": "tutorialOk", "yaw": 1.25, "who": 3.0}, 3) == null, "다른 type 은 null")
	check(Input_.step_yaw({"type": "tutorialStep", "who": 3.0}, 3) == null, "yaw 없으면 null")
	check(Input_.step_yaw({}, 3) == null, "빈 이벤트")


# ghostDropFail (Game.Pieces.cs GhostDrop: {who, reason}): 내 것만 조준 원 흔들림
func test_ghost_drop_fail_marks_refuse() -> void:
	for reason in ["mode", "cd", "full"]:
		check(CamRig.refuse_from({"type": "ghostDropFail", "who": 2.0, "reason": reason}, 2), "내 투하 거절 (%s)" % reason)
	check(not CamRig.refuse_from({"type": "ghostDropFail", "who": 5.0, "reason": "cd"}, 2), "남의 거절은 아님")
	check(not CamRig.refuse_from({"type": "ghostDrop", "who": 2.0}, 2), "된 투하 (ghostDrop) 는 아님")
	check(not CamRig.refuse_from({"type": "ghostDropFail", "who": 2.0}, null), "방 밖은 아님")
	check(CamRig.refuse_from({"type": "ghostDropFail", "who": 0.0}, 0), "id 0 도 내 것")
	check(not CamRig.refuse_from({"type": "ghostDropFail"}, 0), "who 없음")


# masterStall (Game.Items.cs counter: {who, until, ms}): 마스터 편·먹은 사람·다른 생존자 세 시점 글 + 아이템 이름
func test_master_stall_text_and_counter_name() -> void:
	var e := {"type": "masterStall", "who": 4.0, "until": 91000.0, "ms": float(C.MASTER_COUNTER_STALL_MS)}
	var n := int(ceil(float(C.MASTER_COUNTER_STALL_MS) / 1000.0))
	check(U.master_stall_text(e, {"id": 1.0, "master": true}, "봇4") == "반격! 블록 %d초 멈춤" % n, "마스터: '%s'" % U.master_stall_text(e, {"id": 1.0, "master": true}, "봇4"))
	check(U.master_stall_text(e, {"id": 2.0, "master": true, "zombie": true}, "봇4") == "반격! 블록 %d초 멈춤" % n, "마스터 편 (좀비)")
	check(U.master_stall_text(e, {"id": 2.0, "zombie": true}, "봇4") == "반격! 블록 %d초 멈춤" % n, "zombie 만 와도 마스터 편")
	check(U.master_stall_text(e, {"id": 4.0}, "나") == "반격! 마스터 블록 %d초 멈춤" % n, "먹은 사람: '%s'" % U.master_stall_text(e, {"id": 4.0}, "나"))
	check(U.master_stall_text(e, {"id": 6.0, "master": false}, "봇4") == "봇4 반격! 마스터 블록 %d초 멈춤" % n, "다른 생존자: '%s'" % U.master_stall_text(e, {"id": 6.0}, "봇4"))
	check(U.master_stall_text(e, {}, "봇4") == "봇4 반격! 마스터 블록 %d초 멈춤" % n, "내 플레이어가 없으면 이름 붙은 글")
	# 초는 올림 (ms 그대로 받음 — 겹쳐 먹어도 이벤트마다 한 번 분량)
	check(U.master_stall_text({"who": 4.0, "ms": 2500.0}, {"id": 4.0}, "") == "반격! 마스터 블록 3초 멈춤", "2.5초 → 3초")
	check(U.master_stall_text({"who": 0.0, "ms": 4000.0}, {"id": 0.0}, "") == "반격! 마스터 블록 4초 멈춤", "id 0 도 먹은 사람")
	check(HudExtra.ITEM_KO.get("counter") == "반격", "ITEM_KO.counter: %s" % str(HudExtra.ITEM_KO.get("counter")))


# 대기실 판 상태 한 줄 (lobby 가 아닌 단계): 끝난 판만 '종료'
func test_lobby_status_by_phase() -> void:
	check(Lobby.phase_status("over", 3) == "라운드 3 종료", "over: '%s'" % Lobby.phase_status("over", 3))
	check(Lobby.phase_status("countdown", 3) == "곧 시작", "countdown: '%s'" % Lobby.phase_status("countdown", 3))
	check(Lobby.phase_status("playing", 3) == "라운드 3 진행 중", "playing: '%s'" % Lobby.phase_status("playing", 3))
	for ph in ["countdown", "playing"]:
		check(not Lobby.phase_status(ph, 7).contains("종료"), "%s 글에 '종료' 가 있음" % ph)
	check(Lobby.phase_status("playing", 12).contains("12"), "판 번호")


# 메뉴로 만든 방의 기본 옵션: 돌발 이벤트 켬 (기억이 '끔' 이면 그대로 둠)
func test_create_defaults() -> void:
	var on := [{"type": "roundEvents", "on": true}]
	check(U.create_defaults(null, {}) == on, "기억 없음 → 켬: %s" % str(U.create_defaults(null, {})))
	check(U.create_defaults(true, {}) == on, "기억 켬 → 켬")
	check(U.create_defaults(false, {}).is_empty(), "기억 끔 → 안 보냄")
	check(U.create_defaults(null, {"roundEvents": true}).is_empty(), "이미 켜짐 → 안 보냄")
	check(U.create_defaults(true, {"roundEvents": true, "mode": "survival"}).is_empty(), "이미 켜짐 (기억 켬) → 안 보냄")
	check(U.create_defaults(null, {"roundEvents": false}) == on, "꺼져 있음 → 켬")
	check(U.create_defaults(null, {"mode": "master", "phase": "lobby"}) == on, "블록 마스터 방도 켬 (모드를 바꾸면 돎)")
	check(U.create_defaults(false, {"mode": "master"}).is_empty(), "끔 기억은 모드와 상관없이 그대로")
	# 보낼 메시지는 서버 방 메시지 모양 그대로 (Rooms.cs roundEvents: {type, on})
	var m: Dictionary = U.create_defaults(null, {})[0]
	check(m.size() == 2 and m.get("type") == "roundEvents" and m.get("on") == true, "메시지 모양: %s" % str(m))


# ---------- 이벤트 연결 줄 (사이클 2 리뷰 F8: 줄을 지우거나 바꿔도 테스트가 그대로 통과하던 것) ----------
# 아래 노드 테스트는 러너가 SceneTree._initialize 안에서 돌아 노드가 트리에 못 들어감 (뿌리가 아직 트리 밖) → _ready 를 직접 부르고
# 처리기 (_on_event·_event_chip·_create·_on_created) 를 직접 부름. 화면 크기를 읽는 refresh (get_viewport_rect) 는 못 불러
# refresh 가 _event_chip 을 부르는 한 줄은 여기서 못 봄 (자동 조종 스크린샷 몫)

# 아이템 주움 알림 고르기 (pickup {who, item}): 내가 주운 것만, 반격 (counter) 은 masterStall 이 알리니 넘김
func test_pickup_toast() -> void:
	var names: Dictionary = HudExtra.ITEM_KO
	check(U.pickup_toast({"type": "pickup", "who": 2.0, "item": "jump"}, 2, names) == "점프력 상승!", "내가 주움: '%s'" % U.pickup_toast({"who": 2.0, "item": "jump"}, 2, names))
	check(U.pickup_toast({"type": "pickup", "who": 2.0, "item": "counter"}, 2, names) == "", "반격은 넘김 (masterStall 이 알림)")
	check(U.pickup_toast({"type": "pickup", "who": 3.0, "item": "jump"}, 2, names) == "", "남이 주운 것")
	check(U.pickup_toast({"type": "pickup", "who": 3.0, "item": "counter"}, 2, names) == "", "남이 주운 반격")
	check(U.pickup_toast({"type": "pickup", "who": 0.0, "item": "bomb"}, 0, names) == "폭탄!", "id 0 도 내 것")
	check(U.pickup_toast({"type": "pickup", "who": 2.0, "item": "jump"}, null, names) == "", "방 밖 (내 id 없음)")
	check(U.pickup_toast({"type": "pickup", "item": "jump"}, 2, names) == "", "who 없음")
	check(U.pickup_toast({"type": "pickup", "who": 2.0, "item": "meteor"}, 2, names) == "meteor!", "표에 없는 아이템은 id 그대로")
	for item in names: # 반격만 빼고 전부 '이름!'
		var got := U.pickup_toast({"type": "pickup", "who": 2.0, "item": item}, 2, names)
		check(got == ("" if item == "counter" else "%s!" % names[item]), "%s: '%s'" % [item, got])


# 방을 만든 뒤 welcome 에 보낼 메시지: 재접속이면 없음, 아니면 기본 방 옵션
func test_created_msgs() -> void:
	var on := [{"type": "roundEvents", "on": true}]
	check(U.created_msgs(false, null, {}) == on, "새로 만든 방: %s" % str(U.created_msgs(false, null, {})))
	check(U.created_msgs(true, null, {}).is_empty(), "재접속이면 안 보냄")
	check(U.created_msgs(false, false, {}).is_empty(), "끔 기억이면 안 보냄")
	check(U.created_msgs(false, true, {"roundEvents": true}).is_empty(), "이미 켜짐")


static func _toast_texts(h) -> Array:
	return h.toasts.get_children().map(func(x): return str(x.text))


# hud_extra.gd 처리기: pickup → 알림 (반격·남의 것은 없음), masterStall → 알림 (세 시점 글), 돌발 이벤트 띠
func test_hud_extra_event_wiring() -> void:
	var keep_state = Store.state
	var keep_by = Store._players_by_id
	var keep_me = Store.my_id
	var me := {"id": 2.0, "name": "나", "nick": "", "alive": true, "master": false, "zombie": false}
	var bot := {"id": 4.0, "name": "봇4", "nick": "", "alive": true, "master": false, "zombie": false}
	Store.state = {"phase": "playing", "mode": "master", "players": [me, bot]}
	Store._players_by_id = {2: me, 4: bot}
	Store.my_id = 2
	var h = HudExtra.new()
	h._ready()
	check(Store.game_event.is_connected(h._on_event), "hud_extra 가 이벤트 신호를 받음")
	# pickup
	h._on_event({"type": "pickup", "who": 2.0, "item": "jump"})
	check(_toast_texts(h) == ["점프력 상승!"], "내가 주움 → 알림: %s" % str(_toast_texts(h)))
	h._on_event({"type": "pickup", "who": 2.0, "item": "counter"})
	h._on_event({"type": "pickup", "who": 4.0, "item": "speed"})
	h._on_event({"type": "pickup", "who": 4.0, "item": "counter"})
	check(_toast_texts(h) == ["점프력 상승!"], "반격·남이 주운 것은 알림 없음: %s" % str(_toast_texts(h)))
	# masterStall: 먹은 사람 (나) · 다른 생존자가 먹음 · 내가 마스터 편
	var ms := float(C.MASTER_COUNTER_STALL_MS)
	var n := int(ceil(ms / 1000.0))
	h._on_event({"type": "masterStall", "who": 2.0, "until": 9000.0, "ms": ms})
	check(_toast_texts(h) == ["점프력 상승!", "반격! 마스터 블록 %d초 멈춤" % n], "내가 먹음: %s" % str(_toast_texts(h)))
	h._on_event({"type": "masterStall", "who": 4.0, "until": 9000.0, "ms": ms})
	check(_toast_texts(h).back() == "봇4 반격! 마스터 블록 %d초 멈춤" % n, "남이 먹음: %s" % str(_toast_texts(h)))
	me.master = true
	h._on_event({"type": "masterStall", "who": 4.0, "until": 9000.0, "ms": ms})
	check(_toast_texts(h).back() == "반격! 블록 %d초 멈춤" % n, "마스터 편: %s" % str(_toast_texts(h)))
	check(_toast_texts(h).size() == 4, "알림 줄 수: %s" % str(_toast_texts(h)))
	me.master = false
	# 돌발 이벤트 띠: 판 중 + 진행 중인 이벤트가 있을 때만, 글은 RoundEventText.status
	var rain := {"kind": "rain", "left": 4200.0, "dir": null}
	check(not h.event_chip.visible, "처음엔 띠 없음")
	h._event_chip({"phase": "playing", "roundEvent": rain})
	check(h.event_chip.visible and h.event_chip.text == "블록 폭우 5초", "폭우 띠: %s '%s'" % [str(h.event_chip.visible), h.event_chip.text])
	var wind := {"kind": "wind", "left": 3000.0, "dir": {"x": 0.0, "y": -1.0}}
	h._event_chip({"phase": "playing", "roundEvent": wind})
	check(h.event_chip.visible and h.event_chip.text == RoundEventText.status(wind, h._view_yaw()) and h.event_chip.text.begins_with("돌풍"), "돌풍 띠: '%s'" % h.event_chip.text)
	h._event_chip({"phase": "over", "roundEvent": rain})
	check(not h.event_chip.visible, "판 중이 아니면 띠 없음")
	h._event_chip({"phase": "playing", "roundEvent": rain})
	h._event_chip({"phase": "playing", "roundEvent": null})
	check(not h.event_chip.visible, "이벤트가 끝나면 띠 없음")
	h._event_chip({"phase": "playing", "roundEvent": {"kind": "supply", "left": 3000.0}})
	check(not h.event_chip.visible, "보급은 띠 없음")
	h.free()
	Store.state = keep_state
	Store._players_by_id = keep_by
	Store.my_id = keep_me


# menu.gd: 방 만들기 → 그 방의 welcome 에 한 번만 기본 방 옵션을 보냄. 재접속·다른 길 (코드·연습) 로 들어가면 안 보냄
func test_menu_create_sends_room_defaults() -> void:
	var keep_state = Store.state
	var keep_pref = Prefs.get_value("roundEvents", null)
	Prefs._load()["roundEvents"] = true # 기억 '켬' 으로 고정 (파일엔 안 씀 — 끝나면 되돌림)
	Store.state = {}
	var menu = Menu.new()
	menu._ready()
	var sent: Array = []
	menu.send_room = func(m: Dictionary): sent.append(m)
	# 만든 방의 welcome 에 불릴 연결 (joined 신호를 진짜로 쏘면 다른 듣는 쪽 — PlayerInput 등 — 도 불리니, 메뉴의 연결만 골라 부름)
	var call_created := func(rejoined: bool) -> int:
		var n := 0
		for c in Store.joined.get_connections():
			if (c.callable as Callable).get_object() == menu:
				(c.callable as Callable).call({"code": "ABCD"}, rejoined)
				n += 1
		return n
	check(call_created.call(false) == 0 and sent.is_empty(), "만들기 전엔 연결 없음")
	menu._create()
	check(call_created.call(false) == 1, "만들기 → welcome 연결 하나")
	check(sent == [{"type": "roundEvents", "on": true}], "새 방 welcome → 돌발 이벤트 켬 메시지: %s" % str(sent))
	menu._create() # 두 번 눌러도 연결은 하나
	sent.clear()
	check(call_created.call(false) == 1 and sent.size() == 1, "연결은 하나: %s" % str(sent))
	# 재접속 welcome 이면 안 보냄
	sent.clear()
	check(call_created.call(true) == 1 and sent.is_empty(), "재접속이면 안 보냄: %s" % str(sent))
	# 이미 켜진 방·끔 기억이면 안 보냄
	Store.state = {"roundEvents": true}
	call_created.call(false)
	check(sent.is_empty(), "이미 켜진 방: %s" % str(sent))
	Store.state = {}
	Prefs._load()["roundEvents"] = false
	call_created.call(false)
	check(sent.is_empty(), "끔 기억: %s" % str(sent))
	Prefs._load()["roundEvents"] = true
	# 다른 길로 들어가면 남은 연결을 걷음 (남의 방·연습 방에 옵션을 보내지 않게)
	menu._join("WXYZ")
	check(call_created.call(false) == 0 and sent.is_empty(), "코드로 들어가면 연결 걷음")
	menu._create()
	menu._practice()
	check(call_created.call(false) == 0 and sent.is_empty(), "연습으로 들어가도 연결 걷음")
	menu.free()
	if keep_pref == null:
		Prefs._load().erase("roundEvents")
	else:
		Prefs._load()["roundEvents"] = keep_pref
	Store.state = keep_state

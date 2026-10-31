# 자동 조종 (헤드리스 확인용, main.gd --auto): host 는 방 만들고 봇 넣고 시작, guest 는 --room 으로 들어감.
# 판 중에는 가장 가까운 상대 쪽으로 걸으며 평타 (PlayerInput.override). --drop-at 초에 연결을 일부러 끊어 재접속(같은 자리) 확인.
# 끝에 한 줄 요약을 찍고 종료 코드 0 (확인 실패면 2)
# 화면 확인 (G4): --shot <png> --shot-at menu|lobby|game|tab|settings|results (기본 game). menu = 방 안 만듦, lobby = 시작 안 함,
# tab = 판 중 점수표 (킬 점수전에서만 보임 → --mode kills), settings = 설정 창, results = 판이 끝나고 --shot-after 초 (기본 1.5) 뒤.
# --mode survival|master|kills 면 시작 전에 모드를 바꿈. 창 크기는 고도 --resolution 1280x720
# 성능 비교 (G3): --view first|third|spectate (third 는 설정 3인칭, spectate 는 방장이 관전) · --map <맵 id> · --perf-log 에 1% low·메모리 한 줄 더
# 성능: --perf-log (찍는 순간 = --shot-after 에 그리기 수·물체 수·삼각형 수·FPS·프레임 ms 한 줄, 화면 없이도)
# --auto practice|tutorial: 연습·튜토리얼 방 (G6, --char 캐릭터, 연습 창은 --practice-open)
# 연기 시험 (B4): --team (팀전) · --sky (하늘 계단) · --char <id> (방장 캐릭터도) · --skills <초> (그 간격으로 F·R) ·
#   --color <팔레트 번호> (host·guest, 받아짐/거절 로그) · 방장이 나가 넘겨받으면 로그 + 판 시작도 맡음 ·
#   --shot-round <N> (N판째 시작 뒤 --shot-after 초에 찍음) · --char2 <id> --char2-at <초> (연습: 판 중 캐릭터 바꾸기) · --tut-skip <초> (튜토리얼: 한 단계에 이만큼 머물면 넘기기 → 끝까지)
# 화면 범인 찾기: --hide ui|world|audio (그 묶음을 숨기고 찍음) · --dump (찍을 때 보이는 Control·CanvasItem·3D 노드를 화면 사각형과 함께 출력)
extends Node

const C := preload("res://core/config.gd")
const Prof := preload("res://core/prof.gd")

var args := {}
var role := "host"
var start_ms := 0.0
var created := false
var started := false
var snapshots := 0
var rounds := 0
var last_phase := ""
var moved := 0.0
var last_pos = null
var rejoined := false
var skill_at := 0.0 # --skills: 다음 F·R 시각 (ms)
var char2_sent := false
var tut_step := -1
var tut_since := 0.0
var dropped := false
var interp_ok := 0
var push_at := 0.0
var shot_done := false
var perf_done := false
var frame_ms: Array = [] # --perf-log: 최근 프레임 시간 (ms, 벽시계)
var last_us := 0
var perf_rt := false
var perf_split := [0.0, 0.0, 0.0, 0.0, 0] # 그리기 CPU · GPU · _process · 물리 (ms 합), 프레임 수
var shot_at := "game"
var over_ms := -1.0
var was_host = null # 방장이 바뀌면 로그 (방장 나가면 넘김)
var color_sent := -1.0 # --color 보낸 시각 (받아짐·거절 로그)
var round_no := 0 # --shot-round: 지금 몇 판째 (playing 이 될 때마다 +1)
var round_ms := -1.0
var mode_sent := false


func _ready() -> void:
	role = str(args.get("auto", "host"))
	shot_at = str(args.get("shot-at", "game"))
	start_ms = Net.now_ms()
	if args.has("view"):
		View.settings["third"] = str(args["view"]) == "third"
	if args.has("perf-log"):
		Prof.on = true
	# 성능 실험 (엔진 설정): --phys-ticks N (물리 틱/초) · --phys-max N (프레임당 최대 물리 틱) · --shadow-size N (해 그림자 지도) · --shadow-filter 0..5 · --msaa 0|2|4
	if args.has("phys-ticks"):
		Engine.physics_ticks_per_second = int(args["phys-ticks"])
	if args.has("phys-max"):
		Engine.max_physics_steps_per_frame = int(args["phys-max"])
	if args.has("shadow-size"):
		RenderingServer.directional_shadow_atlas_set_size(int(args["shadow-size"]), true)
	if args.has("shadow-filter"):
		RenderingServer.directional_soft_shadow_filter_set_quality(int(args["shadow-filter"]))
	if args.has("msaa"):
		get_viewport().msaa_3d = int(args["msaa"])
	if args.has("low"): # 성능 비교: 그래픽 낮춤으로
		View.settings["lowGfx"] = true
	Store.rooms_changed.connect(_on_rooms)
	Store.joined.connect(_on_joined)
	Store.state_changed.connect(_on_state)
	Store.join_error.connect(func(r): _log("들어가기 실패: %s" % r))


func _log(t: String) -> void:
	print("[자동 %s] %s" % [role, t])


func _on_rooms(_list: Dictionary) -> void:
	if role == "host" and shot_at != "menu" and not created and not Store.in_room() and Store.pending_code == "":
		created = true
		Store.create_room("", str(args.get("name", "고도")))
	if role in ["practice", "tutorial"] and not created and not Store.in_room(): # G6 연습·튜토리얼 방 (혼자, 바로 판)
		created = true
		Net.send({"type": role, "nick": str(args.get("name", "고도")), "char": str(args.get("char", C.CHAR_DEFAULT))})


func _on_joined(room: Dictionary, again: bool) -> void:
	_log("방 %s 들어옴 (내 id %d%s)" % [room.code, Store.my_id, ", 같은 자리로 다시" if again else ""])
	if again:
		rejoined = true
		return
	PlayerInput.lock_mouse(true) # 헤드리스: 마우스 잡힌 셈 (입력이 나가게)
	if role in ["host", "guest"]: # 대전 흐름 (B4): 캐릭터·색 고르기 (같은 색은 서버가 거절)
		if args.has("char"):
			Store.send_room({"type": "setChar", "char": str(args["char"])})
		if args.has("color"):
			Store.send_room({"type": "setColor", "color": int(args["color"])})
			color_sent = Net.now_ms()
	if role == "host":
		if args.has("team"):
			Store.send_room({"type": "teamMode", "on": true})
		if args.has("sky"):
			Store.send_room({"type": "skyStairs", "on": true})
		if args.has("map"): # 성능 비교 (G3): 같은 맵
			Store.send_room({"type": "setMap", "map": str(args["map"])})
		if str(args.get("view", "")) == "spectate": # 관전: 방장은 빠지고 봇만
			Store.send_room({"type": "spectate"})
		for i in int(args.get("bots", 1)):
			Store.send_room({"type": "addBot"})
	if role == "practice":
		Store.send_room({"type": "dummyAdd"})
		if args.has("map"): # 화면 대조 (B4): 연습 방도 같은 맵 (연습 방은 누구나 setMap)
			Store.send_room({"type": "setMap", "map": str(args["map"])})


func _on_state(st: Dictionary, _prev: Dictionary) -> void:
	snapshots += 1
	var ph := str(st.phase)
	if role == "host" and args.has("mode") and not mode_sent and ph == "lobby" and st.get("hostId") == Store.my_id:
		mode_sent = true
		Store.send_room({"type": "setMode", "mode": str(args["mode"])})
	var is_host: bool = st.get("hostId") != null and Store.my_id != null and int(st.hostId) == int(Store.my_id)
	if was_host != null and is_host and not was_host:
		_log("방장 됨 (방장이 나가서 넘겨받음)")
	was_host = is_host
	if color_sent >= 0 and Net.now_ms() - color_sent > 1500 and not Store.me().is_empty():
		var want := int(args["color"])
		var got := int(Store.me().get("color", -1))
		_log("색 %d %s (지금 %d)" % [want, "받아짐" if got == want else "거절", got])
		color_sent = -1.0
	if (role == "host" or is_host) and shot_at != "lobby" and not started and ph == "lobby" and (not args.has("mode") or st.get("mode") == str(args["mode"])) and st.get("canStart", false) and (Store.player(Store.my_id).size() > 0 or str(args.get("view", "")) == "spectate") and int(st.players.size()) >= int(args.get("wait-players", 2)):
		started = true
		Store.send_room({"type": "start"})
		_log("시작 (%d명)" % st.players.size())
	if ph == "over" and last_phase == "playing":
		rounds += 1
		over_ms = Net.now_ms()
		_log("판 %d 끝: 승자 %s, 스냅샷 %d개, 내가 움직인 거리 %.1f칸, 보간 위치 %d번" % [rounds, str(st.round.winnerId), snapshots, moved, interp_ok])
		if (role == "host" or is_host) and rounds < int(args.get("quit-after-rounds", 1)):
			Store.send_room({"type": "start"})
	if ph == "playing" and last_phase != "playing":
		round_no += 1
		round_ms = Net.now_ms()
	last_phase = ph
	var me := Store.me()
	if not me.is_empty():
		var p := Vector3(me.x, me.y, me.z)
		if last_pos != null:
			moved += (p - last_pos).length()
		last_pos = p


func _process(_d: float) -> void:
	var now := Net.now_ms()
	var el := (now - start_ms) / 1000.0
	# 판 중: 가장 가까운 상대 쪽으로 걷고 가끔 평타
	var me := Store.me()
	if Store.phase() == "playing" and not me.is_empty() and me.alive:
		var best = null
		var bd := INF
		for p in Store.state.players:
			if int(p.id) == Store.my_id or not p.alive:
				continue
			var d := Vector2(p.x - me.x, p.y - me.y).length()
			if d < bd:
				bd = d
				best = p
		var yaw: float = atan2(best.y - me.y, best.x - me.x) if best != null else me.yaw
		var fwd := 1 if best != null and bd > 1.2 else 0 # 상대가 없으면 (튜토리얼 빈 단계·혼자 연습) 제자리 — 계속 걸으면 섬 밖으로 떨어짐
		# 튜토리얼: 단계 목표 칸이 있으면 그리로 (shared/tutorial-pilot.js go(target) 만 — 화면 확인용)
		var tut = Store.state.get("tutorial")
		if best == null and tut is Dictionary and tut.get("target") is Dictionary and not tut.get("done", false):
			var tx := float(tut.target.x)
			var ty := float(tut.target.y)
			yaw = atan2(ty - me.y, tx - me.x)
			fwd = 1 if Vector2(tx - me.x, ty - me.y).length() > 0.15 else 0
		PlayerInput.set_yaw_pitch(yaw, 0)
		PlayerInput.override = {"type": "input", "fwd": fwd, "strafe": 0, "jump": false, "yaw": yaw, "pitch": 0}
		if bd < 1.7 and now >= push_at:
			push_at = now + 300
			PlayerInput.press("attack")
		if args.has("skills") and now >= skill_at: # 연기 시험: F·R 번갈아
			skill_at = now + float(args["skills"]) * 1000.0
			PlayerInput.press("skill")
			PlayerInput.press("ult")
		if Store.view_pos(Store.my_id) != Vector3.ZERO:
			interp_ok += 1
	else:
		PlayerInput.override = null
	if role == "practice" and args.has("char2") and not char2_sent and el >= float(args.get("char2-at", 6)):
		char2_sent = true
		Store.send_room({"type": "setChar", "char": str(args["char2"])})
		_log("캐릭터 바꿈 → %s" % args["char2"])
	var tut = Store.state.get("tutorial") if role == "tutorial" else null
	if tut is Dictionary and args.has("tut-skip") and not tut.get("done", false):
		if int(tut.get("i", -1)) != tut_step:
			tut_step = int(tut.get("i", -1))
			tut_since = now
			_log("튜토리얼 %d/%d %s" % [tut_step + 1, int(tut.get("n", 0)), str(tut.get("id", ""))])
		elif now - tut_since > float(args["tut-skip"]) * 1000.0:
			tut_since = now
			Store.send_room({"type": "tutorialSkip"})
	if tut is Dictionary and tut.get("done", false) and tut_step != 999:
		tut_step = 999
		_log("튜토리얼 끝")
	if args.has("drop-at") and not dropped and el >= float(args["drop-at"]):
		dropped = true
		_log("연결을 일부러 끊음 (재접속 확인)")
		Net.drop_for_test()
	if args.has("hide"):
		for n in get_tree().root.get_child(get_tree().root.get_child_count() - 1).get_children():
			if n.name.to_lower().begins_with(str(args.hide)) and n.get("visible") != null:
				n.set("visible", false)
	var ui := get_tree().root.find_child("UI", true, false) # G4 ui/ui.gd (없으면 dev_ui — 그땐 tab·settings 안 함)
	if ui != null and shot_at == "tab" and ui.get("hud") is Object:
		ui.get("hud").set("scores_held", Store.phase() == "playing")
	if ui != null and shot_at == "settings" and ui.get("settings") is Control and el >= float(args.get("shot-after", 8)) - 1.0:
		(ui.get("settings") as Control).visible = true
	var shot_time := el >= float(args.get("shot-after", 8))
	if args.has("shot-round"): # N판째 playing 이 된 뒤 --shot-after 초 (블록 마스터 2판째 = 생존자 화면)
		shot_time = round_no == int(args["shot-round"]) and Store.phase() == "playing" and now - round_ms >= float(args.get("shot-after", 8)) * 1000.0
	if shot_at == "results":
		shot_time = over_ms >= 0.0 and now - over_ms >= float(args.get("shot-after", 1.5)) * 1000.0
	if args.has("perf-log"):
		if not perf_rt:
			perf_rt = true
			RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		if el >= float(args.get("shot-after", 8)) - float(args.get("perf-secs", 1e9)):
			var vr := get_viewport().get_viewport_rid()
			perf_split[0] += RenderingServer.viewport_get_measured_render_time_cpu(vr) + RenderingServer.get_frame_setup_time_cpu()
			perf_split[1] += RenderingServer.viewport_get_measured_render_time_gpu(vr)
			perf_split[2] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			perf_split[3] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			perf_split[4] += 1
		elif Prof.on:
			Prof.reset() # 재기 전 구간 합은 버림
		var now_us := Time.get_ticks_usec() # 벽시계 (_process delta 는 느리면 물리 틱 수로 잘려 133ms 에서 멈춤)
		if last_us > 0 and el >= float(args.get("shot-after", 8)) - float(args.get("perf-secs", 1e9)): # --perf-secs N: 찍기 전 N 초만 (판 시작·로딩 빼고)
			frame_ms.append((now_us - last_us) / 1000.0)
		last_us = now_us
		if frame_ms.size() > (100000 if args.has("perf-secs") else 120):
			frame_ms.pop_front()
		if not perf_done and shot_time:
			perf_done = true
			var avg := 0.0
			var worst := 0.0
			for v in frame_ms:
				avg += v
				worst = maxf(worst, v)
			avg /= maxf(1.0, frame_ms.size())
			var sorted := frame_ms.duplicate()
			sorted.sort()
			var k := maxi(1, ceili(sorted.size() * 0.01))
			var low := 0.0
			for i in k:
				low += sorted[sorted.size() - 1 - i]
			_log("성능 표: 평균 %.2fms · 1%% low %.2fms · 그리기 %d · 메모리 %.1fMB (영상 %.1fMB) · 프레임 %d | 나눔 평균: 그리기 CPU %.1fms · GPU %.1fms · 스크립트 %.1fms · 물리 %.1fms" % [avg, low / k, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, sorted.size(), perf_split[0] / maxf(1, perf_split[4]), perf_split[1] / maxf(1, perf_split[4]), perf_split[2] / maxf(1, perf_split[4]), perf_split[3] / maxf(1, perf_split[4])])
			_log("성능 구간 (프레임당): %s" % Prof.report(int(perf_split[4])))
			_log("성능: 그리기 %d · 물체 %d · 삼각형 %d · FPS %d · 프레임 평균 %.1fms 최악 %.1fms (최근 %d프레임) | 나눠서: 보이는 %d · 그림자 %d · 몸 메시 %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Engine.get_frames_per_second(), avg, worst, frame_ms.size(), get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME), get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME), _body_meshes(get_tree().root)])
			var rw = get_tree().root.get_node_or_null("TfRagdolls")
			if rw != null:
				_log("래그돌: 깨어 있음 %d / 켠 몸 %d · 힘 계산 %.2fms/틱 · 물리 처리 (엔진 포함) %.2fms/틱 · 물리 틱 %d/초" % [rw.stats.n, rw.stats.get("total", 0), rw.stats.ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Engine.physics_ticks_per_second])
				var why := {}
				_rag_why(get_tree().root, why)
				_log("래그돌 만든 수 %d · 안 켠 몸 %s" % [rw.made, str(why)])
	if args.has("shot") and not shot_done and shot_time and DisplayServer.get_name() != "headless":
		shot_done = true
		get_viewport().get_texture().get_image().save_png(str(args.shot))
		_log("화면 저장 %s" % args.shot)
		if args.has("dump"):
			_dump(get_tree().root, 0)
	var done_rounds := rounds >= int(args.get("quit-after-rounds", 999999))
	var done_time := args.has("quit-after") and el >= float(args["quit-after"])
	if done_rounds or done_time:
		var ok := (snapshots > 0 or shot_at == "menu") and (not args.has("drop-at") or rejoined) and (not args.has("quit-after-rounds") or done_rounds) and (not args.has("min-moved") or moved >= float(args["min-moved"]))
		var sfx := get_tree().root.find_child("Sfx", true, false)
		var music := get_tree().root.find_child("Music", true, false)
		var snd := (" | 효과음 %d번, 곡 %s" % [sfx.played, music.song_key]) if sfx != null and music != null else ""
		var fxn := get_tree().get_first_node_in_group("fx")
		if fxn != null:
			snd += " | 효과 이벤트 %d번" % fxn.events
		_log("끝: 판 %d번, 스냅샷 %d개, 움직인 거리 %.1f칸, 재접속 %s, %s%s" % [rounds, snapshots, moved, "같은 자리" if rejoined else "안 함", Net.ping_text(), snd])
		get_tree().quit(0 if ok else 2)


# --perf-log: 보이는 몸 메시 수 (chars/body.gd 의 drawn 중 조상까지 보이는 것)
func _body_meshes(n: Node) -> int:
	var c := 0
	if n is Node3D and not (n as Node3D).is_visible_in_tree():
		return 0
	if n.get("drawn") is Array:
		for dr in n.get("drawn"):
			if (dr.mi as MeshInstance3D).is_visible_in_tree() and (dr.mi as MeshInstance3D).layers != 0:
				c += 1
		return c
	for ch in n.get_children():
		c += _body_meshes(ch)
	return c


# --perf-log: 래그돌이 안 켜진 몸과 까닭 (chars/body.gd rag_why)
func _rag_why(n: Node, out: Dictionary) -> void:
	if n.get("rag_why") is String:
		if n.get("rag_why") != "":
			out[str(n.get("char_id")) + "#" + str(n.get("pid"))] = n.get("rag_why")
		return
	for ch in n.get_children():
		_rag_why(ch, out)


# --dump: 보이는 그림 노드 목록 (이름·종류·화면 사각형·색) — 메뉴에 남는 줄 같은 것 찾기
func _dump(n: Node, depth: int) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Node3D and not (n as Node3D).is_visible_in_tree():
		return
	var info := ""
	if n is Control:
		var c := n as Control
		info = " rect=%s" % str(c.get_global_rect())
		if n is ColorRect:
			info += " color=%s" % str((n as ColorRect).color)
	elif n is Node2D:
		info = " pos=%s" % str((n as Node2D).global_position)
	elif n is VisualInstance3D:
		info = " pos=%s aabb=%s" % [str((n as Node3D).global_position), str((n as VisualInstance3D).get_aabb().size)]
	elif n is CanvasLayer:
		info = " layer=%d" % (n as CanvasLayer).layer
	if info != "" or depth < 2:
		print("%s%s [%s]%s" % ["  ".repeat(depth), n.name, n.get_class(), info])
	for ch in n.get_children():
		_dump(ch, depth + 1)

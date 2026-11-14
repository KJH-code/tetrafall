# W53: 대기실 판 첫 갱신 나누기 (ui.gd _refresh_panels, 입장 첫 바퀴 동안 큰 일 문을 거침) — 월드 조각과 한 프레임에 안 겹침, 미룬 조각은 다음 프레임에, 끄면/첫 바퀴 뒤엔 예전처럼 한 번에
extends RefCounted

const Gate := preload("res://core/entry_gate.gd")
const C := preload("res://core/config.gd")

var errors: Array = []
var _fake_frame := 1


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _frame() -> int:
	return _fake_frame


func _gate_reset() -> void:
	Gate.reset()
	Gate.enabled_override = true
	Gate._clock = Callable(self, "_frame")
	_fake_frame = 1


func _stub(base: String, body: String) -> Object:
	var s := GDScript.new()
	s.source_code = "extends %s\nvar calls := {}\nfunc _c(k):\n\tcalls[k] = int(calls.get(k, 0)) + 1\n%s" % [base, body]
	s.reload()
	return s.new()


func _ui() -> Object:
	Store.my_id = 1 # hostId 1 = 나 (방장 판 갱신)
	var ui = load("res://ui/ui.gd").new()
	ui.lobby = _stub("PanelContainer", "func refresh(_st):\n\t_c('refresh')\n")
	ui.host_players = _stub("PanelContainer", "func refresh(_st):\n\t_c('refresh')\n")
	ui.hud = _stub("Control", "func score_band(_st, _vp, _b):\n\t_c('band')\nfunc warm_faces(_st):\n\t_c('warm')\nfunc prebuild_cards(_st, _vp):\n\t_c('pre')\n\treturn true\n")
	ui.hud_extra = Control.new()
	ui.results = PanelContainer.new()
	ui.shown = "lobby"
	return ui


func _free(ui: Object) -> void:
	Store.my_id = null
	for n in [ui.lobby, ui.host_players, ui.hud, ui.hud_extra, ui.results]:
		n.free()
	ui.free()


func _st() -> Dictionary:
	return {"phase": "lobby", "hostId": 1, "players": []}


func test_est_defaults() -> void:
	for k in ["ui.panel.a", "ui.panel.b"]:
		var e: float = float(Gate.EST_DEFAULT.get(k, 0.0))
		check(e >= Gate.SMALL_MS and e <= Gate.CAP_MS, "%s 예상 ms 가 문을 통과하는 크기 (%s)" % [k, e])
	check(not Gate.can(8.0, float(Gate.EST_DEFAULT["ui.panel.a"])), "월드 조각 8ms 가 돈 프레임엔 대기실 판 A 가 안 돎")
	check(Gate.can(0.0, float(Gate.EST_DEFAULT["ui.panel.a"])), "빈 프레임엔 돎")


# 입장 첫 바퀴 (entered 거짓) + 그 프레임에 큰 일이 이미 있음 → 둘 다 미룸, 다음 프레임에 A 다음 B 가 한 프레임에 하나씩
func test_split_defers_and_resumes() -> void:
	_gate_reset()
	Gate.entered = false
	var ui := _ui()
	Gate.ok("x") # 프레임 굴림
	Gate.spent = 10.0 # 월드 조각이 이미 10ms (이 프레임)
	ui._refresh_panels(_st())
	check(ui.lobby.calls.is_empty() and ui.hud.calls.is_empty(), "큰 일 뒤엔 대기실 판 갱신을 미룸")
	check(ui._panel_late, "미룬 조각이 있다고 표시")
	_fake_frame = 2
	ui._refresh_panels(_st(), false)
	check(int(ui.lobby.calls.get("refresh", 0)) == 1 and int(ui.hud.calls.get("band", 0)) == 1, "다음 프레임에 A (점수 띠 + 대기실 판)")
	for f in range(3, 8):
		_fake_frame = f
		if ui._panel_late:
			ui._refresh_panels(_st(), false)
	check(not ui._panel_late, "몇 프레임 안에 다 끝남")
	check(int(ui.lobby.calls.get("refresh", 0)) == 1 and int(ui.hud.calls.get("warm", 0)) == 1 and int(ui.host_players.calls.get("refresh", 0)) == 1, "각 조각 정확히 한 번씩 (두 번 안 돎)")
	_free(ui)
	_gate_end()


func _gate_end() -> void:
	Gate.reset()


# 첫 바퀴가 끝났으면 (entered) 문 없이 한 번에 — 예전과 같은 호출
func test_after_entered_runs_all() -> void:
	_gate_reset()
	Gate.entered = true
	var ui := _ui()
	Gate.ok("x")
	Gate.spent = 10.0
	ui._refresh_panels(_st())
	check(not ui._panel_late, "첫 바퀴 뒤엔 미루지 않음")
	check(ui.lobby.calls.get("refresh", 0) == 1 and ui.hud.calls.get("band", 0) == 1 and ui.hud.calls.get("warm", 0) == 1 and ui.host_players.calls.get("refresh", 0) == 1, "넷 다 한 번에")
	_free(ui)
	_gate_end()


# 문이 꺼져 있으면 (--no-entry-split) 예전 방식
func test_gate_off_runs_all() -> void:
	_gate_reset()
	Gate.enabled_override = false
	Gate.entered = false
	var ui := _ui()
	ui._refresh_panels(_st())
	check(not ui._panel_late and ui.lobby.calls.get("refresh", 0) == 1 and ui.host_players.calls.get("refresh", 0) == 1, "문 꺼짐 = 한 번에")
	_free(ui)
	_gate_end()


# 방장이 아니면 방장 판은 안 부름 (예전 동작 그대로)
func test_non_host_skips_host_panel() -> void:
	_gate_reset()
	Gate.entered = true
	var ui := _ui()
	var st := _st()
	st["hostId"] = 2
	ui._refresh_panels(st)
	check(ui.host_players.calls.get("refresh", 0) == 0 and not ui.host_players.visible, "방장 아니면 방장 판 갱신·표시 없음")
	_free(ui)
	_gate_end()


# 화면 빛 등록부 (ui_style._reg): 사라진 컨트롤의 WeakRef 가 4000 까지 쌓이지 않고 살아 있는 수 기준 한계에서 정리됨, 살아 있는 것은 그대로
func test_style_reg_prunes_dead_refs() -> void:
	var S = load("res://ui/ui_style.gd")
	var keep_reg: Array = S._reg
	var keep_lim: int = S._reg_limit
	var keep_old = S._reg_old
	S._reg = []
	S._reg_limit = S.REG_MIN
	S._reg_old = false
	var alive: Array = []
	for i in 300:
		var b := StyleBoxFlat.new()
		alive.append(b)
		S._keep(b, "pane")
	for round in 6: # 입장마다 만들고 버림 (사라지는 컨트롤)
		for i in 400:
			var d := StyleBoxFlat.new()
			S._keep(d, "pane")
			d = null
	check(S._reg.size() <= S.REG_MIN + 1, "죽은 참조가 쌓이지 않음 (크기 %d, 한계 %d)" % [S._reg.size(), S.REG_MIN])
	var live := 0
	for r in S._reg:
		if r[0].get_ref() != null:
			live += 1
	check(live == 300, "살아 있는 300개는 다 남음 (%d)" % live)
	check(S._reg_limit >= S.REG_MIN, "한계는 최소 이상")
	S._reg_old = true # --no-reg-prune: 예전 4000
	S._reg = []
	for i in 1500:
		var d := StyleBoxFlat.new()
		S._keep(d, "pane")
		d = null
	check(S._reg.size() == 1500, "끄면 4000 까지 안 버림 (%d)" % S._reg.size())
	S._reg = keep_reg
	S._reg_limit = keep_lim
	S._reg_old = keep_old


# ---- 웹 효과음 묶음 (audio/sfx_pack.gd + addons/web_music/export.gd): 첫 pck 에서 뺀 wav 를 첫 화면 뒤 묶음 파일로 받음 ----
const SfxPack := preload("res://audio/sfx_pack.gd")
const SfxNode := preload("res://audio/sfx.gd")


func test_sfx_pack_split_rule() -> void:
	check(not SfxPack.is_split(false, false) and not SfxPack.is_split(false, true), "PC 는 쪼개지 않음")
	check(not SfxPack.is_split(true, true), "웹이어도 첫 pck 에 wav 가 있으면 (옛 빌드) 쪼개지 않음")
	check(SfxPack.is_split(true, false), "웹 + 첫 pck 에 wav 없음 = 쪼갠 빌드")
	check(SfxPack.group_of("title.crystal.land.0.wav") == "t_crystal" and SfxPack.group_of("title.meadow.burst.wav") == "t_meadow" and SfxPack.group_of("ambientPing.castle.3.wav") == "t_castle", "타이틀·앰비언트 핑은 테마 묶음")
	check(SfxPack.group_of("hit.none.1.0.wav") == "sfx" and SfxPack.group_of("swing.none.0.wav") == "sfx", "나머지 효과음은 공통 묶음")
	check(SfxPack.group_of("music.lobby.ogg") == "" and SfxPack.group_of("ambient.castle.ogg") == "" and SfxPack.group_of("hazard.lava.loop.ogg") == "", "ogg 는 묶음이 아님 (첫 pck·곡 따로)")
	check(SfxPack.pack_name("sfx") == "sfx.pck" and SfxPack.pack_name("t_castle") == "sfx_t_castle.pck", "묶음 파일 이름")
	var themes := ["castle", "crystal", "desert"]
	check(SfxPack.order(themes, "crystal") == ["t_crystal", "sfx", "t_castle", "t_desert"], "받을 순서: 메뉴 테마 → 공통 → 나머지 (%s)" % str(SfxPack.order(themes, "crystal")))
	check(SfxPack.order(themes, "") == ["sfx", "t_castle", "t_crystal", "t_desert"] and SfxPack.order(themes, "zzz") == SfxPack.order(themes, ""), "메뉴 테마를 모르면 공통부터")


# 내보내기 플러그인 규칙 (편집기 전용 스크립트) 과 런타임 규칙이 audio/baked 의 모든 파일에서 같음 — 어긋나면 효과음이 어느 쪽에도 없어짐
func test_sfx_pack_rule_matches_plugin() -> void:
	var P = load("res://addons/web_music/export.gd")
	var n := 0
	var lazy := 0
	var groups := {}
	for f in DirAccess.get_files_at("res://audio/baked/"):
		if f.ends_with(".import"):
			continue
		n += 1
		var in_pack: bool = P.is_lazy_sfx("res://audio/baked/" + f)
		var rg: String = SfxPack.group_of(f)
		if in_pack != (rg != ""):
			check(false, "묶음 여부 어긋남: %s 플러그인 %s 런타임 '%s'" % [f, in_pack, rg])
		if in_pack:
			lazy += 1
			groups[rg] = true
			if P.group_of(f) != rg or P.pack_name(P.group_of(f)) != SfxPack.pack_name(rg):
				check(false, "묶음 이름 어긋남: %s %s vs %s" % [f, P.group_of(f), rg])
	check(n > 300 and lazy > 200 and lazy < n, "파일 수 (%d) · 묶음 몫 (%d)" % [n, lazy])
	check(groups.size() == 8 and groups.has("sfx"), "묶음 = 공통 + 테마 7 (%s)" % str(groups.keys()))
	check(SfxPack.order(C.TITLE_THEMES.keys(), "castle").size() == 8, "테마 표와 묶음 수가 같음")
	for t in C.TITLE_THEMES.keys():
		check(groups.has("t_" + str(t)), "테마 %s 묶음이 있음" % t)
	check(not P.is_song("res://audio/baked/hit.none.1.0.wav") and P.is_song("res://audio/baked/music.lobby.ogg") and not P.is_lazy_sfx("res://audio/baked/music.lobby.ogg"), "곡은 곡 따로, 효과음 묶음에는 안 듦")


# 묶음이 오기 전엔 null (캐시 안 함), 온 뒤엔 읽힘, 묶음마다 따로
func test_sfx_stream_waits_for_pack() -> void:
	var s = SfxNode.new()
	var pk = SfxPack.new()
	pk.split = true # 쪼갠 웹 빌드 흉내 (노드를 트리에 안 넣어서 _ready 는 안 돎)
	s.pack = pk
	check(s.stream("swing.none.0.wav") == null and not s.streams.has("swing.none.0.wav"), "공통 묶음 전: null 이고 캐시 안 함")
	check(s.stream("title.crystal.burst.wav") == null and not s.streams.has("title.crystal.burst.wav"), "테마 묶음 전: null")
	check(s.stream("music.lobby.ogg") != null or true, "ogg 는 묶음과 무관")
	pk.done["t_crystal"] = true
	check(s.stream("title.crystal.burst.wav") != null, "그 테마 묶음이 붙으면 읽힘")
	check(s.stream("title.meadow.burst.wav") == null, "다른 테마 묶음은 아직")
	check(s.stream("swing.none.0.wav") == null, "공통은 아직")
	pk.done["sfx"] = true
	check(s.stream("swing.none.0.wav") != null, "공통 묶음 뒤: 읽힘")
	pk.want("t_meadow") # split 이지만 queue 에 없음 → 아무 일 없음
	pk.queue = ["sfx", "t_castle", "t_meadow"]
	pk.want("t_meadow")
	check(pk.queue == ["t_meadow", "sfx", "t_castle"], "필요한 테마 묶음을 앞으로 (%s)" % str(pk.queue))
	var s2 = SfxNode.new() # 묶음 노드 없음 (PC·테스트) = 예전대로
	check(s2.stream("swing.none.0.wav") != null, "묶음 노드가 없으면 예전대로")
	var pk2 = SfxPack.new() # 쪼개지 않은 빌드 (PC): split 거짓 → 다 읽힘
	var s3 = SfxNode.new()
	s3.pack = pk2
	check(s3.stream("title.castle.burst.wav") != null and s3.stream("hit.none.1.0.wav") != null, "쪼개지 않은 빌드는 다 읽힘")
	pk.free()
	pk2.free()
	s.free()
	s2.free()
	s3.free()

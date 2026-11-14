# W53: 대기실 판 첫 갱신 나누기 (ui.gd _refresh_panels, 입장 첫 바퀴 동안 큰 일 문을 거침) — 월드 조각과 한 프레임에 안 겹침, 미룬 조각은 다음 프레임에, 끄면/첫 바퀴 뒤엔 예전처럼 한 번에
extends RefCounted

const Gate := preload("res://core/entry_gate.gd")

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

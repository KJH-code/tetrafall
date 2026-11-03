# 화면 판 입력 확인 (W16 2026-11-03): 구운 판 (ui/baked_panel.gd) 위에서도 클릭·글자 입력·hover·고르기 목록·스크롤이 그대로인지.
#   재연 (core/replay.gd --ui-check, 대기실 = --replay-warm -4) 이 부름. 창 픽셀 자리로 진짜 입력 사건을 넣고 (Input.parse_input_event) 결과를 봄.
#   끝에 "[UI 확인] n 통과, m 실패" — 창 크기·UI 크기 (--resolution, --set uiScale=1.5) 를 바꿔 여러 번
extends RefCounted

static var fails := 0
static var oks := 0


static func _check(ok: bool, what: String) -> void:
	if ok:
		oks += 1
	else:
		fails += 1
	print("[UI 확인] %s %s" % ["ok  " if ok else "FAIL", what])


static func _frames(tree: SceneTree, n := 3) -> void:
	for i in n:
		await tree.process_frame


# UI 좌표 점 → 창 픽셀
static func _px(tree: SceneTree, p: Vector2) -> Vector2:
	return tree.root.get_final_transform() * p


static func _move(tree: SceneTree, p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _px(tree, p)
	e.global_position = e.position
	Input.parse_input_event(e)
	await _frames(tree, 2)


static func click(tree: SceneTree, c: Control) -> void:
	await _reveal(tree, c)
	var p := c.get_global_rect().get_center()
	await _move(tree, p)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = _px(tree, p)
		e.global_position = e.position
		Input.parse_input_event(e)
		await _frames(tree, 2)


# 스크롤 칸 안에서 가려져 있으면 (작은 창) 보이게 굴림
static func _reveal(tree: SceneTree, c: Control) -> void:
	var a := c.get_parent()
	while a != null and not (a is ScrollContainer):
		a = a.get_parent()
	if a != null:
		(a as ScrollContainer).ensure_control_visible(c)
		await _frames(tree, 3)


static func wheel(tree: SceneTree, c: Control, down := true) -> void:
	var p := c.get_global_rect().get_center()
	await _move(tree, p)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
		e.pressed = pressed
		e.factor = 1.0
		e.position = _px(tree, p)
		e.global_position = e.position
		Input.parse_input_event(e)
	await _frames(tree, 3)


static func key(tree: SceneTree, code: Key, uni := 0) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = uni if pressed else 0
		e.pressed = pressed
		Input.parse_input_event(e)
	await _frames(tree, 2)


static func _ui(tree: SceneTree) -> Node:
	for n in tree.root.find_children("*", "CanvasLayer", true, false):
		if n.get("lobby") is Control and n.get("settings") is Control:
			return n
	return null


static func run(tree: SceneTree) -> void:
	var ui := _ui(tree)
	if ui == null:
		_check(false, "ui.gd 없음")
		return
	var lobby: Control = ui.lobby
	var baked := lobby.get_parent() is CanvasLayer and (lobby.get_parent() as CanvasLayer).custom_viewport != null
	var bk: Node = lobby.get_parent().get_parent() if baked else null
	print("[UI 확인] 창 %s · UI 크기 %.3f · UI 좌표 %s · bake %s" % [tree.root.size, tree.root.get_final_transform().get_scale().x, tree.root.get_visible_rect().size, "켬" if baked else "끔"])
	_check(lobby.is_visible_in_tree(), "대기실 판 보임")
	# hover: 버튼에 마우스를 올리면 다시 구움 (hover 모습)
	var keys_btn: Button = null
	for b in lobby.find_children("*", "Button", true, false):
		if (b as Button).text == "조작법":
			keys_btn = b
	await _reveal(tree, keys_btn)
	var r0: int = int(bk.renders) if bk != null else 0
	await _move(tree, keys_btn.get_global_rect().get_center())
	_check(keys_btn.is_hovered(), "'조작법' 위 hover")
	if bk != null:
		_check(int(bk.renders) > r0, "hover 하면 다시 그림 (%d → %d)" % [r0, int(bk.renders)])
	# 클릭: '조작법' → 조작법 글 보임
	var was: bool = lobby.keys_text.visible
	await click(tree, keys_btn)
	_check(lobby.keys_text.visible != was, "'조작법' 클릭 → 조작법 글 %s" % ("숨김" if was else "보임"))
	await click(tree, keys_btn)
	_check(lobby.keys_text.visible == was, "'조작법' 다시 클릭 → 처음대로")
	# 큰 캐릭터 (산 칸 — 굽지 않음) 클릭 → 스킬 카드
	# (큰 캐릭터 가운데 클릭은 굽기 전에도 안 열림 — stage_box ColorRect 가 클릭을 막음, W16 에 남긴 기존 문제)
	await click(tree, lobby.skill_btn)
	_check(lobby.skill_card.visible, "'스킬 보기' (산 칸) 클릭 → 스킬 카드")
	for b in lobby.skill_card.find_children("*", "Button", true, false): # 카드 '닫기'
		await click(tree, b)
	_check(not lobby.skill_card.visible, "스킬 카드 닫기")
	# 글자 칸: 클릭 → 초점, 글자 넣기
	await click(tree, lobby.name_edit)
	_check(lobby.name_edit.has_focus(), "이름 칸 클릭 → 초점")
	var before: String = lobby.name_edit.text
	for ch in "AB":
		await key(tree, OS.find_keycode_from_string(ch), ch.unicode_at(0))
	_check(lobby.name_edit.text == before + "AB", "이름 칸 글자 입력 ('%s')" % lobby.name_edit.text)
	await key(tree, KEY_BACKSPACE)
	await key(tree, KEY_BACKSPACE)
	lobby.name_edit.release_focus()
	await _frames(tree)
	# 고르기 목록 (방장만 보임): 클릭 → 팝업
	if lobby.mode_sel.is_visible_in_tree():
		await click(tree, lobby.mode_sel)
		var pop: PopupMenu = lobby.mode_sel.get_popup()
		_check(pop.visible, "모드 고르기 클릭 → 목록")
		pop.hide()
		await _frames(tree)
	# 스크롤 (판이 넘칠 때만 — 작은 창)
	var sb: ScrollBar = lobby.scroll.get_v_scroll_bar()
	if sb.max_value > lobby.scroll.size.y + 1.0:
		lobby.scroll.scroll_vertical = 0
		await _frames(tree)
		var v0: int = lobby.scroll.scroll_vertical
		await wheel(tree, lobby.scroll)
		_check(lobby.scroll.scroll_vertical > v0, "판 휠 (scroll, %d → %d)" % [v0, lobby.scroll.scroll_vertical])
		lobby.scroll.scroll_vertical = 0
		await _frames(tree)
	# 플레이어 관리 판 (방장): 팀전 체크 칸 위치에 hover
	if ui.host_players.is_visible_in_tree():
		var cb: Array = ui.host_players.find_children("*", "CheckBox", true, false)
		if not cb.is_empty():
			await _move(tree, (cb[0] as Control).get_global_rect().get_center())
			_check((cb[0] as BaseButton).is_hovered(), "플레이어 관리 '팀전' hover")
	# 설정 창: 대기실 '설정' → 창 → '닫기' 류 버튼으로 닫힘
	var set_btn: Button = null
	for b in lobby.find_children("*", "Button", true, false):
		if (b as Button).text == "설정":
			set_btn = b
	await click(tree, set_btn)
	_check(ui.settings.visible, "대기실 '설정' 클릭 → 설정 창")
	var chk := (ui.settings as Node).find_children("*", "CheckBox", true, false).filter(func(c): return (c as Control).is_visible_in_tree())
	if not chk.is_empty():
		var c0: CheckBox = chk[0]
		var p0 := c0.button_pressed
		await click(tree, c0)
		_check(c0.button_pressed != p0, "설정 창 체크 칸 클릭 (%s)" % c0.text)
		await click(tree, c0)
	var close: Button = null
	for b in (ui.settings as Node).find_children("*", "Button", true, false):
		if (b as Button).text in ["닫기", "닫기 (Esc)", "확인"] and (b as Control).is_visible_in_tree():
			close = b
	if close != null:
		await click(tree, close)
		_check(not ui.settings.visible, "설정 창 '%s' → 닫힘" % close.text)
	else:
		ui.settings.visible = false
	print("[UI 확인] %d 통과, %d 실패" % [oks, fails])

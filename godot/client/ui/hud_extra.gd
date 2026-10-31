# 판 HUD 나머지 (JS main.js·index.html 에서 빠져 있던 것 — 2026-10-31 JS 대 고도 대조): hud.gd 위에 겹쳐 그림 (ui.gd 가 hud 와 같이 보이게).
# 위: 배너 (조종권·블록 마스터) · 압사 경고 '머리 위 블록!' · 알림 (toasts) · 다음 조종권·아이템 시계 / 가운데: 승리 큰 글씨 · 콤보 'N HIT!' · 'COUNTER!' ·
# 히트마커 · 경직 'STUN' + 붉은 테두리 · 화면 번쩍 · '화면을 클릭하면 조작 시작' · 이모트 바퀴 · 도움말 (H 누르는 동안) /
# 아래: 버프 줄 · 아이템 칸 · R 못 씀 흔들림·이유 · 갈고리 장전 탄 · 대포수 탄 3칸 · 조준점 색 (든 아이템)
extends Control

const C := preload("res://core/config.gd")
const S := preload("res://ui/ui_style.gd")
const Keys := preload("res://core/keys.gd")
const Coords := preload("res://core/coords.gd")

const ITEM_KO := {"control": "조종권", "knockback": "투사체", "jump": "점프력 상승", "ghost": "유령화", "brick": "설치 블록", "bomb": "폭탄", "speed": "이속 증가"}
const TEAM_KO := {"red": "빨강", "blue": "파랑"}
const TEAM_MAIN := {"red": Color("ff5a4a"), "blue": Color("4aa8ff")}
const ULT_FAIL_TEXT := {"noBlock": "블록 없음", "noSpace": "자리 없음", "busy": "사용 중", "noTarget": "대상 없음"}
const TIMER_LOOK := {"control": [Color("20e0e0"), "조종권"], "power": [Color("ffb040"), "아이템"]}

var hud: Control # hud.gd (아래 판·F·R 칸 자리를 읽음)
var top_box: VBoxContainer
var timers: HBoxContainer
var timer_labels := {}
var timer_full := {"control": null, "power": null}
var timer_prev := {"control": null, "power": null}
var banner: Label
var danger: Label
var toasts: VBoxContainer
var win_big: Label
var win_until := -1.0
var combo: Label
var counter: Label
var hitmarker: Control
var hit_until := -1.0
var stun: Label
var vignette: TextureRect
var flash: ColorRect
var center: Label
var wheel: Control
var wheel_items: Array[Label] = []
var help: Label
var bottom: VBoxContainer
var buffs: Label
var item_slot: Label
var ammo: Control
var balls: Control
var crosshair: Control
var cross_kind := "" # "" | "armed" | "brick" | "bomb"
var ult_fail_until := -1.0
var ult_fail_text := ""
var shake_until := -1.0
var my_streak := 0
var was_alive := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 화면 번쩍 (JS flashScreen) · 경직 붉은 테두리 (#vignette, inset 140px 붉은 빛)
	vignette = _edge_rect(Color(1, 0, 0, 0.55))
	vignette.modulate.a = 0.0
	add_child(vignette)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1, 1, 1, 0)
	add_child(flash)
	# 위 묶음 (#top): 시계 · 배너 · 경고 · 알림 — 점수 띠 아래 가운데
	top_box = VBoxContainer.new()
	top_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_box.add_theme_constant_override("separation", 6)
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_box)
	timers = HBoxContainer.new()
	timers.alignment = BoxContainer.ALIGNMENT_CENTER
	timers.add_theme_constant_override("separation", 8)
	top_box.add_child(timers)
	for k in ["control", "power"]:
		var l := _box_label(15, Color(0.03, 0.05, 0.1, 0.75))
		l.visible = false
		var sb: StyleBoxFlat = l.get_theme_stylebox("normal")
		sb.content_margin_left = 30 # 왼쪽 시계 원 (JS .pie conic-gradient)
		var kk: String = k
		l.draw.connect(func():
			var ctr := Vector2(17, l.size.y / 2.0)
			var fr := float(l.get_meta("frac", 0.0))
			l.draw_circle(ctr, 6.5, Color(1, 1, 1, 0.2))
			if fr > 0.0:
				var pts := PackedVector2Array([ctr])
				for i in 25:
					var a := -PI / 2.0 + TAU * fr * float(i) / 24.0
					pts.append(ctr + Vector2(cos(a), sin(a)) * 6.5)
				l.draw_colored_polygon(pts, TIMER_LOOK[kk][0]))
		timers.add_child(l)
		timer_labels[k] = l
	banner = _box_label(19, Color("0e8aa0"))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	banner.visible = false
	top_box.add_child(banner)
	danger = _box_label(24, Color("e0300c"))
	danger.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	danger.visible = false
	top_box.add_child(danger)
	toasts = VBoxContainer.new()
	toasts.add_theme_constant_override("separation", 6)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_box.add_child(toasts)
	# 가운데 글자들
	win_big = _label(74)
	win_big.visible = false
	add_child(win_big)
	combo = _label(42, S.ACCENT)
	combo.visible = false
	add_child(combo)
	counter = _label(32, Color("5ad0ff"))
	counter.text = "COUNTER!"
	counter.visible = false
	add_child(counter)
	stun = _label(46, S.HOT)
	stun.text = "STUN"
	stun.visible = false
	add_child(stun)
	center = _label(18)
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.09, 0.06, 0.17, 0.88)
	cs.skew = Vector2(S.SKEW * 0.5, 0)
	cs.content_margin_left = 22
	cs.content_margin_right = 18
	cs.content_margin_top = 6
	cs.content_margin_bottom = 8
	center.add_theme_stylebox_override("normal", cs)
	center.visible = false
	add_child(center)
	hitmarker = Control.new()
	hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hitmarker.size = Vector2(30, 30)
	hitmarker.draw.connect(func():
		var c := hitmarker.size / 2.0
		for a in [PI / 4.0, -PI / 4.0]:
			var d := Vector2(cos(a), sin(a)) * 15.0
			hitmarker.draw_line(c - d, c + d, Color(0, 0, 0, 0.5), 6.0)
			hitmarker.draw_line(c - d, c + d, Color.WHITE, 4.0))
	hitmarker.visible = false
	add_child(hitmarker)
	crosshair = Control.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.size = Vector2(40, 40)
	crosshair.draw.connect(_draw_cross)
	crosshair.visible = false
	add_child(crosshair)
	# 이모트 바퀴 (#emote-wheel): 300px 어두운 원 + 칸 (고른 칸은 노랑)
	wheel = Control.new()
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.size = Vector2(300, 300)
	wheel.draw.connect(func(): wheel.draw_circle(wheel.size / 2.0, 150.0, Color(0, 0, 0, 0.45)))
	wheel.visible = false
	add_child(wheel)
	var n: int = C.EMOTE_NAMES.size()
	for i in n:
		var l := _box_label(18, Color(0.03, 0.05, 0.1, 0.75))
		l.text = str(C.EMOTE_NAMES[i])
		wheel.add_child(l)
		wheel_items.append(l)
	var hint := _label(13, Color("ccccdd"))
	hint.text = "마우스로 고르고\n%s 를 놓기" % Keys.key_label(str(PlayerInput.binds.get("emote", "KeyG")))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wheel.add_child(hint)
	hint.position = Vector2(150, 150) - Vector2(60, 18)
	hint.size = Vector2(120, 36)
	# 도움말 (#help): 오른쪽 위, H 누르는 동안
	help = _label(12, S.DIM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help.visible = false
	add_child(help)
	# 아래 (#bottom): 버프 줄 · 아이템 칸 (F·R 칸은 hud.gd)
	bottom = VBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 4)
	add_child(bottom)
	buffs = _label(14)
	buffs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(buffs)
	item_slot = _box_label(15, Color(0.03, 0.05, 0.1, 0.78))
	item_slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(item_slot)
	ammo = Control.new()
	ammo.size = Vector2(16, 16)
	ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo.draw.connect(func():
		var loaded: bool = bool(Store.me().get("loaded", false))
		if loaded:
			ammo.draw_circle(Vector2(8, 8), 8.0, Color("ffc030"))
		ammo.draw_arc(Vector2(8, 8), 6.5, 0, TAU, 20, Color("fff0a0") if loaded else Color("888888"), 3.0))
	ammo.visible = false
	add_child(ammo)
	balls = Control.new()
	balls.size = Vector2(80, 20)
	balls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	balls.draw.connect(_draw_balls)
	balls.visible = false
	add_child(balls)
	Store.game_event.connect(_on_event)
	Store.state_changed.connect(_on_state)
	PlayerInput.ui_action.connect(func(id: String, down: bool):
		if id == "help":
			help.visible = down
			help.text = _help_text())
	PlayerInput.wheel_changed.connect(_on_wheel)


func _label(size: int, col: Color = S.TEXT) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 14))
	return l


func _box_label(size: int, bg: Color) -> Label:
	var l := _label(size)
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.skew = Vector2(S.SKEW * 0.6, 0)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 4
	s.content_margin_bottom = 5
	l.add_theme_stylebox_override("normal", s)
	return l


# 화면 가장자리 빛 (CSS inset box-shadow): 가운데 투명 → 끝 col
func _edge_rect(col: Color) -> TextureRect:
	var t := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	var gr := Gradient.new()
	gr.set_color(0, Color(col.r, col.g, col.b, 0.0))
	gr.set_color(1, col)
	gr.set_offset(0, 0.6)
	gt.gradient = gr
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _now() -> float:
	return float(Time.get_ticks_msec())


func _name(p: Dictionary) -> String:
	return str(p.get("nick", "")) if str(p.get("nick", "")) != "" else str(p.get("name", "?"))


func _color(p: Dictionary) -> Color:
	var st := Store.state
	if st.get("teamMode", false) and TEAM_MAIN.has(str(p.get("team", ""))):
		return TEAM_MAIN[str(p.team)]
	return Coords.color(C.PLAYER_PALETTE[int(p.get("color", p.get("slot", 0))) % C.PLAYER_PALETTE.size()])


func _practice() -> bool:
	return bool(Store.room.get("practice", false))


# ---------- 알림·번쩍·콤보 (JS toast·flashScreen·showCombo·showCounter·showHitmarker) ----------
func toast(text: String, kind := "") -> void:
	var bg := Color(0.03, 0.05, 0.1, 0.82)
	if kind == "me":
		bg = Color("b53a10")
	elif kind == "good":
		bg = Color("13804a")
	var l := _box_label(17, bg)
	l.text = text
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toasts.add_child(l)
	while toasts.get_child_count() > 4:
		toasts.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(C.TOAST_MS / 1000.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.45)
	tw.tween_callback(l.queue_free)


func flash_screen(col: Color) -> void:
	flash.color = col
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.4)


func show_combo(n: int, taken: bool, finish: bool) -> void:
	combo.text = "%d HIT%s" % [n, "!!" if finish else "!"]
	combo.add_theme_color_override("font_color", Color("ff5a3a") if taken else S.ACCENT)
	combo.visible = true
	combo.set_meta("until", _now() + C.COMBO_TEXT_MS)


func show_counter(taken: bool) -> void:
	counter.add_theme_color_override("font_color", Color("ff5a3a") if taken else Color("5ad0ff"))
	counter.visible = true
	counter.scale = Vector2(1.4, 1.4)
	counter.create_tween().tween_property(counter, "scale", Vector2.ONE, 0.18)
	counter.set_meta("until", _now() + C.COUNTER_TEXT_MS)


func show_hitmarker() -> void:
	hitmarker.visible = true
	hitmarker.modulate.a = 1.0
	hit_until = _now() + 120.0


func _on_event(e: Dictionary) -> void:
	var me_id = Store.my_id
	match str(e.get("type", "")):
		"ultFail": # 내 R 을 못 씀: R 칸이 빨갛게 흔들림 + 짧은 이유
			if e.get("who") == me_id:
				ult_fail_text = str(ULT_FAIL_TEXT.get(str(e.get("reason", "")), "못 씀"))
				ult_fail_until = _now() + C.ULT_FAIL_MS
				shake_until = _now() + C.ULT_FAIL_SHAKE_MS
		"aim": # 처형 사격 대상이면 붉게
			if (e.get("targets", []) as Array).has(me_id):
				flash_screen(Color(1, 0, 0, 0.22))
		"streak":
			if e.get("who") == me_id:
				my_streak = int(e.n)
				show_combo(my_streak, false, false)
		"counter":
			if e.get("by") == me_id or e.get("target") == me_id:
				show_counter(e.get("target") == me_id)
		"practiceReset":
			if e.get("who") == me_id:
				flash_screen(Color(1, 1, 1, 0.25))
		"combo":
			if e.get("target") == me_id:
				show_combo(int(e.n), true, bool(e.get("finish", false)))
			elif e.get("by") == me_id and e.get("finish", false):
				show_combo(maxi(my_streak, int(e.n)), false, true)
		"song":
			if (e.get("targets", []) as Array).has(me_id):
				flash_screen(Color(1, 0.416, 0.835, 0.25))
		"zombie":
			if e.get("who") == me_id:
				toast("마스터 편이 됐다! 하늘에서 블록으로 남은 사람을 깔아라", "good")
			else:
				toast("%s 마스터 편으로" % _name(Store.player(e.get("who"))))
		"respawn":
			if e.get("who") == me_id and not _practice():
				toast("부활! %d초 무적" % int(C.KILLS_SHIELD_MS / 1000.0), "good")
		"hit":
			if e.get("target") == me_id and e.get("ok", false):
				flash_screen(Color(1, 0.824, 0, 0.45))
			elif e.get("by") == me_id and e.get("ok", false):
				show_hitmarker()
		"mark":
			if e.get("by") == me_id:
				show_hitmarker()
		"pickup":
			if e.get("who") == me_id:
				toast("%s!" % str(ITEM_KO.get(str(e.get("item", "")), str(e.get("item", "")))), "good")
		"controlStart":
			if e.get("who") != me_id:
				toast("%s 블록 조종 시작. 그림자를 조심!" % _name(Store.player(e.get("who"))))
		"lava":
			toast("용암! 위로", "me")
		"clear":
			toast("층 클리어!")


# 판 끝 승리 큰 글씨 (JS onState showBig small): 결과 표가 나올 때까지 위쪽에
func _on_state(st: Dictionary, prev: Dictionary) -> void:
	var p := Store.me()
	if prev.get("phase") == "playing" and st.get("phase") == "over" and not _practice():
		var w := Store.player(st.round.get("winnerId"))
		var wt = st.round.get("winnerTeam")
		var ids: Array = st.round.get("winnerIds", [])
		var was_master = null
		for x in prev.get("players", []):
			if x.get("master", false) and not x.get("zombie", false):
				was_master = x
		var text := "무승부"
		var col := Color("dddddd")
		if wt != null:
			text = "%s팀 승리!" % TEAM_KO.get(str(wt), str(wt))
			col = TEAM_MAIN.get(str(wt), S.ACCENT)
		elif ids.size() > 1:
			text = "생존자 승리!" if st.get("mode") == "master" else "공동 승리!"
			col = Color("ffe14a")
		elif not w.is_empty() and was_master != null and was_master.id == w.id:
			text = "마스터 %s 승리!" % _name(w)
			col = _color(w)
		elif not w.is_empty() and st.get("mode") == "master":
			text = "%s 혼자 버팀!" % _name(w)
			col = _color(w)
		elif not w.is_empty():
			text = "%s 승리!" % _name(w)
			col = _color(w)
		win_big.text = text
		win_big.add_theme_color_override("font_color", col)
		win_until = _now() + C.WIN_BANNER_MS
	if st.get("phase") == "playing" and not p.is_empty() and not p.get("alive", true) and was_alive:
		flash_screen(Color(1, 0, 0, 0.45))
	if not p.is_empty():
		was_alive = bool(p.get("alive", true))
	if st.get("phase") != "over":
		win_until = -1.0


func _on_wheel(pick: int) -> void:
	wheel.visible = pick != -2
	if pick == -1:
		# 바퀴를 열 때: 전용 도발 칸 이름 = 내 캐릭터 (바드는 지금 폼)
		var me := Store.me()
		var look := str(me.get("char", ""))
		var bard = me.get("bard")
		if look == "bard" and bard is Dictionary and bard.get("form") == "metal":
			look = "metal"
		wheel_items[int(C.EMOTE_CHAR)].text = str(C.EMOTE_CHAR_NAMES.get(look, C.EMOTE_NAMES[int(C.EMOTE_CHAR)]))
	for i in wheel_items.size():
		var on := i == pick
		var s := StyleBoxFlat.new()
		s.bg_color = Color("ffd23a") if on else Color(0.03, 0.05, 0.1, 0.75)
		s.skew = Vector2(S.SKEW * 0.6, 0)
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		wheel_items[i].add_theme_stylebox_override("normal", s)
		wheel_items[i].add_theme_color_override("font_color", Color("171b2c") if on else S.TEXT)


func _help_text() -> String:
	var b: Dictionary = PlayerInput.binds
	var k := func(id): return Keys.key_label(str(b.get(id, "")))
	var items := "%s 든 아이템 쓰기 (하나만) · %s 1×2 방향 · " % [k.call("item"), Keys.group_label(b, ["rotL", "rotR"])] if bool(Store.state.get("itemsEnabled", C.ITEMS_ENABLED)) else ""
	return "%s 이동 · %s 점프·2단 점프 · %s 대시 · %s 평타 · %s 스킬 · %s 필살기 · %s 1인칭↔3인칭\n%s%s 이모트\n블록 마스터: %s 블록 이동 · %s 회전 · %s 하드드롭 · 키는 설정에서 바꿈" % [
		Keys.group_label(b, ["fwd", "left", "back", "right"]), k.call("jump"), k.call("dash"), k.call("attack"), k.call("skill"), k.call("ult"), k.call("view"),
		items, k.call("emote"), Keys.group_label(b, ["pieceUp", "pieceDown", "pieceLeft", "pieceRight"]), Keys.group_label(b, ["rotL", "rotR"]), k.call("drop")]


func _piece_keys() -> String:
	var b: Dictionary = PlayerInput.binds
	var t := "%s 이동 · %s 회전 · %s 낙하" % [Keys.group_label(b, ["pieceUp", "pieceDown", "pieceLeft", "pieceRight"]), Keys.group_label(b, ["rotL", "rotR"]), Keys.key_label(str(b.get("drop", "")))]
	if bool(C.SKY_VIEW.get("oblique", false)):
		t += " · %s 시점" % Keys.group_label(b, ["viewL", "viewR"])
	return t


func _fmt(ms: float) -> String:
	var s := int(ceil(ms / 1000.0))
	return "%d:%02d" % [s / 60, s % 60]


# ---------- 매 프레임 (ui.gd 가 판 화면일 때 부름) ----------
func refresh(st: Dictionary) -> void:
	var vp := get_viewport_rect().size
	var now := _now()
	var p := Store.me()
	var playing: bool = st.get("phase") == "playing"
	var alive: bool = not p.is_empty() and bool(p.get("alive", false))
	top_box.position = Vector2((vp.x - top_box.size.x) / 2.0, 62)
	top_box.size.x = minf(vp.x - 40, 760)
	_item_timers(st)
	_banner(st, p)
	# 압사 경고: 내 머리 위로 떨어지는 블록이 곧 깔 때 (서버가 계산한 남은 시간)
	var dg = p.get("danger") if alive and playing else null
	danger.visible = dg != null
	if dg != null:
		danger.text = "머리 위 블록!   %.1f초" % (float(dg) / 1000.0)
	# 승리 큰 글씨: 결과 표 전까지 (View.victory_stage — slow·closeup 동안)
	var stage := str(View.victory_stage)
	win_big.visible = st.get("phase") == "over" and win_until > 0 and (now < win_until or stage in ["slow", "closeup"])
	win_big.position = Vector2((vp.x - win_big.size.x) / 2.0, vp.y * 0.15 - win_big.size.y / 2.0)
	# 콤보·카운터·히트마커 시간
	if combo.visible and now > float(combo.get_meta("until", 0.0)):
		combo.visible = false
	if counter.visible and now > float(counter.get_meta("until", 0.0)):
		counter.visible = false
	combo.position = Vector2(vp.x * 0.62, vp.y * 0.44)
	counter.position = Vector2(vp.x * 0.62, vp.y * 0.37)
	counter.pivot_offset = counter.size / 2.0
	if hitmarker.visible:
		hitmarker.modulate.a = 1.0 if now < hit_until else maxf(0.0, 1.0 - (now - hit_until) / 150.0)
		if now > hit_until + 150.0:
			hitmarker.visible = false
	hitmarker.position = vp / 2.0 - hitmarker.size / 2.0
	# 경직
	var show_me: bool = alive and not p.get("master", false) and st.get("phase") in ["playing", "countdown"]
	var stunned: bool = show_me and bool(p.get("stunned", false))
	stun.visible = stunned
	stun.position = Vector2((vp.x - stun.size.x) / 2.0, vp.y / 2.0 + 30)
	vignette.modulate.a = move_toward(vignette.modulate.a, 1.0 if stunned else 0.0, get_process_delta_time() / 0.15)
	# 조준점 (든 아이템에 따라 색)
	var input_on: bool = show_me and PlayerInput.locked
	crosshair.visible = input_on and not p.get("controlling", false)
	var held := str(p.get("held", ""))
	cross_kind = "armed" if held == "knockback" else ("brick" if held == "brick" else ("bomb" if held == "bomb" else ""))
	crosshair.position = vp / 2.0 - crosshair.size / 2.0
	crosshair.queue_redraw()
	# 가운데 안내: 판 중 마우스가 안 잡혀 있으면 (관전·카운트다운 빼고)
	var spectating: bool = not p.is_empty() and not alive and playing
	var center_text := ""
	if st.get("phase") in ["playing", "countdown"] and not spectating and st.get("phase") != "countdown" and not PlayerInput.locked and not p.is_empty():
		center_text = "화면을 클릭하면 조작 시작"
	center.text = center_text
	center.visible = center_text != ""
	var sky: bool = str(View.mode) == "sky"
	center.position = Vector2((vp.x - center.size.x) / 2.0, (vp.y - 150 - center.size.y) if sky else (vp.y * 0.28 - center.size.y / 2.0))
	# 이모트 바퀴·도움말 자리
	wheel.position = vp / 2.0 - wheel.size / 2.0
	var n := wheel_items.size()
	for i in n:
		var a := -PI / 2.0 + TAU * float(i) / float(n)
		var l := wheel_items[i]
		l.position = Vector2(150, 150) + Vector2(cos(a), sin(a)) * 108.0 - l.size / 2.0
	help.position = Vector2(vp.x - help.size.x - 12, 40)
	# 아래: 버프·아이템 칸, 갈고리 탄·대포수 탄 (F·R 칸 옆)
	_bottom(st, p, show_me, vp)


func _item_timers(st: Dictionary) -> void:
	var t: Dictionary = st.get("itemTimers", {}) if st.get("itemTimers") is Dictionary else {}
	for k in timer_labels:
		var left = t.get(k)
		var l: Label = timer_labels[k]
		if left != null and (timer_prev[k] == null or float(left) > float(timer_prev[k])):
			timer_full[k] = maxf(float(left), 1.0)
		timer_prev[k] = left
		l.visible = left != null and st.get("phase") == "playing" and (k != "power" or bool(st.get("itemsEnabled", C.ITEMS_ENABLED)))
		if left == null:
			continue
		var look: Array = TIMER_LOOK[k]
		var frac := 1.0 - minf(1.0, float(left) / float(timer_full[k]))
		l.text = "%s %ds" % [look[1], int(ceil(float(left) / 1000.0))]
		l.set_meta("frac", frac)
		l.queue_redraw()
		l.add_theme_color_override("font_color", look[0])


func _banner(st: Dictionary, p: Dictionary) -> void:
	var text = null
	var col := Color("0e8aa0")
	var playing: bool = st.get("phase") == "playing"
	var my_piece = null
	for pc in st.get("pieces", []):
		if pc.get("phase") == "control" and pc.get("controller") == Store.my_id:
			my_piece = pc
	if not p.is_empty() and p.get("alive", false) and playing:
		if p.get("controlling", false) and my_piece != null:
			var left := float(my_piece.timeLeft) / 1000.0
			text = "블록 조종 중 %.1f초\n%s%s" % [left, _piece_keys(), "" if my_piece.get("fits", true) else "\n여기엔 못 놓음 (빨간 미리보기)"]
			if left < 3.0:
				col = Color("c83c14")
		elif p.get("hasControl", false):
			var n = st.get("nextSpawnIn")
			text = "조종권 보유: 곧 하늘 시점으로 전환" if n == null else "조종권 보유: %.1f초 후 하늘 시점으로 전환" % (float(n) / 1000.0)
	# 블록 마스터: 마스터는 할 일·남은 시간, 생존자는 누구 블록인지·남은 시간
	if not p.is_empty() and st.get("mode") == "master" and playing and st.round.get("left") != null:
		var m = null
		var survivors := 0
		for x in st.players:
			if x.get("master", false) and not x.get("zombie", false):
				m = x
			if x.get("alive", false) and not x.get("master", false) and not x.get("spectator", false):
				survivors += 1
		var left_s := _fmt(float(st.round.left))
		if p.get("master", false):
			var extra := "\n다음 블록 준비 중"
			if my_piece != null:
				extra = "\n%s (%.1f초)%s" % [_piece_keys(), float(my_piece.timeLeft) / 1000.0, "" if my_piece.get("fits", true) else " · 여기엔 못 놓음 (꽉 찼거나 주변보다 %d칸 넘게 높아짐)" % int(C.MASTER_MAX_RISE)]
			text = "%s: 생존자를 다 깔아라! 남은 %s · 생존 %d명%s" % ["마스터 편" if p.get("zombie", false) else "블록 마스터", left_s, survivors, extra]
			col = Color("782ca0")
		elif p.get("alive", false):
			text = "%s의 블록을 피해 버티기 · 남은 %s · 생존 %d명" % [_name(m) if m != null else "마스터", left_s, survivors]
			col = Color("148c3c") if float(st.round.left) < 10000.0 else Color("782ca0")
	banner.visible = text != null
	if text != null:
		banner.text = text
		var s: StyleBoxFlat = banner.get_theme_stylebox("normal")
		s.bg_color = col


func _bottom(st: Dictionary, p: Dictionary, show: bool, vp: Vector2) -> void:
	bottom.visible = show
	var skills: Control = hud.get("skills") if hud != null else null
	var r_slot: Label = hud.get("skill_r") if hud != null else null
	ammo.visible = show and str(p.get("char", "")) == "hook"
	balls.visible = show and str(p.get("char", "")) == "cannon" and p.get("cannon") is Dictionary
	if not show:
		return
	var b := []
	for kv in [["jumpLeft", "점프↑"], ["speedLeft", "이속↑"], ["ghostLeft", "유령"], ["shieldLeft", "부활 무적"], ["iframeLeft", "무적"]]:
		var v := float(p.get(kv[0], 0))
		if v > 0:
			b.append("%s %.1fs" % [kv[1], v / 1000.0])
	buffs.text = "   ".join(b)
	var item := "아이템 —"
	if float(p.get("ammo", 0)) > 0:
		item = "투사체 ×%d" % int(p.ammo)
	elif float(p.get("bricks", 0)) > 0:
		item = "설치 1×2 ×%d %s" % [int(p.bricks), "옆" if p.get("brickSide", false) else "앞"]
	elif float(p.get("bombs", 0)) > 0:
		item = "폭탄 ×%d" % int(p.bombs)
	item_slot.text = "%s  %s" % [Keys.key_label(str(PlayerInput.binds.get("item", ""))), item]
	item_slot.modulate.a = 0.5 if item.ends_with("—") else 1.0
	item_slot.visible = bool(st.get("itemsEnabled", C.ITEMS_ENABLED))
	var top_y: float = skills.position.y if skills != null and skills.visible else vp.y - 150.0
	bottom.position = Vector2((vp.x - bottom.size.x) / 2.0, top_y - bottom.size.y - 6)
	# R 칸: 못 씀 이유·흔들림, 사냥꾼 대상 없음이면 회색, 바드 메탈 폼 이름 (hud.gd 가 쓴 글을 덮어씀)
	if r_slot != null and skills != null and skills.visible:
		var now := _now()
		var ult_max := float(p.get("ultMax", C.ULT_MAX))
		var full := float(p.get("ult", 0)) >= ult_max
		var bard = p.get("bard")
		var ult_name := str(C.BARD_METAL_ULT_NAME) if str(p.get("char", "")) == "bard" and bard is Dictionary and bard.get("form") == "metal" else str(C.ULT_NAMES.get(str(p.get("char", "")), ""))
		r_slot.text = "R  %s" % (ult_fail_text if now < ult_fail_until else "%s %s" % [ult_name, "준비!" if full else "%d%%" % int(floor(float(p.get("ult", 0)) / ult_max * 100))])
		r_slot.add_theme_color_override("font_color", Color("ff5050") if now < ult_fail_until else S.TEXT)
		var dim: bool = full and typeof(p.get("ultTarget")) == TYPE_BOOL and not bool(p.ultTarget) # 사냥꾼: 쏠 표식 대상 없음
		var panel := r_slot.get_parent() as Control
		panel.modulate = Color(0.55, 0.55, 0.55) if dim else (Color(1.2, 1.1, 0.7) if full else Color.WHITE)
		panel.position.x = (sin(now / 18.0) * 6.0 * (shake_until - now) / C.ULT_FAIL_SHAKE_MS) if now < shake_until else 0.0
		var rr := panel.get_global_rect()
		ammo.position = Vector2(rr.end.x + 8, rr.position.y + (rr.size.y - 16) / 2.0)
		ammo.queue_redraw()
		balls.position = Vector2(rr.end.x + (32 if ammo.visible else 8), rr.position.y + (rr.size.y - 20) / 2.0)
		balls.queue_redraw()


# 대포수 탄 3칸: 찬 칸 = 쇠공 (금 테), 빈 칸 첫째는 장전 진행만큼 아래부터 차오름
func _draw_balls() -> void:
	var c = Store.me().get("cannon")
	if not (c is Dictionary):
		return
	var n := int(C.CANNON_AMMO_MAX)
	var ammo_n := int(c.get("ammo", 0))
	var reload_ms := float(c.get("reloadMs", 0))
	var prog := 1.0 - float(c.get("reloadLeft", 0)) / reload_ms if reload_ms > 0 else 0.0
	for i in n:
		var ctr := Vector2(10 + i * 26, 10)
		var full := i < ammo_n
		if full:
			balls.draw_circle(ctr, 8.0, Color("2a2c30"))
			balls.draw_circle(ctr + Vector2(-2.5, -2.5), 3.0, Color("9a9ca4"))
		elif i == ammo_n and float(c.get("reloadLeft", 0)) > 0:
			var h := 16.0 * prog
			balls.draw_rect(Rect2(ctr.x - 6, ctr.y + 8 - h, 12, h), Color("6a6c70"))
		balls.draw_arc(ctr, 8.0, 0, TAU, 24, Color("ffd23a") if full else Color("888888"), 2.0)


# 조준점: 평소 작은 원 (hud.gd 링이 그림), 든 아이템이면 큰 원 — 투사체 빨강·설치 블록 노랑 네모·폭탄 주황
func _draw_cross() -> void:
	if cross_kind == "":
		return
	var c := crosshair.size / 2.0
	var col := Color("ff3030") if cross_kind == "armed" else (Color("f0d060") if cross_kind == "brick" else Color("ff7a20"))
	if cross_kind == "brick":
		crosshair.draw_rect(Rect2(c - Vector2(13, 13), Vector2(26, 26)), col, false, 3.0)
	else:
		crosshair.draw_arc(c, 13.0, 0, TAU, 32, col, 3.0)

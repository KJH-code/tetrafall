# G4 화면 모양 '빛 사선' (JS client/index.html 의 메뉴·대기실·창 CSS): 어두운 반투명 판 + 테마 빛 테두리·왼쪽 빛 띠,
# 평행사변형 버튼 (StyleBoxFlat.skew), 주 버튼은 하양→빛 채움, 글자 빛 (외곽선 + 그림자). 판 중 HUD 는 밝은 예전 모양 (노랑·남색)
# 빛 색: 테마 (config TITLE_THEMES[id].edge·glow). 3D 메뉴·대기실 장면 (다음 단계) 이 View.ui_theme 를 정하면 그것, 없으면 자수정
extends RefCounted

const C := preload("res://core/config.gd")
const Coords := preload("res://core/coords.gd")
const FONT := preload("res://assets/fonts/ui_font.tres")

# JS index.html :root 토큰
const INK := Color("060913")
const PANEL := Color("151d38")
const PANEL2 := Color("0a0f22")
const TEXT := Color("f4f6ff")
const DIM := Color("9fabcd")
const ACCENT := Color("ffd23a")
const ACCENT_D := Color("8a5c00")
const HOT := Color("ff4426")
const GOOD := Color("36d07a")
const SKEW := 0.18 # 평행사변형 기울기 (CSS clip-path 9px / 높이 ~50px)

# 테마 빛 색을 쓴 것 기억 (판 테마가 바뀌면 restyle 이 그 자리에서 다시 칠함 — 타이틀·대기실 맵 테마 View.ui_theme). [WeakRef, 종류, 인자]
static var _reg: Array = []


static func _keep(o: Object, kind: String, arg = null) -> void:
	_reg.append([weakref(o), kind, arg])
	if _reg.size() > 4000: # 다시 만든 목록 (방 목록·색 칸 등) 이 쌓이면 사라진 것만 버림
		_reg = _reg.filter(func(r): return r[0].get_ref() != null)


# View.ui_theme 가 바뀌면 (ui.gd 가 부름): 기억한 판·버튼·글자 빛·글자 칸·체크 상자를 새 테마 색으로
static func restyle() -> void:
	var gc := g()
	var live: Array = []
	for r in _reg:
		var o = r[0].get_ref()
		if o == null:
			continue
		live.append(r)
		match r[1]:
			"pane":
				o.border_color = alpha(gc, 0.55)
				o.shadow_color = alpha(gc, 0.18)
			"btn":
				var fresh := button_box(r[2][0], r[2][1], false)
				o.bg_color = fresh.bg_color
				o.border_color = fresh.border_color
				o.shadow_color = fresh.shadow_color
			"btn_font":
				if r[2] != "go":
					o.add_theme_color_override("font_outline_color", alpha(gc, 0.6))
			"glow":
				o.add_theme_color_override("font_outline_color", alpha(gc, 0.75))
				o.add_theme_color_override("font_shadow_color", alpha(g2(), 0.5))
			"edit":
				o.border_color = gc if r[2] else alpha(gc, 0.22)
			"check":
				_check_icons(o)
	_reg = live


static func theme_id() -> String:
	var t = View.get("ui_theme")
	return str(t) if t != null and C.TITLE_THEMES.has(str(t)) else "crystal"


# 테마 빛 색: g = 테두리·글자 빛 (edge), g2 = 넓은 빛 (glow)
static func g() -> Color:
	return Coords.color(C.TITLE_THEMES[theme_id()].edge)


static func g2() -> Color:
	return Coords.color(C.TITLE_THEMES[theme_id()].glow)


static func alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


# 빛 판: 어두운 유리 + 빛 테두리 + 왼쪽 빛 띠 (#center·#results·창)
static func pane(strip := true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	_keep(s, "pane")
	s.bg_color = Color(0.09, 0.06, 0.17, 0.88)
	s.border_color = alpha(g(), 0.55)
	s.set_border_width_all(1)
	if strip:
		s.border_width_left = 5
	s.shadow_color = alpha(g(), 0.18)
	s.shadow_size = 14
	s.set_content_margin_all(16)
	s.content_margin_left = 22
	return s


# 버튼: kind = "ghost" (빛 테두리만) | "go" (하양→빛 채움, 주 버튼) | "big" (메뉴 큰 버튼). state = normal·hover·pressed·disabled
static func button_box(kind: String, state: String, keep := true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if keep:
		_keep(s, "btn", [kind, state])
	s.skew = Vector2(SKEW, 0)
	s.anti_aliasing = true
	var gc := g()
	match kind:
		"go":
			s.bg_color = gc.lerp(Color.WHITE, 0.55 if state != "hover" else 0.7)
			s.border_color = Color.WHITE
			s.set_border_width_all(1)
			s.shadow_color = alpha(gc, 0.6)
			s.shadow_size = 10 if state != "hover" else 16
		"big":
			s.bg_color = Color(0.12, 0.07, 0.2, 0.84) if state == "normal" else gc.darkened(0.55)
			s.border_color = alpha(gc, 0.55) if state == "normal" else gc
			s.set_border_width_all(1)
			s.border_width_left = 4
			s.shadow_color = alpha(gc, 0.25 if state == "normal" else 0.45)
			s.shadow_size = 8
		_:
			s.bg_color = Color(0.04, 0.02, 0.09, 0.6) if state == "normal" else alpha(gc.darkened(0.6), 0.85)
			s.border_color = alpha(gc, 0.55)
			s.set_border_width_all(1)
	if state == "disabled":
		s.bg_color = Color(0.2, 0.2, 0.22, 0.5)
		s.border_color = Color(0.4, 0.4, 0.45, 0.5)
		s.shadow_size = 0
	if state == "pressed":
		s.expand_margin_top = -2
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func style_button(b: Button, kind := "ghost", size := 16) -> Button:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var key: String = "normal" if st == "focus" else str(st)
		b.add_theme_stylebox_override(st, button_box(kind, key))
	var fg := Color("12081c") if kind == "go" else Color.WHITE
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(0.7, 0.7, 0.75))
	b.add_theme_font_size_override("font_size", size)
	_keep(b, "btn_font", kind)
	if kind != "go":
		b.add_theme_color_override("font_outline_color", alpha(g(), 0.6))
		b.add_theme_constant_override("outline_size", 4)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func button(text: String, cb: Callable, kind := "ghost", size := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return style_button(b, kind, size)


# 글자 빛 (CSS text-shadow 빛): 외곽선을 빛 색으로 + 그림자
static func glow_label(text: String, size := 20, color := Color.WHITE, glow := 6) -> Label:
	var l := Label.new()
	_keep(l, "glow")
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", alpha(g(), 0.75))
	l.add_theme_constant_override("outline_size", glow)
	l.add_theme_color_override("font_shadow_color", alpha(g2(), 0.5))
	l.add_theme_constant_override("shadow_outline_size", glow * 2)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	return l


static func label(text: String, size := 14, color := DIM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


# 글자 칸: 어두운 바탕 + 빛 테두리 (포커스면 게임 키를 막는 건 ui.gd 가 한 곳에서 — PlayerInput.ui_blocking)
static func line_edit(placeholder: String, size := 16, max_len := 0) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	if max_len > 0:
		e.max_length = max_len
	e.add_theme_font_size_override("font_size", size)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.45)
	s.border_color = alpha(g(), 0.22)
	s.set_border_width_all(1)
	s.set_content_margin_all(6)
	e.add_theme_stylebox_override("normal", s)
	_keep(s, "edit", false)
	var f: StyleBoxFlat = s.duplicate()
	f.border_color = g()
	_keep(f, "edit", true)
	e.add_theme_stylebox_override("focus", f)
	return e


# 판 중 HUD (밝은 예전 모양): 남색 판 + 노랑 띠
static func hud_box(accent_left := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.05, 0.1, 0.8)
	s.skew = Vector2(SKEW * 0.6, 0)
	if accent_left:
		s.border_width_left = 4
		s.border_color = ACCENT
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


# 체크 상자: 기본 테마 표시가 어두운 판에서 안 보여서 직접 그림 (빈 칸 = 빛 테두리, 켬 = 빛 채움 + 하얀 속)
static func _check_icon(on: bool, off_alpha := 1.0) -> ImageTexture:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var gc := g()
	for y in n:
		for x in n:
			var edge: bool = x < 2 or y < 2 or x >= n - 2 or y >= n - 2
			if edge:
				img.set_pixel(x, y, alpha(gc, off_alpha))
			elif on:
				var inner: bool = x >= 5 and y >= 5 and x < n - 5 and y < n - 5
				img.set_pixel(x, y, Color.WHITE if inner else alpha(gc, 0.85))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0.45))
	return ImageTexture.create_from_image(img)


static func _check_icons(c: CheckBox) -> void:
	c.add_theme_icon_override("unchecked", _check_icon(false))
	c.add_theme_icon_override("checked", _check_icon(true))
	c.add_theme_icon_override("unchecked_disabled", _check_icon(false, 0.35))
	c.add_theme_icon_override("checked_disabled", _check_icon(true, 0.35))


static func style_check(c: CheckBox, size := 13) -> CheckBox:
	_check_icons(c)
	_keep(c, "check")
	c.add_theme_font_size_override("font_size", size)
	c.add_theme_color_override("font_color", TEXT)
	c.add_theme_color_override("font_hover_color", Color.WHITE)
	c.add_theme_color_override("font_pressed_color", Color.WHITE)
	c.add_theme_constant_override("h_separation", 6)
	c.focus_mode = Control.FOCUS_NONE
	return c

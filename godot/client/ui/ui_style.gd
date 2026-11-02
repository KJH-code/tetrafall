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
const SKEW := 0.18 # 평행사변형 기울기 (판 중 HUD 칸들) — StyleBoxFlat 기울기 = 높이 × 이 값
const SKEW_BTN := 0.27 # 창 버튼 (JS --par 9px / 버튼 높이 ~33px)
const SKEW_BIG := 0.29 # 메뉴 큰 버튼 (JS clip-path 18px / 높이 62px)
const CUT := 20 # 빛 판 잘린 모서리 (JS --cut2: 오른쪽 위·왼쪽 아래 20px)
const LOGO_SLANT := 0.355 # 로고 기울기 (JS font-style: italic (브라우저 가짜 기울임 ¼) + skewX(-6deg) tan 0.105)
# 로고 빛 겹 [외곽선 굵기, 색 (g = 테마 빛, g2 = 넓은 빛, w = 흰), 진하기] — JS text-shadow 0 0 4px #fff, 18px g, 46px g2, 90px g2 50% 를 겹겹이
const LOGO_GLOW := [[44, "g2", 0.08], [30, "g2", 0.12], [18, "g", 0.22], [9, "g", 0.4], [4, "w", 0.7]] # 외곽선은 너무 굵으면 글꼴 래스터가 깨져 44 까지

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
			"tint":
				o.add_theme_color_override("font_color", gc.lerp(r[2][0], r[2][1]))
			"layer":
				o.add_theme_color_override("font_outline_color", alpha(_glow_col(r[2][0]), r[2][1]))
			"streak":
				o.texture = _streak_tex()
			"under":
				o.border_color = alpha(gc, 0.55)
			"border":
				o.border_color = alpha(gc, r[2])
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


# 글자색 = 테마 빛 색을 mix 쪽으로 amount 만큼 (테마가 바뀌면 restyle 이 다시 칠함)
static func tint(c: Control, mix: Color = Color.WHITE, amount := 0.5) -> Control:
	c.add_theme_color_override("font_color", g().lerp(mix, amount))
	_keep(c, "tint", [mix, amount])
	return c


# 테두리 = 테마 빛 색 (투명도 a), 테마가 바뀌면 다시 칠함
static func theme_border(s: StyleBoxFlat, a := 1.0) -> StyleBoxFlat:
	s.border_color = alpha(g(), a)
	_keep(s, "border", a)
	return s


# 빛 판: 어두운 유리 + 빛 테두리 + 왼쪽 빛 띠 (#center·#results·창). JS --cut2: 오른쪽 위·왼쪽 아래 20px 잘린 모서리 (둥글기 1단 = 깎은 모서리),
# 빛은 판 안쪽으로만 (inset) — 예전엔 바깥 그림자 14px 로 판 밖이 빛났음
static func pane(strip := true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	_keep(s, "pane")
	s.bg_color = Color(0.09, 0.06, 0.17, 0.88)
	s.border_color = alpha(g(), 0.55)
	s.set_border_width_all(1)
	if strip:
		s.border_width_left = 5
	s.shadow_size = 0
	s.corner_radius_top_right = CUT
	s.corner_radius_bottom_left = CUT
	s.corner_detail = 1
	s.anti_aliasing = true
	s.set_content_margin_all(16)
	s.content_margin_left = 22
	return s


# 메뉴 펼친 세부 (JS #rooms .open): rgba(4,3,10,.78) + 안쪽 1px gb (22%) + 잘린 모서리, padding 12 18, margin 6px 10px 0
static func open_pane() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color8(4, 3, 10, 199)
	s.set_border_width_all(1)
	theme_border(s, 0.22)
	s.corner_radius_top_right = CUT
	s.corner_radius_bottom_left = CUT
	s.corner_detail = 1
	s.anti_aliasing = true
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.expand_margin_left = -10 # margin 0 10px (판보다 양쪽 10 안)
	s.expand_margin_right = -10
	return s


# 공개 방 한 줄 (JS #room-list .room): rgba(255,255,255,.035) + 안쪽 1px gc (10%), padding 8 12, 9px 사선
static func room_row() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.035)
	s.set_border_width_all(1)
	theme_border(s, 0.1)
	s.skew = Vector2(0.17, 0)
	s.anti_aliasing = true
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


# 가장자리 어둡게 (CSS radial-gradient(ellipse at cx% cy%, inner 0 inner_stop, outer 100%)): 화면 전체 TextureRect
static func radial_shade(center: Vector2, inner_stop: float, inner: Color, outer: Color) -> TextureRect:
	var t := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = center
	gt.fill_to = Vector2(1.0, 1.0) # 가장 먼 모서리까지 (farthest-corner)
	var gr := Gradient.new()
	gr.set_color(0, inner)
	gr.set_offset(0, inner_stop)
	gr.set_color(1, outer)
	gt.gradient = gr
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


# 글꼴 변형: 기울임 (FontVariation 변환 — CSS italic·skewX), 자간 (letter-spacing px)
static func slanted(slant: float) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = FONT
	f.variation_transform = Transform2D(Vector2(1.0, slant), Vector2(0.0, 1.0), Vector2.ZERO) # 고도 문서의 기울임 꼴 (x 축 = (1, slant))
	return f


static var _spaced := {}
static func spaced(px: int) -> FontVariation:
	if not _spaced.has(px):
		var f := FontVariation.new()
		f.base_font = FONT
		f.spacing_glyph = px
		_spaced[px] = f
	return _spaced[px]


static func _glow_col(kind: String) -> Color:
	return Color.WHITE if kind == "w" else (g2() if kind == "g2" else g())


# 빛 겹 하나 (글자는 투명, 외곽선만 빛 색 · 진하기)
static func glow_layer(l: Label, kind: String, a: float) -> void:
	l.add_theme_color_override("font_outline_color", alpha(_glow_col(kind), a))
	_keep(l, "layer", [kind, a])


# 로고 가운데 빛 줄 (JS h2::after: 3px, 투명 → g 30% → 흰 50% → g 70% → 투명, 흐림 1px, 진하기 .7)
static func _streak_tex() -> GradientTexture2D:
	var gt := GradientTexture2D.new()
	gt.width = 256
	gt.height = 4
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.7, 1.0])
	gr.colors = PackedColorArray([alpha(g(), 0.0), alpha(g(), 0.7), Color(1, 1, 1, 0.7), alpha(g(), 0.7), alpha(g(), 0.0)])
	gt.gradient = gr
	return gt


static func streak() -> TextureRect:
	var t := TextureRect.new()
	t.texture = _streak_tex()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keep(t, "streak")
	return t


# 메뉴 이름 칸 (JS .nick input): 테두리 없이 아래 2px 빛 줄 (ga 55%), 바탕 rgba(0,0,0,.35), padding 4 8
static func underline_edit(e: LineEdit) -> void:
	for st in ["normal", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0, 0, 0, 0.35)
		s.border_width_bottom = 2
		s.border_color = alpha(g(), 0.55)
		_keep(s, "under")
		s.content_margin_left = 8
		s.content_margin_right = 8
		s.content_margin_top = 4
		s.content_margin_bottom = 4
		e.add_theme_stylebox_override(st, s)


# 움직임 줄이기·그래픽 낮춤 (등장 애니 끔)
static func reduced() -> bool:
	return bool(View.settings.get("reducedMotion", false)) or bool(View.settings.get("lowGfx", false))


# 등장 애니: 나타남 (JS open-down .22s ease-out — 위치는 컨테이너가 정해 투명도만)
static func pop_down(c: CanvasItem) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


# 버튼: kind = "ghost" (빛 테두리만) | "go" (하양→빛 채움, 주 버튼) | "big" (메뉴 큰 버튼). state = normal·hover·pressed·disabled
static func button_box(kind: String, state: String, keep := true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if keep:
		_keep(s, "btn", [kind, state])
	s.skew = Vector2(SKEW_BIG if kind == "big" else SKEW_BTN, 0)
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
			# JS button.big: 바탕 rgba(30,18,52,.8)→rgba(8,5,18,.86) (가운데 색), 안쪽 1px ga, 바깥 빛 없음. hover·열림은 g 36% 섞음 + 테두리 g
			s.bg_color = Color8(19, 11, 35, 212) if state == "normal" else alpha(gc.lerp(Color8(18, 12, 34), 0.64), 0.86)
			s.border_color = alpha(gc, 0.55) if state == "normal" else gc
			s.set_border_width_all(1)
			s.border_width_left = 4
			s.shadow_size = 0
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

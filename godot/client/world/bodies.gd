# 사람 몸 자리: G2 의 chars/chars.gd make_body(char, color) 가 있으면 그 몸, 없으면 상자 몸 (G0 dev_view 와 같음).
# World 는 위치 (Store.view_pos 보간)·방향·보이기·머리 위 이름표만 정함. 몸 동작은 몸 노드의 pose(p, now_ms)·on_event(e) (G2)
extends Node3D
const Opts := preload("res://core/opts.gd")

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const Labels := preload("res://world/labels.gd")
const UI_CALC := "res://ui/ui_calc.gd" # G4 hp_view (체력전 HP)
const CHARS := "res://chars/chars.gd"
const Lod := preload("res://world/pose_lod.gd")
const OutFar := preload("res://world/outline_far.gd")
const Sh := preload("res://world/shadow_calc.gd")
const Opts_ := preload("res://core/opts.gd")
static var NO_OUTLINE_FAR: bool = Opts_.args().has("--no-outline-far") # 확인용: 외곽선 거리 끔 (전후 비교)
static var NO_SHADOW_FAR: bool = Opts_.args().has("--no-shadow-far") or Opts_.args().has("--no-shadow-opt") # 확인용 (W32): 먼 몸·시야 밖 몸 그림자 끄기를 끔 (전후 비교)
const Prof := preload("res://core/prof.gd")

var stencil_fn = null # Callable(ShaderMaterial): 몸 재질이 스텐실을 씀 (사냥꾼의 눈 x-ray 가 몸에 가린 곳엔 안 나오게, G3.toon_stencil_write)
var nodes := {} # id -> {root, body, label, char, color}
var chars_script = null
var ui_calc = null # G4 ui/ui_calc.gd (hp_view·hp_color) — 없으면 체력전도 %
static var _white: ImageTexture
var pos_fn = null # Callable(p, pos) -> pos: 화면 위치 고치기 (World: 대기실 미리보기 판 가운데·지형 위)
var make_mat = null # Callable(Color) -> Material: G3 툰 재질 (상자 몸, 없으면 StandardMaterial3D)
var shown := {} # id -> 게임 좌표 화면 위치 (Vector3) — 카메라·하늘 도우미가 읽음
var cam: Camera3D = null # 몸 자세 LOD (W12, world/pose_lod.gd): 판 카메라 (지난 프레임 자리) — 없으면 모두 매 프레임
var lod_on := true # 확인용 (--no-pose-lod)
var lod := WC.POSE_LOD # 확인용 --pose-lod-near <m> 로 near 만 바꿈
var _last_now = null
var sun_node: DirectionalLight3D = null # W32: 해 (몸 그림자가 떨어지는 쪽 계산) — World 아래 G3Env/Sun, 처음 쓸 때 찾음


func _ready() -> void:
	var a := Opts.args()
	lod_on = not a.has("--no-pose-lod")
	if Opts.web():
		lod = WC.POSE_LOD_WEB
	var ni := a.find("--pose-lod-near")
	if ni >= 0 and ni + 1 < a.size():
		lod = lod.duplicate()
		lod.near = float(a[ni + 1])
	if ResourceLoader.exists(CHARS):
		chars_script = load(CHARS)
	if ResourceLoader.exists(UI_CALC):
		ui_calc = load(UI_CALC)


# 팀전이면 팀 계열 (팀 안 자리 순 명암), 아니면 고른 색 (render.js playerColor)
static func player_color(p: Dictionary, st: Dictionary) -> int:
	var team = p.get("team")
	if st.get("teamMode", false) and team != null and WC.TEAM_COLORS.has(team):
		var mates := []
		for o in st.players:
			if o.get("team") == team:
				mates.append(o)
		mates.sort_custom(func(a, b): return a.slot < b.slot)
		var idx := 0
		for i in mates.size():
			if int(mates[i].id) == int(p.id):
				idx = i
		var list: Array = WC.TEAM_COLORS[team]
		return int(list[idx % list.size()])
	var ci = p.get("color", p.get("slot", 0))
	return int(C.PLAYER_PALETTE[int(ci if ci != null else 0) % C.PLAYER_PALETTE.size()])


# 몸 모양 이름 (render.js: 연습 방 허수아비는 'dummy' — 캐릭터 없는 허수아비 모양, B2 make_body 가 그림)
static func look_of(p: Dictionary) -> String:
	if p.get("dummy", false):
		return "dummy"
	var c = p.get("char")
	return str(c) if c != null else ""


func _make(p: Dictionary, color: int) -> Dictionary:
	var root := Node3D.new()
	var body: Node3D
	if chars_script != null:
		body = chars_script.make_body(look_of(p), Co.color(color))
	else:
		body = _box_body(color)
	root.add_child(body)
	if stencil_fn != null and body.get("drawn") is Array: # render.js bodyOrder: 사람 몸은 x-ray 복사본보다 앞
		for dr in body.drawn:
			if dr.get("mi") is GeometryInstance3D and dr.mi.material_override is ShaderMaterial:
				stencil_fn.call(dr.mi.material_override)
	var lab := Label3D.new()
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.fixed_size = true
	lab.pixel_size = WC.LABEL_PIXEL
	lab.font_size = WC.LABEL_FONT[0]
	lab.outline_size = WC.LABEL_FONT[1]
	lab.no_depth_test = true
	lab.position.y = C.PLAYER_HEIGHT + C.LABEL_ABOVE_HEAD + WC.LABEL_LIFT
	var ext = body.get("ext") # W19 외부 (Blender) 모델이 코드 몸보다 크면 (투구 깃) 이름표를 그만큼 올림 (<id>.json label_lift)
	if ext != null and ext.get("info") is Dictionary:
		lab.position.y += float(ext.info.cfg.get("label_lift", 0.0))
	root.add_child(lab)
	# 체력전: 이름 아래 작은 HP 막대 (뒤판 + 채움, 화면 크기 고정)
	var bar_back := _bar_sprite(Color(0, 0, 0, 0.7))
	var bar_fill := _bar_sprite(Color.WHITE)
	bar_fill.render_priority = 1
	for b in [bar_back, bar_fill]:
		b.position.y = lab.position.y
		b.visible = false
		root.add_child(b)
	add_child(root)
	return {"root": root, "body": body, "label": lab, "char": look_of(p), "color": color, "bar_back": bar_back, "bar_fill": bar_fill}


func _bar_sprite(c: Color) -> Sprite3D:
	if _white == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	var s := Sprite3D.new()
	s.texture = _white
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.fixed_size = true
	s.no_depth_test = true
	s.shaded = false
	s.modulate = c
	return s


# 체력전 머리 위 HP 막대 (hv = G4 ui_calc.hp_view: {hp, max, frac, low}, null 이면 숨김). 이름 바로 아래, 크기는 이름표 크기를 따라감
func _hp_bar(n: Dictionary, hv, lab: Label3D) -> void:
	var back: Sprite3D = n.bar_back
	var fill: Sprite3D = n.bar_fill
	var on: bool = hv != null and lab.visible
	back.visible = on
	fill.visible = on
	if not on:
		return
	var k: float = lab.pixel_size / WC.LABEL_PIXEL # 이름표 크기 (가까운 4명 / 먼 사람·하늘)
	var w: float = WC.HP_BAR[0]
	var h: float = WC.HP_BAR[1]
	var frac := clampf(float(hv.frac), 0.0, 1.0)
	# 4px 텍스처 → pixel_size 로 화면 px 크기 (fixed_size): 폭 w·높이 h px
	back.pixel_size = WC.LABEL_PIXEL * k
	fill.pixel_size = back.pixel_size
	back.scale = Vector3(w / 4.0, h / 4.0, 1)
	fill.scale = Vector3(maxf(0.001, w * frac) / 4.0, (h - 2) / 4.0, 1)
	var dy: float = WC.HP_BAR[2] # 이름 아래로 (px, 이름표 글자 기준)
	back.offset = Vector2(0, -dy / (h / 4.0)) # offset 은 텍스처 px (scale 전) 단위
	fill.offset = Vector2((-(w - w * frac) / 2.0) / maxf(0.001, w * frac) * 4.0, -dy / ((h - 2) / 4.0))
	fill.modulate = ui_calc.hp_color(frac) if ui_calc.has_method("hp_color") else Color.WHITE
	back.modulate.a = 0.7 # (예전 lab.modulate.a × 0.7 — 그땐 여기서 늘 a = 1 이라 실제로 0.7·1, W15 에 이름표 투명도를 프레임마다 1 로 되돌리지 않게 바꾼 뒤에도 같은 모습)
	fill.modulate.a = 1.0


func _box_body(color: int) -> Node3D:
	var root := Node3D.new()
	var mat: Material
	if make_mat != null:
		mat = make_mat.call(Co.color(color))
	else:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Co.color(color)
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = C.PLAYER_HALF
	cm.height = C.PLAYER_HEIGHT
	body.mesh = cm
	body.position.y = C.PLAYER_HEIGHT / 2
	body.material_override = mat
	root.add_child(body)
	var nose := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(0.3, 0.15, 0.15)
	nose.mesh = nb
	nose.position = Vector3(0.35, C.PLAYER_HEIGHT * 0.75, 0)
	nose.material_override = mat
	root.add_child(nose)
	return root


# hide_me: 1인칭이면 내 몸 숨김. sky: 하늘 시점 (이름표 이름만·작게)
func update(st: Dictionary, my_id, hide_me: bool, sky: bool, now_ms: float) -> void:
	var seen := {}
	shown.clear()
	var frame_ms: float = 0.0 if _last_now == null else maxf(0.0, now_ms - float(_last_now))
	_last_now = now_ms
	var planes: Array = []
	var cpos := Vector3.ZERO
	var use_lod: bool = lod_on and cam != null and cam.is_inside_tree()
	if use_lod:
		planes = cam.get_frustum()
		cpos = cam.global_position
	var to_sun := Vector3(0.4, 1.0, 0.4).normalized()
	if use_lod and not NO_SHADOW_FAR:
		if sun_node == null and get_parent() != null:
			sun_node = get_parent().get_node_or_null("G3Env/Sun") as DirectionalLight3D
		if sun_node != null and sun_node.is_inside_tree():
			to_sun = sun_node.global_transform.basis.z.normalized() # 빛은 −Z 로 비춤 → +Z = 해가 있는 쪽
	for p in st.get("players", []):
		var id := int(p.id)
		seen[id] = true
		var color := player_color(p, st)
		var n: Dictionary = nodes.get(id, {})
		if not n.is_empty() and (n.char != look_of(p) or (chars_script == null and n.color != color)):
			n.root.queue_free() # 캐릭터·색이 바뀜 → 몸 새로
			n = {}
		if n.is_empty():
			n = _make(p, color)
			nodes[id] = n
		var pos := Store.view_pos(id)
		if pos_fn != null:
			pos = pos_fn.call(p, pos)
		shown[id] = pos
		var root: Node3D = n.root
		var mine: bool = my_id != null and id == int(my_id)
		root.visible = p.alive and not p.get("master", false)
		root.position = Co.gpos(pos)
		root.rotation = Vector3(0, Co.rot_y(p.yaw), 0)
		(n.body as Node3D).visible = not (mine and hide_me)
		if use_lod and not NO_OUTLINE_FAR and n.body.has_method("set_outline_far"): # W31: 먼 몸은 외곽선 껍질을 뗌 (시야각 70° 기준 거리, 켜고 끄는 문턱에 여유)
			var of := OutFar.far_state(root.global_position.distance_to(cpos), cam.fov, bool(n.body.outline_far()), mine)
			n.body.set_outline_far(of)
		if use_lod and not NO_SHADOW_FAR and n.body.has_method("set_shadow_off"): # W32: 먼 몸·몸도 그림자도 시야 밖인 몸은 해 그림자를 끔
			var so: bool = Sh.far_off(root.global_position.distance_to(cpos), cam.fov, bool(n.body.shadow_off()), mine)
			if not so and root.visible and not mine:
				var sc := root.global_position + Vector3(0, C.PLAYER_HEIGHT * 0.5, 0)
				so = not Sh.visible_or_shadow(planes, sc, to_sun, float(lod.margin) + float(WC.SHADOW.view_pad), root.global_position.y)
			n.body.set_shadow_off(so)
		if n.body.has_method("pose"):
			var iv := 0.0
			if use_lod and root.visible and not mine:
				var c := root.global_position + Vector3(0, C.PLAYER_HEIGHT * 0.5, 0)
				iv = Lod.interval_ms(c.distance_to(cpos), Lod.in_view(planes, c, float(lod.margin)), false, lod)
			if Lod.due(now_ms, n.get("posed_at"), iv, frame_ms):
				n.body.pose(p, now_ms)
				n["posed_at"] = now_ms
				if Prof.on:
					Prof.add_us("몸 LOD 자세 함 (번)", 1000)
			elif Prof.on:
				Prof.add_us("몸 LOD 자세 안 함 (번)", 1000)
		var lab: Label3D = n.label
		var name := str(p.get("nick", "")) if str(p.get("nick", "")) != "" else str(p.get("name", ""))
		var hv = ui_calc.hp_view(p, st) if ui_calc != null and not sky else null
		var txt: String = name if sky or hv != null else "%s\n%d%%" % [name, int(p.get("damage", 0))]
		if lab.text != txt:
			lab.text = txt
		_hp_bar(n, hv, lab)
		# 색은 바뀔 때만, 투명도는 thin_labels 가 정한 값 그대로 (W15: 예전엔 여기서 a = 1 → thin_labels 가 다시 흐리게 — 이름표마다 프레임마다 두 번 다시 그림)
		var lc := Co.color(color).lightened(WC.LABEL_LIGHTEN)
		lc.a = lab.modulate.a
		if lab.modulate != lc:
			lab.modulate = lc
		lab.visible = p.alive and not (mine and not sky) # 내 % 는 화면 아래 HUD
	for id in nodes.keys():
		if not seen.has(id):
			nodes[id].root.queue_free()
			nodes.erase(id)


# 카메라를 놓은 뒤: 크기·흐림 (labelSizes), 하늘 시점이면 작게 + 화면에서 겹치는 이름표는 먼저 놓인 것만 (render.js thinLabels)
func thin_labels(cam: Camera3D, sky: bool) -> void:
	var vis: Array[Label3D] = []
	for id in nodes:
		var l: Label3D = nodes[id].label
		if l.visible and nodes[id].root.visible:
			vis.append(l)
	var dists := []
	for l in vis:
		dists.append(l.global_position.distance_to(cam.global_position))
	var sizes := Labels.label_sizes(dists)
	var k := float(C.SKY_VIEW.label) if sky else 1.0
	# 화면에서 겹치면 가까운 것만 (하늘 시점은 SKY_VIEW.labelGap, 보통은 이름표 크기 × 배율), UI 판 (View.covers) 뒤면 숨김
	var items := []
	var idx := []
	for i in vis.size():
		var l := vis[i]
		var px: float = WC.LABEL_PIXEL * sizes[i][0] * k
		if not is_equal_approx(l.pixel_size, px): # (Label3D 값은 float32 — 그냥 != 면 늘 다름)
			l.pixel_size = px
		if not is_equal_approx(l.modulate.a, float(sizes[i][1])):
			l.modulate.a = sizes[i][1]
		if cam.is_position_behind(l.global_position):
			continue
		var g: Vector2 = Vector2(C.SKY_VIEW.labelGap[0], C.SKY_VIEW.labelGap[1]) if sky else Vector2(WC.LABEL_GAP[0], WC.LABEL_GAP[1]) * sizes[i][0]
		items.append({"px": cam.unproject_position(l.global_position), "dist": dists[i], "gap": g})
		idx.append(i)
	var shown := Labels.thin(items, View.covers)
	for j in idx.size():
		if not shown[j]:
			vis[idx[j]].visible = false


func on_event(e: Dictionary) -> void:
	for id in nodes:
		var b = nodes[id].body
		if b.has_method("on_event"):
			b.on_event(e)

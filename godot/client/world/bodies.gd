# 사람 몸 자리: G2 의 chars/chars.gd make_body(char, color) 가 있으면 그 몸, 없으면 상자 몸 (G0 dev_view 와 같음).
# World 는 위치 (Store.view_pos 보간)·방향·보이기·머리 위 이름표만 정함. 몸 동작은 몸 노드의 pose(p, now_ms)·on_event(e) (G2)
extends Node3D

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const Labels := preload("res://world/labels.gd")
const CHARS := "res://chars/chars.gd"

var nodes := {} # id -> {root, body, label, char, color}
var chars_script = null
var pos_fn = null # Callable(p, pos) -> pos: 화면 위치 고치기 (World: 대기실 미리보기 판 가운데·지형 위)
var make_mat = null # Callable(Color) -> Material: G3 툰 재질 (상자 몸, 없으면 StandardMaterial3D)
var shown := {} # id -> 게임 좌표 화면 위치 (Vector3) — 카메라·하늘 도우미가 읽음


func _ready() -> void:
	if ResourceLoader.exists(CHARS):
		chars_script = load(CHARS)


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


func _make(p: Dictionary, color: int) -> Dictionary:
	var root := Node3D.new()
	var body: Node3D
	if chars_script != null:
		body = chars_script.make_body(str(p.get("char", "")), Co.color(color))
	else:
		body = _box_body(color)
	root.add_child(body)
	var lab := Label3D.new()
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.fixed_size = true
	lab.pixel_size = WC.LABEL_PIXEL
	lab.font_size = WC.LABEL_FONT[0]
	lab.outline_size = WC.LABEL_FONT[1]
	lab.no_depth_test = true
	lab.position.y = C.PLAYER_HEIGHT + C.LABEL_ABOVE_HEAD + WC.LABEL_LIFT
	root.add_child(lab)
	add_child(root)
	return {"root": root, "body": body, "label": lab, "char": str(p.get("char", "")), "color": color}


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
	for p in st.get("players", []):
		var id := int(p.id)
		seen[id] = true
		var color := player_color(p, st)
		var n: Dictionary = nodes.get(id, {})
		if not n.is_empty() and (n.char != str(p.get("char", "")) or (chars_script == null and n.color != color)):
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
		if n.body.has_method("pose"):
			n.body.pose(p, now_ms)
		var lab: Label3D = n.label
		var name := str(p.get("nick", "")) if str(p.get("nick", "")) != "" else str(p.get("name", ""))
		lab.text = name if sky else "%s\n%d%%" % [name, int(p.get("damage", 0))]
		lab.modulate = Co.color(color).lightened(WC.LABEL_LIGHTEN)
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
		l.pixel_size = WC.LABEL_PIXEL * sizes[i][0] * k
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

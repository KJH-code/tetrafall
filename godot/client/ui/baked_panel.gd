# (W16 2026-11-03) 그림만 굽는 판: 내용이 드물게 바뀌는 큰 화면 판 (대기실·플레이어 관리·설정 창) 을 SubViewport 에 한 번 그려
# 이 칸이 텍스처 한 장으로 그림 → 2D 그리기 수십~백여 번이 1번 (바뀐 프레임만 다시 구움).
#
# 판 노드는 장면 트리에서 그대로 (입력·초점·글자 칸·스크롤·팝업·툴팁은 창 viewport 의 gui 가 예전처럼 받음) — 그리기만
# CanvasLayer.custom_viewport 로 SubViewport 에 감. 판 CanvasLayer 의 변환은 그대로 (항등) 라 클릭 자리 = 예전 자리,
# SubViewport 쪽은 global_canvas_transform 에 UI 배율 (창 늘림) 을 넣어 창 픽셀 그대로 (W9 — 안 흐림), 원점은 화소 칸에 맞춤.
#   다시 굽는 때: 판 안 CanvasItem 의 draw (글·상자·hover·눌림·글자 칸 커서 — 고도가 다시 그릴 때마다 내는 신호),
#   Control 자리·크기 바뀜, 보임 바뀜, 자식 들어옴·나감, 판 자리·배율·투명도, 빛 색 바뀜 (S.restyle), 등장 애니 (S.slide_in·pop_down 동안 매 프레임)
#   SubViewport 는 반투명을 미리 곱한 색 (premultiplied) 으로 쌓이므로 보일 때 PREMULT_ALPHA 로 섞음 → 직접 그린 것과 같은 색
# 산 칸 (live): 판 안이지만 매 프레임 바뀌는 그림 (대기실 큰 3D 캐릭터) 은 굽지 않고 RenderingServer 에서 이 칸 위 자식 칸으로 옮겨 그림
#   (순서: 구운 판 → 산 칸 차례대로, cover 가 참이면 산 칸 숨김 — 판 안에서 그 위를 덮는 것이 보일 때)
# 끄기: 실행 인자 --no-bake (A/B·문제 확인), 그래픽과 무관
extends Control

const S := preload("res://ui/ui_style.gd")

const PAD := 40.0 # 판 사각형 밖으로 그리는 것 (그림자·글자 빛·사선 넘침·미끄러짐) 여유 (UI 좌표)

static var enabled := true

var panel: Control
var layer: CanvasLayer
var sv: SubViewport
var renders := 0 # 구운 수 (테스트·세기)
var dirty := true
var _key := []
var _style_gen := -1
var _live: Array = [] # [CanvasItem, 칸 RID]
var _cover: Callable
var _draw_rect := Rect2()


# 판을 감싸 돌려줌 (판 대신 부모에 넣음). 끄면 판 그대로
static func wrap(p: Control) -> Control:
	if not enabled:
		return p
	var b = load("res://ui/baked_panel.gd").new()
	b.setup(p)
	return b


func setup(p: Control) -> void:
	panel = p
	name = "Baked_" + (p.get_script().resource_path.get_file().get_basename() if p.get_script() != null else p.get_class())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # 화소 1:1
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	material = m
	sv = SubViewport.new()
	sv.transparent_bg = true
	sv.disable_3d = true
	sv.gui_disable_input = true
	sv.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sv.size = Vector2i(2, 2)
	add_child(sv)
	layer = CanvasLayer.new()
	layer.custom_viewport = sv
	add_child(layer)
	layer.add_child(p)
	_watch(p)
	process_priority = 1000 # 다른 화면 판 _process (보임·자리·글) 뒤
	visible = false


func _ready() -> void:
	var cl := _outer_layer()
	if cl != null:
		layer.layer = cl.layer # 입력 순서 (같은 층이면 트리 순서) = 예전 그대로


func _outer_layer() -> CanvasLayer:
	var a := get_parent()
	while a != null and not (a is CanvasLayer):
		a = a.get_parent()
	return a as CanvasLayer


# 산 칸: node 는 굽지 않고 이 판 위에 따로 그림. cover() 가 참이면 숨김
func live(nodes: Array, cover := Callable()) -> void:
	_cover = cover
	for n in nodes:
		var rid := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(rid, get_canvas_item())
		_live.append([n, rid])


func _exit_tree() -> void:
	for l in _live:
		var n: CanvasItem = l[0]
		if is_instance_valid(n) and n.is_inside_tree() and n.get_parent() is CanvasItem:
			RenderingServer.canvas_item_set_parent(n.get_canvas_item(), (n.get_parent() as CanvasItem).get_canvas_item())


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for l in _live:
			RenderingServer.free_rid(l[1])


# 판 안 노드의 바뀜 신호를 다 들음 (새로 들어오는 자식도)
func _watch(n: Node) -> void:
	if n.has_meta("_baked_watch"):
		return
	n.set_meta("_baked_watch", true)
	if n is CanvasItem:
		(n as CanvasItem).draw.connect(_touch)
		(n as CanvasItem).visibility_changed.connect(_touch)
	if n is Control:
		(n as Control).item_rect_changed.connect(_touch)
	n.child_entered_tree.connect(_on_child)
	n.child_exiting_tree.connect(_on_gone)
	for c in n.get_children():
		_watch(c)


func _on_child(c: Node) -> void:
	_watch(c)
	dirty = true


func _on_gone(_c: Node) -> void:
	dirty = true


func _touch() -> void:
	dirty = true


func _process(_d: float) -> void:
	var cl := _outer_layer()
	var vis := panel.visible and is_inside_tree() and get_parent() is CanvasItem and (get_parent() as CanvasItem).is_visible_in_tree() and (cl == null or cl.visible)
	if layer.visible != vis:
		layer.visible = vis
	visible = vis
	if not vis:
		_place_live(false)
		return
	var vp := get_viewport()
	var xf := vp.get_final_transform() # UI 배율 (창 늘림) — UI 좌표 × k = 창 픽셀
	var k := xf.get_scale().x
	var r := panel.get_global_rect().grow(PAD)
	var o := (xf * r.position).floor() # 화소 칸에 맞춘 원점 (창 픽셀)
	var px := Vector2i(ceili(r.size.x * k) + 2, ceili(r.size.y * k) + 2)
	var key := [o, px, k, panel.modulate, panel.self_modulate]
	if key != _key:
		_key = key
		if sv.size != px:
			sv.size = px
		sv.global_canvas_transform = Transform2D(0.0, Vector2(k, k), 0.0, xf.origin - o)
		sv.oversampling_override = k # 글자를 창 픽셀 크기로 (고도 글꼴 오버샘플 — 창 viewport 는 배율로 자동)
		# 그릴 자리는 _draw 의 사각형으로 (Control 자리는 gui 화소 맞춤 (snap_controls_to_pixels) 으로 UI 좌표 정수로 반올림돼 배율 2.25 면 1화소 밀림)
		_draw_rect = Rect2(get_global_transform_with_canvas().affine_inverse() * (xf.affine_inverse() * o), Vector2(px) / k)
		queue_redraw()
		dirty = true
	if S.style_gen != _style_gen:
		_style_gen = S.style_gen
		dirty = true
	if dirty or S.animating():
		dirty = false
		renders += 1
		sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	_place_live(true)


func _draw() -> void:
	draw_texture_rect(sv.get_texture(), _draw_rect, false)


# 산 칸: 노드 그림을 이 칸의 자식 칸으로 옮기고, 칸 변환 = 노드 부모의 전역 변환 (이 판 기준), 투명도 = 조상 투명도 곱, 잘림 = 판 안 스크롤 칸
func _place_live(on: bool) -> void:
	if _live.is_empty():
		return
	var off: bool = not on or (_cover.is_valid() and bool(_cover.call()))
	var inv := get_global_transform().affine_inverse()
	for l in _live:
		var n: CanvasItem = l[0]
		var rid: RID = l[1]
		if not is_instance_valid(n) or not n.is_inside_tree():
			RenderingServer.canvas_item_set_visible(rid, false)
			continue
		var par := n.get_parent() as CanvasItem
		var shown: bool = not off and par != null and par.is_visible_in_tree()
		RenderingServer.canvas_item_set_visible(rid, shown)
		if not shown:
			continue
		RenderingServer.canvas_item_set_parent(n.get_canvas_item(), rid)
		RenderingServer.canvas_item_set_transform(rid, inv * par.get_global_transform())
		var mod := Color.WHITE
		var a: Node = par
		var clip := Rect2()
		while a != null and a != layer:
			if a is CanvasItem:
				mod *= (a as CanvasItem).modulate
			if a is Control and (a as Control).clip_contents and clip == Rect2():
				clip = (a as Control).get_global_rect()
			a = a.get_parent()
		RenderingServer.canvas_item_set_modulate(rid, mod)
		var has_clip := clip != Rect2()
		RenderingServer.canvas_item_set_clip(rid, has_clip)
		if has_clip:
			var to_local := par.get_global_transform().affine_inverse()
			RenderingServer.canvas_item_set_custom_rect(rid, true, Rect2(to_local * clip.position, clip.size))

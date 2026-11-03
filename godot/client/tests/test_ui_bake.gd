# W16 2D 화면 판 그리기 줄이기: 구운 판 (ui/baked_panel.gd) 구조·다시 굽는 때, 같은 값이면 다시 그리지 않기
extends RefCounted

const Baked := preload("res://ui/baked_panel.gd")
const S := preload("res://ui/ui_style.gd")
const Hud := preload("res://ui/hud.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# 판은 장면 트리에 그대로 (입력·초점은 창 gui), 그리기만 SubViewport 로: CanvasLayer.custom_viewport, 미리 곱한 색 섞기, 화소 1:1
func test_wrap_moves_drawing_only() -> void:
	var p := PanelContainer.new()
	var b := Button.new()
	p.add_child(b)
	var w = Baked.wrap(p)
	check(w != p and w is Control, "감싼 칸이 생김")
	var layer: CanvasLayer = p.get_parent() as CanvasLayer
	check(layer != null and layer.custom_viewport is SubViewport and layer.get_parent() == w, "판 부모 = 그리기만 SubViewport 로 보내는 CanvasLayer")
	check(layer.transform == Transform2D.IDENTITY, "판 층 변환은 그대로 (클릭 자리 = 예전 자리)")
	var sv: SubViewport = layer.custom_viewport
	check(sv.transparent_bg and sv.disable_3d and sv.render_target_update_mode == SubViewport.UPDATE_DISABLED, "투명 바탕·3D 없음·평소엔 안 그림")
	check(w.material is CanvasItemMaterial and (w.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA, "미리 곱한 색으로 섞음 (반투명 판 색 그대로)")
	check(w.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and w.mouse_filter == Control.MOUSE_FILTER_IGNORE, "화소 1:1 · 클릭은 안 막음")
	# 다시 굽는 때: 판 안 노드가 다시 그려지거나 자리·보임이 바뀌면
	w.dirty = false
	b.draw.emit()
	check(w.dirty, "버튼 draw (hover·글) → 다시 구움")
	w.dirty = false
	b.item_rect_changed.emit()
	check(w.dirty, "자리·크기 → 다시 구움")
	w.dirty = false
	b.visibility_changed.emit()
	check(w.dirty, "보임 → 다시 구움")
	w.free()


func test_wrap_off_keeps_panel() -> void:
	Baked.enabled = false
	var p := PanelContainer.new()
	check(Baked.wrap(p) == p and p.get_parent() == null, "--no-bake 면 판 그대로 (예전처럼)")
	Baked.enabled = true
	p.free()


# 등장 애니 (S.slide_in·pop_down) 동안은 매 프레임 굽고, 빛 색이 바뀌면 (restyle) 다시
func test_anim_and_restyle_mark() -> void:
	var c := Control.new()
	S.anim_until = 0
	check(not S.animating(), "애니 없으면 안 굽")
	S.slide_in(c, 30.0)
	check(S.animating(), "미끄러져 들어오는 동안 굽")
	var g0 := S.style_gen
	S.restyle()
	check(S.style_gen == g0 + 1, "빛 색 바뀜 세기")
	S.anim_until = 0
	c.free()


# F·R 칸 테두리: 같은 값이면 안 씀 (StyleBox changed → 칸 다시 그림, 예전엔 갱신마다)
func test_slot_state_same_value_no_change() -> void:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	p.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	p.add_child(l)
	Hud.slot_state(l, 0.5, false)
	var n := [0]
	s.changed.connect(func(): n[0] += 1)
	Hud.slot_state(l, 0.5, false)
	check(n[0] == 0, "같은 상태면 StyleBox 안 바뀜 (%d번)" % n[0])
	Hud.slot_state(l, 0.5, true)
	check(n[0] > 0 and s.border_color == S.ACCENT and s.shadow_size == 14, "준비되면 노랑 테두리")
	p.free()

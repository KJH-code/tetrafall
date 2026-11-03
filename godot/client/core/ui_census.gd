# 2D 화면 판 비용 세기 (W16 2026-11-03): 화면 요소마다 '숨기면 2D 그리기·물체가 얼마나 주나' (빼 보기) + 노드·꾸밈 수 + 프레임마다 다시 그리는 수.
#   재연 (core/replay.gd --census) · 자동 조종 (--ui-census, 찍는 순간) 이 부름. 결과는 print 한 표 (README 순위표의 근거)
#   그리기 수는 창 viewport 의 2D (RENDER_INFO_TYPE_CANVAS) — 구운 판 SubViewport 의 2D 는 따로 (viewport 줄)
extends RefCounted


static func _canvas(vp: Viewport) -> Array:
	return [vp.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)]


# 이름 (스크립트 파일 · 종류 · 글 앞부분)
static func label_of(n: Node) -> String:
	var s := ""
	if n.get_script() != null:
		s = (n.get_script() as Script).resource_path.get_file().get_basename()
	else:
		s = n.get_class()
	var t = n.get("text")
	if t is String and t != "":
		s += " '%s'" % t.replace("\n", " ").left(14)
	return s


# 노드·꾸밈 수: [CanvasItem, Label, Button, TextureRect, StyleBoxFlat (기울기·그림자·둥근 모서리·테두리), 외곽선 글자, SubViewport]
static func stats(n: Node) -> Dictionary:
	var out := {"items": 0, "labels": 0, "buttons": 0, "tex": 0, "box": 0, "box_skew": 0, "box_shadow": 0, "box_round": 0, "outline": 0, "subvp": 0, "hidden": 0}
	var stack: Array[Node] = [n]
	var seen := {}
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is SubViewport:
			out.subvp += 1
			continue
		if c is CanvasItem and not (c as CanvasItem).visible:
			out.hidden += _count_items(c)
			continue
		for k in c.get_children():
			stack.append(k)
		if not (c is CanvasItem):
			continue
		out.items += 1
		if c is Label or c is RichTextLabel:
			out.labels += 1
		if c is BaseButton:
			out.buttons += 1
		if c is TextureRect:
			out.tex += 1
		if c is Control:
			var ct := c as Control
			if ct.get_theme_constant("outline_size") > 0 or ct.get_theme_constant("shadow_outline_size") > 0:
				out.outline += 1
			for nm in ["panel", "normal"]:
				if ct.has_theme_stylebox(nm):
					var sb := ct.get_theme_stylebox(nm)
					if sb is StyleBoxFlat and not seen.has(sb):
						seen[sb] = true
						var f := sb as StyleBoxFlat
						out.box += 1
						if f.skew != Vector2.ZERO:
							out.box_skew += 1
						if f.shadow_size > 0 and f.shadow_color.a > 0.0:
							out.box_shadow += 1
						if f.corner_radius_top_left + f.corner_radius_top_right + f.corner_radius_bottom_left + f.corner_radius_bottom_right > 0:
							out.box_round += 1
	return out


static func _count_items(n: Node) -> int:
	var k := 1 if n is CanvasItem else 0
	for c in n.get_children():
		k += _count_items(c)
	return k


# 빼 보기: node 의 보이는 자식마다 숨기고 한 프레임 그려 2D 그리기·물체가 준 만큼. 많이 주는 자식은 한 단 더 (깊이 depth 까지)
static func ablate(vp: Viewport, node: Node, depth: int, prefix: String, rows: Array, min_draws := 4) -> void:
	for c in node.get_children():
		if not (c is CanvasItem) or not (c as CanvasItem).visible or c is SubViewport:
			continue
		var ci := c as CanvasItem
		await RenderingServer.frame_post_draw
		var base := _canvas(vp)
		# 그리기만 끔 (RenderingServer 직접 — visible 을 바꾸면 보임 알림·다시 배치·미끄러져 들어오기 트윈이 돌아 다음 잼을 흐림)
		RenderingServer.canvas_item_set_visible(ci.get_canvas_item(), false)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var off := _canvas(vp)
		RenderingServer.canvas_item_set_visible(ci.get_canvas_item(), true)
		var name := prefix + label_of(c)
		var st := stats(c)
		rows.append([name, base[0] - off[0], base[1] - off[1], st])
		if depth > 0 and base[0] - off[0] >= min_draws and c.get_child_count() > 0:
			await ablate(vp, c, depth - 1, "  " + prefix, rows, min_draws)


# 다시 그리기 빈도: frames 프레임 동안 2D 노드가 draw 신호를 낸 수 (스크립트 무리별)
static func redraws(tree: SceneTree, root: Node, frames := 60) -> Dictionary:
	var counts := {}
	var cons := []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for k in n.get_children():
			stack.append(k)
		if n is CanvasItem:
			var a: Node = n
			while a != null and a.get_script() == null:
				a = a.get_parent()
			var key := (a.get_script() as Script).resource_path.get_file().get_basename() if a != null else "-"
			var who := key + "/" + label_of(n) + " @" + str(n.get_path()).get_slice("/", str(n.get_path()).get_slice_count("/") - 2) + "/" + str(n.get_index())
			var cb := func():
				counts[key] = int(counts.get(key, 0)) + 1
				counts[who] = int(counts.get(who, 0)) + 1
			n.draw.connect(cb)
			cons.append([n, cb])
	for i in frames:
		await tree.process_frame
	for c in cons:
		if is_instance_valid(c[0]):
			c[0].draw.disconnect(c[1])
	return counts


# 화면 하나 세기 (ui = ui.gd CanvasLayer). what = 화면 이름 (print 머리)
static func run(tree: SceneTree, what: String, depth := 6) -> void:
	var vp := tree.root
	var found := tree.root.find_children("*", "CanvasLayer", true, false)
	await RenderingServer.frame_post_draw
	var tot := _canvas(vp)
	var rows := []
	var baked := tree.root.find_children("Baked_*", "", true, false)
	var r0 := baked.map(func(b): return int(b.renders))
	var redraw := await redraws(tree, vp, 60)
	print("[UI 세기] 구운 판 다시 구움 (60프레임): %s" % ", ".join(range(baked.size()).map(func(i): return "%s %d (보임 %s)" % [baked[i].name, int(baked[i].renders) - r0[i], baked[i].visible])))
	var tweens := tree.get_processed_tweens().size()
	for cl in found:
		var layer := cl as CanvasLayer
		if not layer.visible or layer.get_viewport() != vp:
			continue
		await ablate(vp, layer, depth, "", rows)
	var fo := vp.gui_get_focus_owner()
	print("[UI 세기] 글자 칸 초점 %s" % (label_of(fo) if fo != null else "없음"))
	print("[UI 세기] %s · 창 2D 그리기 %d · 물체 %d · 도는 Tween %d · 다시 그림 (60프레임, 무리별) %s" % [what, tot[0], tot[1], tweens, str(redraw)])
	for r in rows:
		var st: Dictionary = r[3]
		if r[1] <= 0 and st.items < 8:
			continue
		print("  %-46s 그리기 %4d · 물체 %4d · 노드 %4d (숨은 %d) · 글 %d · 버튼 %d · 그림 %d · 상자 %d (사선 %d 그림자 %d 둥근 %d) · 외곽선 글 %d · SubViewport %d" % [r[0].left(46), r[1], r[2], st.items, st.hidden, st.labels, st.buttons, st.tex, st.box, st.box_skew, st.box_shadow, st.box_round, st.outline, st.subvp])
	for sv in tree.root.find_children("*", "SubViewport", true, false):
		var s := sv as SubViewport
		var d := _canvas(s)
		if d[0] > 0 and s.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			print("  [SubViewport %s %s 모드 %s] 2D 그리기 %d · 물체 %d" % [label_of(s.get_parent()), s.size, ["off", "once", "visible", "parent", "always"][s.render_target_update_mode], d[0], d[1]])

# 프레임 구성 (W37 2026-11-09): 한 프레임을 분류별로 — 그리기 호출·물체·삼각형 (화면 / 해 그림자 패스)·그림 메모리·CPU ms.
#   재연 (core/replay.gd) 이 --budget 으로 부름. 소프트웨어 렌더에서도 믿을 수 있는 숫자만 (삼각형·그리기·메모리·CPU ms) — GPU ms 는 RenderingServer 가 주면 한 줄 덧붙임.
#   방법: 보이는 3D 물체 (GeometryInstance3D) 를 가장 가까운 스크립트 붙은 조상 파일 (+ 클래스) 로 분류에 나누고, 분류마다 RenderingServer 로
#         그 물체들만 끈 채 한 프레임 그려 창·SubViewport 의 그리기·물체·삼각형 (화면 + 그림자) 이 준 만큼 = 그 분류의 몫 (합이 전체와 맞음).
#   그림 메모리: 분류 물체 재질이 쓰는 Texture2D (겹치면 처음 분류에만) 의 이미지 바이트 (압축 가져오기면 압축 크기 + 밉맵). 메시 버퍼는 분류별로 못 가름 → 전체만.
#   CPU ms: core/prof.gd 구간 이름 접두사 → 분류 (CPU_MAP).
extends RefCounted

const Prof := preload("res://core/prof.gd")

# 분류 이름 → 스크립트 파일 이름 (가장 가까운 스크립트 붙은 조상). 순서 = 표 순서
const GROUPS := [
	["몸 (코드 몸)", ["body.gd", "external.gd", "ext_shadow.gd", "ext_cloth.gd", "bodies.gd", "ragdoll.gd", "baked_batch.gd", "baked.gd", "chars.gd", "ghost_depth.gd", "figure_pose.gd"]],
	["1인칭 팔", ["viewmodel.gd"]],
	["지형·배경", ["scenery.gd", "sprouts.gd", "cells.gd", "lobby_dark.gd", "lobby_preview.gd", "world.gd", "g3.gd", "block_style.gd"]],
	["쌓인 블록", ["grid_view.gd"]],
	["떨어지는 칸·그림자 칸", ["pieces_view.gd"]],
	["건축 블록", ["bblocks.gd", "shards.gd"]],
	["위험", ["hazard_view.gd"]],
	["효과", ["fx.gd", "effects.gd", "ko.gd", "body_fx.gd", "hook_fx.gd", "light_fx.gd", "shots.gd", "marks.gd", "hunt_marks.gd", "tutorial_mark.gd", "sky_aids.gd", "game_light.gd", "victory.gd"]],
	["아이템·투사체", ["items_view.gd"]],
]
const LABEL_CAT := "이름표 (Label3D)"
const OTHER := "기타 (스크립트 없음)"

# Prof 구간 이름 접두사 → 분류 (앞에서부터 처음 맞는 것)
const CPU_MAP := [
	["몸", "몸 (코드 몸)"], ["world bodies", "몸 (코드 몸)"], ["래그돌", "몸 (코드 몸)"],
	["world 1인칭", "1인칭 팔"],
	["world 격자", "쌓인 블록·건축"], ["world 떨어지는 칸", "쌓인 블록·건축"], ["G3", "쌓인 블록·건축"],
	["world 위험", "위험"],
	["world 섬", "지형·하늘·배경"], ["world 판 빛", "지형·하늘·배경"], ["world 카메라", "지형·하늘·배경"], ["world 하늘", "지형·하늘·배경"],
	["world 이름표", "이름표"],
	["world body_fx", "효과"], ["world 표식", "효과"], ["fx", "효과"], ["이벤트→fx", "효과"], ["이벤트→body", "효과"], ["이벤트→hook", "효과"], ["이벤트→marks", "효과"], ["이벤트→shots", "효과"], ["world 아이템", "효과"],
	["ui", "HUD / 2D"], ["HUD", "HUD / 2D"], ["이벤트→hud", "HUD / 2D"], ["이벤트→tutorial", "HUD / 2D"], ["이벤트→practice", "HUD / 2D"],
	["net", "통신 (스냅샷 처리)"], ["store", "통신 (스냅샷 처리)"],
	["audio", "소리"], ["이벤트→audio", "소리"],
]


static func script_file(n: Node) -> String:
	var a: Node = n
	while a != null and a.get_script() == null:
		a = a.get_parent()
	return (a.get_script() as Script).resource_path.get_file() if a != null else ""


# 트리 밖 노드도 되는 경로 글자 (이름을 부모부터 이어 붙임)
static func _path(n: Node) -> String:
	var parts := []
	var a: Node = n
	while a != null:
		parts.append(str(a.name))
		a = a.get_parent()
	parts.reverse()
	return "/" + "/".join(parts)


static func category_of(n: Node) -> String:
	if n is Label3D:
		return LABEL_CAT
	var path := _path(n)
	if path.contains("/ext/") and (path.contains("SubViewport") or path.contains("/waist/")):
		return "1인칭 팔"
	if path.contains("/frame/ext/") or path.contains("/ext/"):
		return "몸 (외부 몸)"
	var f := script_file(n)
	if f == "body.gd" and (n.name == "batch" or str(n.name).begins_with("batch")):
		return "몸 (코드 몸 합침)"
	for g in GROUPS:
		if f in g[1]:
			return g[0]
	return OTHER if f == "" else "기타 (%s)" % f


# 보이는 3D 물체를 분류별로 [분류 → [GeometryInstance3D …]]
static func collect(root: Node) -> Dictionary:
	var out := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).is_visible_in_tree():
			continue
		if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
			continue
		for c in n.get_children():
			stack.append(c)
		if n is GeometryInstance3D and (n as GeometryInstance3D).visible:
			var k := category_of(n)
			if not out.has(k):
				out[k] = []
			out[k].append(n)
	return out


# 그리는 모든 viewport 의 [화면 그리기, 그림자 그리기, 화면 물체, 그림자 물체, 화면 삼각형, 그림자 삼각형]
static func info(tree: SceneTree) -> Array:
	var tot := [0, 0, 0, 0, 0, 0]
	var vps: Array[Viewport] = [tree.root]
	for sv in tree.root.find_children("*", "SubViewport", true, false):
		if (sv as SubViewport).render_target_update_mode != SubViewport.UPDATE_DISABLED:
			vps.append(sv)
	for vp in vps:
		var V := Viewport.RENDER_INFO_TYPE_VISIBLE
		var S := Viewport.RENDER_INFO_TYPE_SHADOW
		tot[0] += vp.get_render_info(V, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		tot[1] += vp.get_render_info(S, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		tot[2] += vp.get_render_info(V, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
		tot[3] += vp.get_render_info(S, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
		tot[4] += vp.get_render_info(V, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		tot[5] += vp.get_render_info(S, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	return tot


static func _set_visible(nodes: Array, on: bool) -> void:
	for n in nodes:
		if is_instance_valid(n):
			RenderingServer.instance_set_visible((n as GeometryInstance3D).get_instance(), on)


# 재질이 쓰는 Texture2D 들 (겹침 없이)
static func _textures(nodes: Array, seen: Dictionary) -> Array:
	var out := []
	for n in nodes:
		var mats := []
		var gi := n as GeometryInstance3D
		if gi.material_override != null:
			mats.append(gi.material_override)
		var mesh: Mesh = null
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
			for i in (n as MeshInstance3D).get_surface_override_material_count():
				var so = (n as MeshInstance3D).get_surface_override_material(i)
				if so != null:
					mats.append(so)
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			mesh = (n as MultiMeshInstance3D).multimesh.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var m = mesh.surface_get_material(i)
				if m != null:
					mats.append(m)
		while not mats.is_empty():
			var m: Material = mats.pop_back()
			if m == null or seen.has(m.get_instance_id()):
				continue
			seen[m.get_instance_id()] = true
			if m.next_pass != null:
				mats.append(m.next_pass)
			var texs := []
			if m is ShaderMaterial:
				var sm := m as ShaderMaterial
				if sm.shader != null:
					for u in sm.shader.get_shader_uniform_list():
						if u.type == TYPE_OBJECT:
							var t = sm.get_shader_parameter(u.name)
							if t is Texture2D:
								texs.append(t)
			elif m is BaseMaterial3D:
				var bm := m as BaseMaterial3D
				for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_EMISSION, BaseMaterial3D.TEXTURE_NORMAL]:
					var t := bm.get_texture(slot)
					if t != null:
						texs.append(t)
			for t in texs:
				if not seen.has(t.get_instance_id()):
					seen[t.get_instance_id()] = true
					out.append(t)
	return out


# 그림 한 장의 영상 메모리 (바이트 어림): 이미지 데이터 크기 (압축·밉맵 포함)
static func tex_bytes(t: Texture2D) -> int:
	if t is AtlasTexture or t is ViewportTexture or t is GradientTexture2D or t is NoiseTexture2D:
		return t.get_width() * t.get_height() * 4
	var img := t.get_image()
	if img == null:
		return t.get_width() * t.get_height() * 4
	return img.get_data_size()


static func cpu_category(name: String) -> String:
	for r in CPU_MAP:
		if name.begins_with(r[0]):
			return r[1]
	return "기타 (스크립트)"


# 표를 print. label = 장면 이름. cpu_frames = Prof 구간을 나눌 프레임 수 (0 이면 CPU 열 생략)
static func report(tree: SceneTree, label: String, cpu_frames := 0) -> Dictionary:
	var groups := collect(tree.root)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var base := info(tree)
	var seen_tex := {}
	var rows := []
	var keys := groups.keys()
	for k in keys:
		var nodes: Array = groups[k]
		var tex := _textures(nodes, seen_tex)
		var tb := 0
		for t in tex:
			tb += tex_bytes(t)
		await RenderingServer.frame_post_draw # 끄기 직전 켠 채의 값 (장면이 프레임마다 조금 달라서 분류마다 새로 잼)
		await RenderingServer.frame_post_draw
		var on_now := info(tree)
		_set_visible(nodes, false)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var off := info(tree)
		_set_visible(nodes, true)
		var d := []
		for i in 6:
			d.append(maxi(0, on_now[i] - off[i]))
		rows.append({"cat": k, "nodes": nodes.size(), "draws": d[0], "sdraws": d[1], "objs": d[2], "tris": d[4], "stris": d[5], "tex": tb})
	await RenderingServer.frame_post_draw
	# 3D 가 아닌 몫: 합과 전체의 차 (하늘 셰이더·후처리·SubViewport 합성 등) + 2D
	var sum := [0, 0, 0, 0, 0, 0]
	for r in rows:
		sum[0] += r.draws
		sum[1] += r.sdraws
		sum[2] += r.objs
		sum[4] += r.tris
		sum[5] += r.stris
	var canvas := tree.root.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var canvas_tris := tree.root.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	rows.sort_custom(func(a, b): return a.tris + a.stris > b.tris + b.stris)
	if OS.get_cmdline_user_args().has("--budget-names"): # 기타 분류 물체가 누구인지 (경로)
		for k in keys:
			if k.begins_with("기타"):
				for n in groups[k]:
					print("[구성] %s: %s (%s)" % [k, str(n.get_path()).right(90), n.get_class()])
	var cpu := {}
	if cpu_frames > 0 and Prof.on:
		for k in Prof.sums:
			var c := cpu_category(k)
			if k.contains("(번)") or k.contains("받은 스냅샷 수") or k.begins_with("net ·") or k.begins_with("HUD ·") or k.begins_with("store ·") or k.begins_with("몸 LOD") or k.begins_with("몸 figureAnim") or k.begins_with("몸 묶음") or k.begins_with("몸 움직임") or k.begins_with("몸 재질") or k.begins_with("몸 래그돌"):
				continue # 안쪽 구간 (바깥 구간이 이미 포함) 은 합에서 뺌
			cpu[c] = float(cpu.get(c, 0.0)) + float(Prof.sums[k][0]) / 1000.0 / maxf(1.0, cpu_frames)
	print("[구성] -- 프레임 구성 · %s --" % label)
	print("[구성] %-22s %5s %6s %6s %8s %8s %8s" % ["분류", "노드", "그리기", "그림자", "삼각형", "그림자삼각", "그림MB"])
	var jr := []
	for r in rows:
		print("[구성] %-22s %5d %6d %6d %8d %8d %8.1f" % [r.cat, r.nodes, r.draws, r.sdraws, r.tris, r.stris, r.tex / 1048576.0])
		jr.append(r)
	var rest := [base[0] - sum[0], base[1] - sum[1], base[4] - sum[4], base[5] - sum[5]]
	print("[구성] %-22s %5s %6d %6d %8d %8d" % ["그 밖 3D (하늘·후처리·합성)", "-", rest[0], rest[1], rest[2], rest[3]])
	print("[구성] %-22s %5s %6d %6s %8d" % ["2D (창 viewport)", "-", canvas, "-", canvas_tris])
	print("[구성] %-22s %5s %6d %6d %8d %8d" % ["합계 (3D)", "-", base[0], base[1], base[4], base[5]])
	print("[구성] 영상 메모리 %.1fMB (그림 %.1f · 쓰는 곳 %.1f · 합 %.1f)" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	if not cpu.is_empty():
		var ck := cpu.keys()
		ck.sort_custom(func(a, b): return cpu[a] > cpu[b])
		print("[구성] CPU ms/프레임 (스크립트 구간): %s" % " · ".join(ck.map(func(k): return "%s %.2f" % [k, cpu[k]])))
	var out := {"label": label, "rows": jr, "total": base, "canvas": canvas, "cpu": cpu, "vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0}
	print("[구성json] " + JSON.stringify(out))
	return out

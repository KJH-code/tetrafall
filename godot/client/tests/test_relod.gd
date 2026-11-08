# W31 판 LOD 다시 굽기 (tools/blender/tripo/relod.py·relod_merge.mjs): 닌자·탱크·갈고리 판 LOD (high·medium·low) 가 새 UV·1024 아틀라스로 삼각형 3~5천이고,
# stage 는 그대로 (원본 1.7~1.9만), 몸 색 칸 (UV2.x) 넓이가 stage 와 거의 같고, 아틀라스는 LOD 마다 따로 VRAM 압축, 1인칭 팔은 그대로. 사냥꾼은 건드리지 않음 (이미 3~5천).
extends RefCounted

var errors: Array = []

const BUDGET := {"high": 5000, "medium": 4000, "low": 3000}
const IDS := ["ninja", "tank", "hook"]
const VM_TRIS := {"ninja": 3430, "tank": 3845, "hook": 1774} # 1인칭 팔 (W31 이전과 같음)
const MASK_AREA_REL := 0.25 # stage 몸 색 칸 넓이와 LOD 의 차 (상대) 한도 — 꼭짓점 단위 칸이라 가장자리가 삼각형 하나만큼 어긋남
const ISLAND_MAX := {"high": 1100, "medium": 1000, "low": 900} # UV 조각 (이음선으로 갈린 덩어리) 수 — Smart UV 큰 조각 (예전 판 LOD 3100)


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


# 메시 노드 이름 → {tris, mask (UV2.x > 0.5 인 삼각형의 3D 넓이 비율), islands, verts, tex (재질 알베도 크기)}
func _stats(scene: Node, name: String) -> Dictionary:
	var mi: MeshInstance3D = scene.find_child(name, true, false)
	if mi == null or mi.mesh == null:
		return {}
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2] if arr[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var tris := idx.size() / 3
	var area := 0.0
	var marea := 0.0
	var parent := PackedInt32Array()
	parent.resize(pos.size())
	for i in pos.size():
		parent[i] = i
	for t in tris:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		var ar := (pos[b] - pos[a]).cross(pos[c] - pos[a]).length() * 0.5
		area += ar
		if uv2.size() == pos.size() and (uv2[a].x + uv2[b].x + uv2[c].x) / 3.0 > 0.5:
			marea += ar
		for v in [b, c]:
			var ra := _find(parent, a)
			var rv := _find(parent, v)
			if ra != rv:
				parent[rv] = ra
	var roots := {}
	for t in tris:
		roots[_find(parent, idx[t * 3])] = true
	var tex_w := 0
	var mat := mi.mesh.surface_get_material(0)
	if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
		tex_w = (mat as BaseMaterial3D).albedo_texture.get_width()
	return {"tris": tris, "mask": marea / maxf(area, 0.000001), "islands": roots.size(), "verts": pos.size(), "uv2": uv2.size() == pos.size(), "tex": tex_w}


func _find(p: PackedInt32Array, x: int) -> int:
	while p[x] != x:
		p[x] = p[p[x]]
		x = p[x]
	return x


func _cfg(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/ext/%s.json" % id))


func test_lod_triangle_budget_and_names() -> void:
	for id in IDS:
		var cfg := _cfg(id)
		var lods: Dictionary = cfg.lods
		var seen := {}
		for lv in BUDGET:
			var nm: String = lods[lv]
			check(not seen.has(nm), "%s: 판 LOD %s 는 서로 다른 메시 (%s)" % [id, lv, nm])
			seen[nm] = true
		var scene: Node = (load("res://assets/models/ext/%s.glb" % id) as PackedScene).instantiate()
		var st := _stats(scene, str(lods.stage))
		check(int(st.tris) >= 17000, "%s stage 는 원본 그대로 (%d)" % [id, int(st.tris)])
		for lv in BUDGET:
			var s := _stats(scene, str(lods[lv]))
			check(not s.is_empty() and int(s.tris) <= int(BUDGET[lv]) and int(s.tris) >= int(BUDGET[lv]) - 600, "%s %s 삼각형 %d (≤ %d)" % [id, lv, int(s.get("tris", -1)), int(BUDGET[lv])])
		scene.free()


func test_lod_uv_islands_and_mask_area() -> void:
	for id in IDS:
		var cfg := _cfg(id)
		var scene: Node = (load("res://assets/models/ext/%s.glb" % id) as PackedScene).instantiate()
		var st := _stats(scene, str(cfg.lods.stage))
		check(float(st.mask) > 0.01, "%s stage 에 몸 색 칸이 있음 (%.3f)" % [id, float(st.mask)])
		for lv in BUDGET:
			var s := _stats(scene, str(cfg.lods[lv]))
			check(bool(s.uv2), "%s %s: 몸 색 칸 UV2 가 있음" % [id, lv])
			check(int(s.islands) <= int(ISLAND_MAX[lv]), "%s %s UV 조각 %d (≤ %d)" % [id, lv, int(s.islands), int(ISLAND_MAX[lv])])
			check(absf(float(s.mask) - float(st.mask)) <= float(st.mask) * MASK_AREA_REL, "%s %s 몸 색 칸 넓이 %.4f (stage %.4f ±%d%%)" % [id, lv, float(s.mask), float(st.mask), int(MASK_AREA_REL * 100)])
			check(int(s.verts) <= int(s.tris) * 2, "%s %s 꼭짓점 %d (삼각형 ×2 이하)" % [id, lv, int(s.verts)])
		scene.free()


func test_lod_atlases_separate_and_compressed() -> void:
	for id in IDS:
		var stage_p := "res://assets/models/ext/%s_%s_atlas.jpg" % [id, id]
		var stage_tex = load(stage_p)
		check(stage_tex != null and (stage_tex as Texture2D).get_width() == 2048, "%s stage 아틀라스 2048" % id)
		for n in [1, 2, 3]:
			var p := "res://assets/models/ext/%s_%s_atlas_lod%d.jpg" % [id, id, n]
			check(FileAccess.get_file_as_string(p + ".import").contains("compress/mode=2"), "%s LOD%d 아틀라스 VRAM 압축 (가져오기)" % [id, n])
			var tex = load(p)
			check(tex != null and (tex as Texture2D).get_width() == 1024 and (tex as Texture2D).get_image().is_compressed(), "%s LOD%d 아틀라스 1024 압축 상태" % [id, n])
		var scene: Node = (load("res://assets/models/ext/%s.glb" % id) as PackedScene).instantiate()
		var cfg := _cfg(id)
		for lv in BUDGET:
			var s := _stats(scene, str(cfg.lods[lv]))
			check(int(s.tex) == 1024, "%s %s 재질 알베도 1024 (%d)" % [id, lv, int(s.tex)])
		var vm := _stats(scene, "%s_vm" % id)
		check(int(vm.tris) == int(VM_TRIS[id]), "%s 1인칭 팔은 그대로 (%d)" % [id, int(vm.tris)])
		scene.free()


func test_hunter_untouched() -> void:
	var cfg := _cfg("hunter")
	check(cfg.lods.high == "hunter_lod1" and cfg.lods.medium == "hunter_lod2" and cfg.lods.low == "hunter_lod3", "사냥꾼 LOD 이름 그대로")
	var scene: Node = (load("res://assets/models/ext/hunter.glb") as PackedScene).instantiate()
	check(_stats(scene, "hunter_lod1").tris <= 5200 and _stats(scene, "hunter_lod3").tris <= 3200, "사냥꾼은 이미 3~5천")
	scene.free()

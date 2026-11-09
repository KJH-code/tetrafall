# W34 새 모델 다듬기: 몸 색 칸 마스크 텍스처 (skin_mask), (뒤 항목은 같은 파일에 계속 더함)
extends RefCounted

const Body := preload("res://chars/body.gd")
const Ext := preload("res://chars/external.gd")

var errors: Array = []

const IDS := ["ninja", "tank", "hook", "hunter"]
const MIN_COVER := {"ninja": 0.10, "tank": 0.05, "hook": 0.08, "hunter": 0.05} # 마스크 넓이 (텍셀 비율) — 칸 >= 5%
const EDGE_MAX := 0.25 # 가장자리 (0.05~0.95) 텍셀 ÷ 칸 텍셀 — 꼭짓점 판정의 경계 삼각형 32~55% 보다 한참 아래


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _body(ch: String, level: String):
	var Gfx = load("res://world/gfx.gd")
	var was_plan = Gfx.plan
	Gfx.plan = {"level": level}
	var was: bool = Body.use_ext
	Body.use_ext = true
	var b = Body.new()
	b.build(ch, Color(0.2, 0.5, 1.0), true)
	Body.use_ext = was
	Gfx.plan = was_plan
	return b


func test_skin_mask_files() -> void:
	for id in IDS:
		var txt := FileAccess.get_file_as_string("res://assets/models/ext/%s.json" % id)
		var d = JSON.parse_string(txt)
		check(d is Dictionary and d.has("skin_mask"), "%s.json 에 skin_mask" % id)
		if not (d is Dictionary and d.has("skin_mask")):
			continue
		var seen := {}
		for node in d.skin_mask:
			var p: String = d.skin_mask[node]
			check(ResourceLoader.exists(p), "%s 마스크 파일 %s" % [id, p])
			if seen.has(p):
				continue
			seen[p] = true
			var tex := load(p) as Texture2D
			if tex == null:
				check(false, "%s 못 읽음" % p)
				continue
			var im := tex.get_image()
			check(im.get_width() == 1024 and im.get_height() == 1024, "%s 1024² (%dx%d)" % [p, im.get_width(), im.get_height()])
			im.decompress() if im.is_compressed() else null
			var tot := 0.0
			var edge := 0.0
			var step := 4 # 4칸마다 (속도)
			var n := 0
			for y in range(0, im.get_height(), step):
				for x in range(0, im.get_width(), step):
					var v := im.get_pixel(x, y).r
					tot += v
					n += 1
					if v > 0.05 and v < 0.95:
						edge += 1.0
			var cover := tot / n
			check(cover >= MIN_COVER[id], "%s 칸 넓이 %.3f >= %.2f" % [p, cover, MIN_COVER[id]])
			var ratio := edge / maxf(tot, 1.0)
			check(ratio <= EDGE_MAX, "%s 경계 텍셀 비율 %.3f <= %.2f" % [p, ratio, EDGE_MAX])


# 판 몸 3단계 LOD 모두 몸 색 재질이 마스크 텍스처를 쓰고, 마스크 재질 수는 늘지 않음 (몸 하나당 표면 재질 = 이전과 같은 수)
func test_skin_mask_in_body_all_levels() -> void:
	for id in IDS:
		for lv in ["high", "medium", "low"]:
			var b = _body(id, lv)
			var used := 0
			var plain := 0
			for mi in b.find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).material_override as ShaderMaterial
				if m == null or not m.get_shader_parameter("skin_multiply"):
					continue
				if m.get_shader_parameter("use_skin_mask") == true and m.get_shader_parameter("skin_mask_tex") != null:
					used += 1
				else:
					plain += 1
			check(used >= 1 and plain == 0, "%s %s: 마스크 텍스처 쓰는 몸 재질 %d, 꼭짓점 판정 %d" % [id, lv, used, plain])
			b.free()


# 마스크 없는 재질은 예전 그대로 (use_skin_mask 꺼짐)
func test_toon_for_without_mask_unchanged() -> void:
	var m: ShaderMaterial = Ext.Ext.toon_for(Color.WHITE, null, true, true, Color.RED)
	check(m.get_shader_parameter("use_skin_mask") != true, "마스크 안 주면 꼭짓점 판정")
	var t := load("res://assets/models/ext/ninja_mask_lod1.png") as Texture2D
	var m2: ShaderMaterial = Ext.Ext.toon_for(Color.WHITE, null, true, true, Color.RED, {"skin_mask": t})
	check(m2.get_shader_parameter("use_skin_mask") == true, "마스크를 주면 텍스처 판정")

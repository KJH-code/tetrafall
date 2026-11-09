# W39 최적화 5차: 새 모델 알베도 텍스처 지연 로드 (항목 2) · (뒤 항목들은 아래에 이어 붙임)
extends RefCounted

const Ext := preload("res://chars/external.gd")
const Chars := preload("res://chars/chars.gd")
const Gfx := preload("res://world/gfx.gd")
const Body := preload("res://chars/body.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func _atlas(id: String, suf := "") -> String:
	return "res://assets/models/ext/%s_%s_atlas%s.jpg" % [id, id, suf]


func _body(id: String, level := "high", stage := false) -> Node3D:
	var was: Dictionary = Gfx.plan
	var was_e: bool = Body.use_ext
	Gfx.plan = {"level": level}
	Body.use_ext = true
	Ext.stage = stage
	var b := Chars.make_body(id, Color(0.8, 0.3, 0.3))
	Ext.stage = false
	Body.use_ext = was_e
	Gfx.plan = was
	return b


func _tex_id(body: Node3D) -> int:
	for pt in body.ext.parts:
		if pt.tex != null:
			return (pt.tex as Object).get_instance_id()
	return 0


# 모델 정보만 읽었을 땐 알베도 텍스처가 하나도 안 올라와 있다 (장면이 붙잡지 않음), 표면에는 경로가 적혀 있음
func test_lazy_tex_info_holds_no_textures() -> void:
	var keep := Ext.lazy_tex
	Ext.lazy_tex = true
	for id in ["ninja", "tank", "hook"]:
		var info = Ext.load_char(id)
		check(info != null, "%s 읽음" % id)
		if info == null:
			continue
		for suf in ["", "_lod1", "_lod2", "_lod3"]:
			check(not ResourceLoader.has_cached(_atlas(id, suf)), "%s%s 알베도: 몸이 없으면 안 올라와 있음" % [id, suf])
		var n := 0
		for sf in info.surfs:
			if str(sf.tex_path) != "":
				n += 1
			check(sf.tex == null, "%s 표면의 텍스처 참조는 비어 있음" % id)
		check(n >= 4, "%s: 경로가 적힌 표면 %d" % [id, n])
	Ext.lazy_tex = keep


# 판 몸 = 고른 LOD 알베도만 올림 (보통이면 LOD2 만), 몸이 사라지면 같이 풀림, 같은 캐릭터 몸끼리는 한 텍스처를 나눠 씀
func test_lazy_tex_only_picked_lod_and_shared() -> void:
	var keep := Ext.lazy_tex
	Ext.lazy_tex = true
	var a := _body("ninja", "medium")
	check(a.ext != null, "닌자 붙음")
	check(ResourceLoader.has_cached(_atlas("ninja", "_lod2")), "보통: LOD2 알베도 올라옴")
	for suf in ["", "_lod1", "_lod3"]:
		check(not ResourceLoader.has_cached(_atlas("ninja", suf)), "보통: ninja%s 알베도는 안 올라옴" % suf)
	var b := _body("ninja", "medium")
	var ta := _tex_id(a)
	var tb := _tex_id(b)
	check(ta != 0 and ta == tb, "같은 캐릭터 두 몸이 알베도 텍스처 하나를 나눠 씀")
	a.free()
	check(ResourceLoader.has_cached(_atlas("ninja", "_lod2")), "한 몸이 남아 있으면 텍스처도 남음")
	b.free()
	check(not ResourceLoader.has_cached(_atlas("ninja", "_lod2")), "몸이 모두 사라지면 알베도도 풀림")
	Ext.lazy_tex = keep


# 대기실 큰 캐릭터 (stage) 는 stage 알베도만, 판 LOD 알베도는 안 올림
func test_lazy_tex_stage_body() -> void:
	var keep := Ext.lazy_tex
	Ext.lazy_tex = true
	var s := _body("tank", "high", true)
	check(ResourceLoader.has_cached(_atlas("tank")), "큰 캐릭터: stage 알베도 올라옴")
	for suf in ["_lod1", "_lod2", "_lod3"]:
		check(not ResourceLoader.has_cached(_atlas("tank", suf)), "큰 캐릭터: tank%s 안 올라옴" % suf)
	s.free()
	check(not ResourceLoader.has_cached(_atlas("tank")), "큰 캐릭터를 치우면 stage 알베도도 풀림")
	Ext.lazy_tex = keep


# 끄면 (--no-lazy-tex) 예전처럼 장면 정보가 텍스처를 쥐고 있음 — 몸 모습은 같은 텍스처
func test_lazy_tex_off_keeps_old_behavior() -> void:
	var keep := Ext.lazy_tex
	Ext.lazy_tex = false
	Ext._cache.erase("hook")
	var info = Ext.load_char("hook")
	var held := 0
	for sf in info.surfs:
		if sf.tex != null:
			held += 1
	check(held > 0 or Ext._tex_paths.size() > 0, "끄면 표면이 텍스처를 쥠 (또는 이미 벗겨진 장면: 경로로 읽음)")
	var t = null
	for sf in info.surfs:
		if str(sf.node) == str(info.cfg.lods.high):
			t = Ext.Ext.tex_of(sf)
	check(t != null, "끄고도 몸 텍스처가 나옴")
	Ext.lazy_tex = keep
	Ext._cache.erase("hook")

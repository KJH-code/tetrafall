# 판 몸 그림자 전용 저폴리 (W32): 외부 (Blender) 모델은 화질별 LOD (높음 5000 · 보통 4000 · 낮음 3000 삼각형) 중 하나만 화면에 그리는데,
# 해 그림자 패스는 그 메시를 한 번 더 그림 (8명 판에서 그림자 패스 = 3D 삼각형의 38%). 그림자는 모양이 뭉툭해도 눈에 안 띄므로
# 보이는 메시는 그림자를 끄고 (cast_shadow OFF), 가장 낮은 LOD 메시를 같은 뼈대·스킨으로 하나 더 두어 그림자만 던지게 함 (SHADOWS_ONLY, 재질 없음).
# 보이는 LOD 가 이미 가장 낮으면 (화질 낮음 — 그림자도 꺼짐) · 대기실 큰 캐릭터·초상·1인칭 쌍둥이면 안 함. 순수 판정 caster_node, 만들기 add (chars/external.gd Ext._surfaces 가 부름)
# 테스트 tests/test_shadow.gd
extends RefCounted

const WC := preload("res://world/world_config.gd")


# 그림자만 던질 LOD 노드 이름 ("" = 안 함: 보이는 메시가 그림자도 던짐)
static func caster_node(cfg: Dictionary, lod: String, third: bool, on_stage: bool) -> String:
	if not WC.shadow_opt or not bool(WC.SHADOW.caster_lod) or not third or on_stage or lod == "":
		return ""
	var lods: Dictionary = cfg.get("lods", {})
	var low := str(lods.get("low", ""))
	if low == "" or low == lod or low == str(lods.get("stage", "")):
		return ""
	return low


# info.surfs 중 노드 이름이 name 인 표면마다 그림자 전용 메시 하나. 원래 메시 자리에 (같은 부모·변환·스킨·뼈대). 만든 메시 목록을 돌려줌
static func add(model: Node, sk: Skeleton3D, surfs: Array, name: String) -> Array:
	var made := []
	for sf in surfs:
		if str(sf.get("node", "")) != name:
			continue
		var orig := model.get_node_or_null(sf.path) as MeshInstance3D
		if orig == null or sf.mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "%s_sh%d" % [orig.name, int(sf.surf)]
		mi.mesh = sf.mesh
		mi.transform = orig.transform
		if sf.skinned:
			mi.skin = orig.skin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		orig.get_parent().add_child(mi)
		if sf.skinned:
			mi.skeleton = mi.get_path_to(sk)
		made.append(mi)
	return made

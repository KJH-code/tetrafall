# 재질 첫 등장 기록 (W42 항목 4, --mat-first): 판 (countdown 이후) 에서 처음 그려진 재질 '모양' 을 찾음 — 대기실·메뉴 (미리 그리기가 도는 동안) 에 한 번도 트리에 없었던 것 =
# 미리 그리기가 못 덮은 후보 (고도 Compatibility 는 재질·메시 종류 조합마다 처음 그릴 때 셰이더를 컴파일). 매 프레임 전체 트리를 훑음 (측정 도구라 비용은 신경 안 씀).
# 모양 열쇠: 재질 종류 (ShaderMaterial = 셰이더 파일, BaseMaterial3D = 기능 조합) + next_pass·overlay + 그리는 노드 종류 (메시·스킨 메시·MultiMesh·글자·그림·파티클·반짝 줄)
# 확인 방법: 순수 함수 key_of 는 tests/test_w42.gd
extends Node

const Hitch := preload("res://core/hitch.gd")

var pre := {} # 열쇠 → 처음 본 ms (판 시작 전)
var game := {} # 열쇠 → [처음 본 ms, 직전 이벤트, 처음 본 위치 경로] (판 시작 뒤에 처음)
var game_since := -1.0
var last_event := ""
var frames := 0


func _ready() -> void:
	process_priority = 1000 # 모든 그리기 코드가 낸 뒤에
	Store.game_event.connect(func(e): last_event = "%s" % str(e.get("type", "")))


func _process(_dt: float) -> void:
	frames += 1
	var ph := str(Store.state.get("phase", "")) if not Store.state.is_empty() else ""
	var started := ph == "countdown" or ph == "playing" or ph == "over"
	var now := Time.get_ticks_msec() / 1000.0
	if started and game_since < 0.0:
		game_since = now
	var seen := {}
	_walk(get_tree().root, seen)
	for k in seen:
		if pre.has(k) or game.has(k):
			continue
		if not started:
			pre[k] = now
		else:
			game[k] = [now - game_since, last_event, seen[k]]


func _walk(n: Node, out: Dictionary) -> void:
	if n is Node3D and not (n as Node3D).is_visible_in_tree():
		# 숨은 노드 (미리 그리기 전 비활성) 는 안 그려지므로 안 셈 — 자식도 숨음
		return
	for k in keys_of(n):
		if not out.has(k):
			out[k] = str(n.get_path()) if n.is_inside_tree() else n.name
	for c in n.get_children():
		_walk(c, out)


# 노드가 그리는 재질 모양 열쇠들 (순수: 노드·재질만 봄)
static func keys_of(n: Node) -> Array:
	var out := []
	var kind := ""
	var mats := []
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.layers == 0:
			return out
		kind = "skin" if mi.skin != null else "mesh"
		if mi.material_override != null:
			mats.append(mi.material_override)
		else:
			for si in mi.mesh.get_surface_count():
				var m = mi.get_surface_override_material(si)
				if m == null:
					m = mi.mesh.surface_get_material(si)
				mats.append(m)
		if mi.material_overlay != null:
			mats.append(mi.material_overlay)
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null or mm.instance_count == 0 or mm.visible_instance_count == 0:
			return out
		kind = "multi" + ("+col" if mm.use_colors else "") + ("+cd" if mm.use_custom_data else "")
		if (n as MultiMeshInstance3D).material_override != null:
			mats.append((n as MultiMeshInstance3D).material_override)
		else:
			for si in mm.mesh.get_surface_count():
				mats.append(mm.mesh.surface_get_material(si))
	elif n is Label3D:
		out.append("label3d")
		return out
	elif n is Sprite3D:
		out.append("sprite3d")
		return out
	elif n is GPUParticles3D or n is CPUParticles3D:
		out.append("particles:" + n.get_class())
		return out
	else:
		return out
	for m in mats:
		if m != null:
			out.append("%s|%s" % [kind, mat_key(m)])
	return out


static func mat_key(m: Material, depth := 0) -> String:
	var s := ""
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		s = "S:" + (sh.resource_path.get_file() if sh != null and sh.resource_path != "" else "inline")
	elif m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		s = "B:sh%d,tr%d,bl%d,cu%d,dt%d,bb%d,vc%d,tx%d,em%d,fog%d,dd%d" % [b.shading_mode, b.transparency, b.blend_mode, b.cull_mode, 1 if b.no_depth_test else 0, b.billboard_mode, 1 if b.vertex_color_use_as_albedo else 0, 1 if b.albedo_texture != null else 0, 1 if b.emission_enabled else 0, 1 if b.disable_fog else 0, b.depth_draw_mode]
	else:
		s = m.get_class()
	if m.next_pass != null and depth < 3:
		s += ">" + mat_key(m.next_pass, depth + 1)
	return s


func report() -> Array:
	var rows := []
	for k in game:
		rows.append([float(game[k][0]), k, str(game[k][1]), str(game[k][2])])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	return rows.map(func(r): return "[첫 재질] 판 +%.1fs | %s | 직전 이벤트 %s | %s" % [r[0], r[1], r[2], r[3]])

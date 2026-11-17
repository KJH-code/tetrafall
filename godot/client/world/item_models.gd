# 아이템 코드 모델 (c10-u2): world/item_look.gd 의 조각 표 → 종류마다 ArrayMesh 하나 (정점 색, 한 번 만들어 나눠 씀).
# 기본 도형 (SphereMesh·CylinderMesh·BoxMesh) 의 정점 배열을 조각마다 옮겨 한 표면으로 합침 → 종류마다 그리기 한 번 (+ 외곽선). 재질은 G3 툰 (정점 색) — 새 셰이더 없음.
# 쓰는 곳: world/items_view.gd (바닥 아이템·넉백 투사체), world/shots.gd (놓인 폭탄 — 몸통과 빛나는 조각을 따로), tools/item_sheet.gd
extends RefCounted

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const IL := preload("res://world/item_look.gd")
const G3 := preload("res://shaders/g3.gd")

const ALL := -1 # build 의 pick: 조각 전부
const BODY := 0 # 빛남 표시가 없는 조각만
const GLOW := 1 # 빛남 표시 조각만

static var _cache := {}


# 종류의 모델. 표에 없는 종류 (control·모르는 것) 는 예전 상자 (BoxMesh WC.ITEM_SIZE)
static func mesh(kind: String) -> Mesh:
	var key := kind if IL.PARTS.has(kind) else str(IL.BOX)
	if not _cache.has(key):
		_cache[key] = box_mesh() if key == IL.BOX else build(IL.PARTS[key], IL.SIZE)
	return _cache[key]


static func box_mesh() -> BoxMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * WC.ITEM_SIZE
	return box


# 넉백 투사체: 긴 변 = 지름
static func proj_mesh() -> ArrayMesh:
	if not _cache.has("#proj"):
		_cache["#proj"] = build(IL.PROJ, C.PROJECTILE_RADIUS * 2.0)
	return _cache["#proj"]


# 놓인 폭탄: [몸통, 빛나는 조각 (띠·불씨)] — 둘을 겹치면 바닥 아이템 폭탄 (mesh("bomb")) 과 같은 모양. size = 긴 변
static func bomb_split(size: float) -> Array:
	var key := "#bomb%f" % size
	if not _cache.has(key):
		_cache[key] = [build(IL.PARTS.bomb, size, BODY), build(IL.PARTS.bomb, size, GLOW)]
	return _cache[key]


# 모델 재질: 툰 + 정점 색 + 제 색 빛남 (IL.GLOW) + 공용 잉크 외곽선 (world/bblocks.gd 판자 조각과 같은 갈래 — G3.prewarm 이 데움). 부를 때마다 새 재질 (나눠 쓰는 쪽이 하나 들고 있음)
static func material(opts := {}) -> ShaderMaterial:
	var o := {"vertex_color": true, "color_glow": IL.GLOW}
	o.merge(opts)
	return G3.toon_material(Color.WHITE, o)


# 표에 없는 종류 상자의 재질 (예전 아이템 상자 그대로: 아이템 빛 노랑 + 스스로 빛남)
static func box_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Co.color(C.GAME_LIGHT_ITEM)
	m.emission_enabled = true
	m.emission = Co.color(C.GAME_LIGHT_ITEM) * WC.ITEM_GLOW
	return m


static func _shape(kind: String, d: Array) -> PrimitiveMesh:
	if kind == "sph":
		var s := SphereMesh.new()
		s.radius = float(d[0])
		s.height = float(d[0]) * 2.0
		s.radial_segments = int(d[1])
		s.rings = int(d[2])
		return s
	if kind == "cyl":
		var c := CylinderMesh.new()
		c.top_radius = float(d[0])
		c.bottom_radius = float(d[1])
		c.height = float(d[2])
		c.radial_segments = int(d[3])
		c.rings = 1
		return c
	var b := BoxMesh.new()
	b.size = Vector3(d[0], d[1], d[2])
	return b


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func _glows(part: Array) -> bool:
	return part.size() > 6 and bool(part[6])


# 조각 표 → 메시 하나. 조각 전부의 테두리 상자로 긴 변이 size 가 되게 고르게 키우고 세로 가운데를 0 으로 (pick 으로 일부만 담아도 크기·자리는 전부 기준 — 겹치면 딱 맞음)
static func build(parts: Array, size: float, pick := ALL) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var lo := Vector3.ONE * INF
	var hi := Vector3.ONE * -INF
	for part in parts:
		var a := _shape(str(part[0]), part[1]).get_mesh_arrays()
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var xf := Transform3D(Basis.from_euler(_v3(part[3])).scaled_local(_v3(part[4])), _v3(part[2]))
		var nb := xf.basis.inverse().transposed() # 고르지 않은 배율에도 법선이 면에 서게
		var take := pick == ALL or (pick == GLOW) == _glows(part)
		var col := Co.color(int(part[5]))
		var base := verts.size()
		for i in vs.size():
			var v := xf * vs[i]
			lo = lo.min(v)
			hi = hi.max(v)
			if take:
				verts.append(v)
				norms.append((nb * ns[i]).normalized())
				cols.append(col)
		if take:
			for i in ix:
				idx.append(base + i)
	var span := hi - lo
	var k := size / maxf(1e-6, maxf(span.x, maxf(span.y, span.z)))
	var mid_y := (lo.y + hi.y) * 0.5
	for i in verts.size():
		verts[i] = Vector3(verts[i].x, verts[i].y - mid_y, verts[i].z) * k
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# 삼각형 수 (표면 0)
static func tri_count(m: Mesh) -> int:
	var a := m.surface_get_arrays(0)
	var ix = a[Mesh.ARRAY_INDEX]
	return (ix.size() if ix != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3

# c7 신호 고리 모양 (world/body_fx.gd 가 몸을 따라가게 그림): F 준비 예고 고리 · 스킬·필살기 발밑 고리.
# 예전: 예고는 효과 풀의 얇은 흰 고리 (밝은 바닥에서 안 보임), 스킬·필살기는 부를 때마다 새로 만든 한 색 띠.
# 지금: 반지름 1 기준 단면을 '띠' 로 나눠 정점 색으로 칠한 메시 (흰 심 + 쓴 사람 색 띠 + 잉크 테) — 밝은 바닥에선 잉크·색, 어두운 바닥에선 흰 심이 읽힘.
# 메시는 (종류, 색) 마다 한 번만 만들어 기억. 재질은 고리마다 (알파가 따로 흐름) — 모양은 world/warm_scan.gd STD_KEYS 에 있는 것 (새 셰이더 없음).
# 순수 계산 (단면·반지름·알파 곡선) 은 tests/test_fx.gd test_c7_* 가 고정
extends RefCounted

const Co := preload("res://core/coords.gd")
const G3C := preload("res://shaders/g3_config.gd")

# 단면 띠: [안 반지름, 바깥 반지름, 안쪽 칠, 바깥쪽 칠]. 칠 = "clear" (흰색 알파 0) · "core" (흰 심) · "tint" (쓴 사람 색) · "ink" (외곽선 색, 알파 INK_ALPHA)
# windup: 폭 = 반지름의 24% (0.76 → 1.0). aura: 폭 14% (예전 ring_mesh(0.5, 0.58) 의 띠 폭 그대로)
const LOOKS := {
	"windup": {"seg": 48, "bands": [[0.76, 0.80, "clear", "core"], [0.80, 0.88, "core", "core"], [0.88, 0.97, "tint", "tint"], [0.97, 1.0, "ink", "ink"]]},
	"aura": {"seg": 40, "bands": [[0.86, 0.93, "core", "core"], [0.93, 1.0, "tint", "tint"]]},
}
const INK_ALPHA := 0.6
# F 준비 예고 고리: 반지름 (칸) r0 → r1 로 ease-out, 수명의 hold 까지 알파 1 · 뒤는 0 으로, 발밑에서 lift 칸 위, 그리는 순서 (이름표 외곽선 10 아래)
const WINDUP := {"r0": 0.95, "r1": 1.25, "hold": 0.75, "lift": 0.05, "priority": 9}
# 스킬·필살기 고리: 처음 반지름 (칸) · 처음 알파 · 발밑에서 lift 칸 위 (커짐·시간은 body_fx.aura 그대로)
const AURA := {"r": 0.58, "alpha": 0.85, "lift": 0.04}

static var _meshes := {} # "종류|색" → ArrayMesh


static func paint(kind: String, tint: Color) -> Color:
	match kind:
		"clear":
			return Color(1, 1, 1, 0)
		"core":
			return Color(1, 1, 1, 1)
		"ink":
			return Color(G3C.OUTLINE_COLOR.r, G3C.OUTLINE_COLOR.g, G3C.OUTLINE_COLOR.b, INK_ALPHA)
	return Color(tint.r, tint.g, tint.b, 1.0)


# 쓴 사람 색 (0xRRGGBB) → 정점 색. 정점 색은 재질이 선형 값으로 읽어서 (vertex_color_is_srgb 를 켜면 셰이더 모양이 달라져 미리 그리기 표 밖) 여기서 바꿔 둠
static func tint_of(color: int) -> Color:
	return Co.color(color).srgb_to_linear()


# 띠 폭 ÷ 바깥 반지름 (화면에서 고리가 얼마나 굵은지)
static func band_frac(kind: String) -> float:
	var b: Array = LOOKS[kind].bands
	return (float(b.back()[1]) - float(b[0][0])) / float(b.back()[1])


# 예고 고리 반지름 (칸): u = 흐른 비율 0~1
static func windup_radius(u: float) -> float:
	var k := 1.0 - clampf(u, 0.0, 1.0)
	return lerpf(float(WINDUP.r0), float(WINDUP.r1), 1.0 - k * k)


# 예고 고리 알파: hold 까지 1, 그 뒤 곧게 0 으로
static func windup_alpha(u: float) -> float:
	var h := float(WINDUP.hold)
	if u <= h:
		return 1.0
	return clampf(1.0 - (u - h) / (1.0 - h), 0.0, 1.0)


# 바닥에 눕힌 고리 (고도 xz 평면, 반지름 1). 띠마다 사각형 둘레 — 띠 경계는 정점을 따로 둬 색이 번지지 않음
static func mesh(kind: String, color: int) -> ArrayMesh:
	var key := "%s|%d" % [kind, color]
	if _meshes.has(key):
		return _meshes[key]
	var L: Dictionary = LOOKS[kind]
	var tint := tint_of(color)
	var seg := int(L.seg)
	var v := PackedVector3Array()
	var vc := PackedColorArray()
	var nrm := PackedVector3Array()
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, -sin(a0))
		var d1 := Vector3(cos(a1), 0, -sin(a1))
		for b in L.bands:
			var ri := float(b[0])
			var ro := float(b[1])
			var ci := paint(str(b[2]), tint)
			var co := paint(str(b[3]), tint)
			v.append_array([d0 * ro, d0 * ri, d1 * ro, d1 * ro, d0 * ri, d1 * ri])
			vc.append_array([co, ci, co, co, ci, ci])
			for k in 6:
				nrm.append(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = vc
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[key] = m
	return m


# 고리 재질 (고리마다 하나 — 알파만 흐름): 빛 안 받음 · 반투명 · 정점 색 · 양면 · 깊이 안 씀, 깊이 검사는 켬 (블록 뒤면 가려짐).
# 효과 풀 고리 (fx/effects.gd ring_mat) 와 같은 셰이더 모양 = STD_KEYS [0, 1, 0, 2, 0, 0, 1, 0, 0, 0, 2] → 판 들어올 때 미리 그려 둠
static func material(alpha := 1.0, priority := 0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, alpha)
	m.render_priority = priority
	return m


static func clear_static() -> void: # 종료 때 정적 상태를 비움 (메시 리소스를 쥔 채 엔진이 내려가지 않게)
	_meshes = {}

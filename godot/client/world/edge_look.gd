# C7 (겉모습 2 — 바닥 읽힘): 낭떠러지 테. 필드 바깥 변 (바닥 판 윗면 + 변에 닿은 지형 칸 윗면) 에 밝은 띠 + 그 안쪽 어두운 선 —
# 어느 테마에서든 '여기까지가 설 수 있는 바닥' 이 선으로 읽히게. 그리는 곳 shaders/floor.gdshader (f_field·f_edge·f_edge_w) · shaders/terrain.gdshader (tf_field·tf_field_edge·tf_field_w).
# 넣는 곳 world/world.gd (테마 적용 직후·판 크기 바뀔 때). uniform 이 0 (기본) 이면 예전 화소 그대로.
# 순수 계산 + 재질에 값 넣기만. 테스트 tests/test_block_style.gd test_c7_edge_*
extends RefCounted

const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")

const EDGE := {
	"w": 0.14, # 밝은 띠 폭 (칸, 변에서 안쪽으로)
	"lift": 0.62, # 띠 색 = floor.a 를 흰 쪽으로 이만큼 (sRGB) — 채도가 빠져 위험 액체·플레이어 색과 안 헷갈림
	"inner_w": 0.1, # 띠 안쪽 어두운 선 폭 (칸)
	"inner_shade": 0.72, # 어두운 선 = 바닥 색 × 이 값 (sRGB 배율. 셰이더는 선형이라 shade_linear 로 넣음) — 밝은 바닥 (하늘성·사막) 은 이 선으로 구분됨
}
const GAMMA := 2.2 # sRGB 배율 → 선형 배율 (거듭제곱 근사)


# 띠 색 (sRGB)
static func edge_color(theme_id) -> Color:
	return _floor_a(theme_id).lerp(Color.WHITE, EDGE.lift)


# 안쪽 어두운 선의 색 (sRGB) — 체크무늬 a 칸 위에서. 셰이더가 그리는 값과 같게 선형에서 곱함
static func inner_color(theme_id) -> Color:
	var a := _floor_a(theme_id).srgb_to_linear()
	var k := shade_linear()
	return Color(a.r * k, a.g * k, a.b * k).linear_to_srgb()


static func _floor_a(theme_id) -> Color:
	var t = C.WORLD_THEMES.get(theme_id) if theme_id != null else null
	return Co.color(t.floor.a if t != null and t.has("floor") else C.TERRAIN_COLOR)


static func shade_linear() -> float:
	return pow(EDGE.inner_shade, GAMMA)


# 변까지 거리 d (칸) → [밝은 띠 세기, 어두운 선 세기] (0 또는 1). 셰이더와 같은 문턱: d < w 띠 · w ≤ d < w + inner_w 선
# (셰이더는 문턱마다 화면 한 화소만큼 부드럽게 섞음 — 문턱 자리는 같음)
static func band(d: float, w: float = EDGE.w, inner_w: float = EDGE.inner_w) -> Vector2:
	if d < w:
		return Vector2(1.0, 0.0)
	return Vector2(0.0, 1.0 if d < w + inner_w else 0.0)


# 필드 변까지 거리 (셰이더의 min 넷과 같은 식)
static func edge_dist(x: float, y: float, w: float, d: float) -> float:
	return minf(minf(x, w - x), minf(y, d - y))


# 셰이더에 넣는 폭 묶음 (띠 폭, 어두운 선 폭, 어두운 선 선형 배율)
static func widths() -> Vector3:
	return Vector3(EDGE.w, EDGE.inner_w, shade_linear())


static func _is(mat, file: String) -> bool:
	return mat is ShaderMaterial and mat.shader != null and mat.shader.resource_path.get_file() == file


# 바닥·지형 재질에 판 크기·띠 색·폭을 넣음 (다른 재질이면 건드리지 않음). w·d 가 0 이면 끔
static func apply(floor_mat, terrain_mat, theme_id, w: float, d: float) -> void:
	var c := edge_color(theme_id).srgb_to_linear()
	var col := Vector3(c.r, c.g, c.b)
	if _is(floor_mat, "floor.gdshader"):
		floor_mat.set_shader_parameter("f_field", Vector2(w, d))
		floor_mat.set_shader_parameter("f_edge", col)
		floor_mat.set_shader_parameter("f_edge_w", widths())
	if _is(terrain_mat, "terrain.gdshader"):
		terrain_mat.set_shader_parameter("tf_field", Vector2(w, d))
		terrain_mat.set_shader_parameter("tf_field_edge", col)
		terrain_mat.set_shader_parameter("tf_field_w", widths())

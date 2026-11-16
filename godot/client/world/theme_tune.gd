# C6 (겉모습 1 — 세계 바탕): 맵 테마의 고도 쪽 덮어쓰기. core/config.gd 는 JS 에서 만든 생성 파일이라 못 고침 →
# C.WORLD_THEMES[id] 를 깊게 베낀 것 위에 TUNE 을 깊게 합쳐 돌려줌 (theme, 결과는 기억해 둠). 쓰는 곳: G3.apply_theme (하늘·하늘빛·해·안개) · Scenery (섬 절벽)
# 덮을 수 있는 키는 ALLOWED 뿐 — floor·terrain·piece·hazard 는 JS 정답 테스트 (test_block_style 등) 가 C.WORLD_THEMES 로 묶고 있어 그대로 둠.
# C8 (겉모습 3 — 세계 색 마감): 구름 바다 (sea)·구름 (cloud)·먼 배경 (far) 도 덮을 수 있음 — 쓰는 곳 Scenery (바다 판·구름·먼 실루엣).
# 순수 계산만 (노드·three 없음). 테스트 tests/test_shaders.gd·test_w45.gd 의 test_c6_* · test_shaders.gd test_c8_*
extends RefCounted

const C := preload("res://core/config.gd")

const ALLOWED := ["sky", "hemi", "sunIntensity", "fog", "cliff", "sea", "far", "cloud"]

# 하늘을 밝혀 둔 어두운 (밤) 테마 — 아래 TUNE 첫 묶음. 그래픽 낮춤 하늘 배율 (sky_low_dim)·구름 바다 밝기 하한 (SEA_LUMA_MIN) 이 이 셋만 봄
const DARK := ["volcano", "crystal", "mushroom"]

# 어두운 세 테마 (화산·수정·버섯) 가 검정 덩어리로 꺼지지 않게 (갤러리 사진을 보며 맞춘 값): 하늘 네 색 ↑ (지평선 × ~1.6, 꼭대기·중간·아래 × ~2 — 밤 느낌은 남김),
# 하늘빛 세기 × 1.5~1.8 + 땅 쪽 색 ↑ (그늘 면이 하늘과 구분되게), 해 세기 + 0.35~0.55, 안개 색도 하늘 중간 색 쯤으로.
# 판 빛 (game_light vivid) 이 하늘·안개를 0.5배로 낮춘 뒤에도 지평선이 SKY_DIM_LUMA_MIN 위에 남아야 함 (test_c6_dark_sky_floor).
# 값은 통째 값 (사전은 키마다 합치고, 배열·숫자는 갈아 끼움). 색은 0xRRGGBB. 원래 값: core/config.gd WORLD_THEMES (예: 화산 지평선 0x8c2c16, 하늘빛 1.45, 해 1.0)
const TUNE := {
	"volcano": {
		"sky": {"top": 0x321012, "mid": 0x70221e, "horizon": 0xd4582c, "below": 0x5a1c12},
		"hemi": [0xffc4a8, 0x7a4444, 2.6],
		"sunIntensity": 1.55,
		"fog": [0x5a1a16, 40.0, 115.0],
		"sea": [0x7c3020, -16.0],
	},
	"crystal": {
		"sky": {"top": 0x201a50, "mid": 0x4a3a9c, "horizon": 0x9068d8, "below": 0x34266e},
		"hemi": [0xc0b0ff, 0x5c4a8c, 2.4],
		"sunIntensity": 1.45,
		"fog": [0x3a2c78, 40.0, 120.0],
		"sea": [0x6247a3, -16.0],
	},
	"mushroom": {
		"sky": {"top": 0x103c44, "mid": 0x1e7474, "horizon": 0x4cb496, "below": 0x144846},
		"hemi": [0xb0f4dc, 0x44684e, 2.3],
		"sunIntensity": 1.4,
		"fog": [0x165052, 40.0, 115.0],
		"sea": [0x245e56, -16.0],
	},
	# C8: 성 — 지평선 (원래 0xeaf2ea) 의 초록기를 뺌 (판 빛이 채도를 올리면 하늘 아래쪽이 초록 얼룩으로 떴음)
	"castle": {
		"sky": {"horizon": 0xeef0f4},
	},
	# C8: 사막 — 모래 주황은 지형·바닥에만. 하늘 지평선·안개·구름 바다·구름은 보조색 (옅은 하늘빛·연보라), 먼 메사는 적갈색 (지형보다 붉고 어둡게 떨어져 보이게).
	# 원래 값: 지평선 0xf8d8a0 · 안개 0xf2dcb0 · 바다 0xf0dcb8 · 구름 0xfff2e0 · 먼 배경 0xc08a5a (하늘·바다·섬이 전부 모래색 한 덩이였음)
	"desert": {
		"sky": {"horizon": 0xd8dce8},
		"fog": [0xd0d4e0, 45.0, 120.0],
		"sea": [0xc8cede, -16.0],
		"cloud": 16052458.0, # 0xf4f0ea
		"far": {"shapes": ["mesa", "mesa", "pyramid"], "color": 0x9a4630, "base": -18.0, "count": 12.0, "haze": [0.2, 0.45]},
	},
}

# C8 구름 바다 (TUNE.*.sea): 어두운 세 테마는 그 테마 하늘 below 와 horizon 의 중간 색에서 출발 — 화면 아래쪽이 검정이 아니라 테마 색 안개층으로.
# 바다 색은 꼭짓점 색으로 값 그대로 나감 (판 빛이 안 낮춤) → sRGB 밝기가 이 하한 위, 그 테마 위험 액체 (hazard.mid·shallow) 보다는 어둡게 (test_c8_dark_sea_floor)
const SEA_LUMA_MIN := 0.2

# 절벽 (섬 몸통 층 색) sRGB 밝기 하한: 가장 어두운 층이 이보다 낮으면 그 층을 하한에 놓고 나머지는 그 위로 (층 사이 밝기 차 × CLIFF_SPREAD → 층이 계속 구분됨, 빛깔은 그 색 그대로)
const CLIFF_LUMA_MIN := 0.22
const CLIFF_SPREAD := 2.0 # 밝힐 때 층 사이 밝기 차를 이 배로 (어두운 테마는 차가 작아 층이 묻혔음)
# 판 빛 vivid 로 낮춘 뒤 지평선 색의 선형 밝기 하한 (예전 화산·수정 0.037)
const SKY_DIM_LUMA_MIN := 0.06

# 그래픽 낮춤 (판 빛 꺼짐 → 하늘을 아무도 안 낮춤) 일 때 TUNE 으로 밝힌 하늘에 곱할 값 (선형). TUNE 하늘 값은 판 빛 vivid (× 0.5) 아래에서 맞춘 것
const SKY_LOW_DIM := 0.7

# 하늘 띠 (sky.gdshader band_k·band_glow): 지평선 쪽 부드러운 띠 2단. 그래픽 낮춤이면 0. band_glow 는 sky.glow 가 있는 (밤) 테마만
const SKY_BAND_K := 0.5
const SKY_BAND_GLOW := 0.25
# 띠 색 대비 기본 (sky.gdshader band_mix·band_lift 기본값과 같음): 윗단 색 = mix(지평선, 중간, MIX), 아랫단 밝히기 LIFT
const SKY_BAND_MIX := 0.4
const SKY_BAND_LIFT := 0.0
# 테마마다 띠 값 덮기 {k, mix, lift} (없는 키는 위 기본). TUNE 밖에 둠 — TUNE 은 테마 값 (ALLOWED 키) 만.
# 하늘 성 (c6 리뷰 F4): 지평선 (0xFFD17C)·중간 (0xD88C8C) 색이 이미 부드럽게 이어져 기본 띠 (그 둘 사이 색을 반만 섞음) 가 바탕 기울기에 묻혀 안 보였음 →
# 윗단을 지평선 색 그대로·세기 1 로 (밝은 금빛 구름 띠가 중간 색 하늘 위로 물결침), 아랫단은 0.3 밝게. 갤러리 map-spiral-eye·over 를 보며 맞춘 값 (0.9·0.1·0.15 는 아직 흐렸음)
const SKY_BAND_THEME := {
	"skycastle": {"k": 1.0, "mix": 0.0, "lift": 0.3},
}

# 섬 몸통 (scenery.gd island_shape): 고리 흔들림을 예전의 몇 배로 (반지름) · 높이 흔들림 ± · 방위마다 위 고리보다 반지름이 이 배 이하 · 높이는 depth 의 이만큼 더 아래 ·
# 끝 점은 마지막 고리 가장 좁은 반지름의 이 배 안쪽 · 면마다 밝기 흔들림
const ISLAND_JITTER := 0.6
const ISLAND_Z_JITTER := 0.05
const ISLAND_SHRINK := 0.99
const ISLAND_DROP := 0.02
const ISLAND_TIP_IN := 0.6
const ISLAND_FACE_SHADE := 0.015 # 면마다 밝기 흔들림 한 칸 (−2..+2 칸 → ±3%)

static var _cache := {}


# 테마 표 한 줄 (C.WORLD_THEMES[id] + TUNE[id] + 절벽 밝기 하한). 표에 없는 id 는 {}. 돌려준 사전은 고치지 말 것 (기억해 둔 것 그대로)
static func theme(id) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	if not C.WORLD_THEMES.has(id):
		return {}
	var t: Dictionary = C.WORLD_THEMES[id].duplicate(true)
	_merge(t, TUNE.get(id, {}))
	if t.has("cliff"):
		t.cliff = cliff_floor(t.cliff, CLIFF_LUMA_MIN)
	_cache[id] = t
	return t


# 깊게 합치기: 사전은 키마다, 나머지 (배열·숫자) 는 갈아 끼움
static func _merge(base: Dictionary, over: Dictionary) -> void:
	for k in over:
		if base.get(k) is Dictionary and over[k] is Dictionary:
			_merge(base[k], over[k])
		elif over[k] is Dictionary or over[k] is Array:
			base[k] = over[k].duplicate(true)
		else:
			base[k] = over[k]


# 0xRRGGBB 의 sRGB 밝기 (0~1, 값 그대로 — 선형으로 안 바꿈)
static func luma(c) -> float:
	var i := int(c)
	return (0.2126 * ((i >> 16) & 0xff) + 0.7152 * ((i >> 8) & 0xff) + 0.0722 * (i & 0xff)) / 255.0


# 선형 색 (Vector3) 의 밝기
static func lin_luma(v: Vector3) -> float:
	return 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z


# 절벽 층 색들: 가장 어두운 층이 lo 보다 낮으면 그 층 밝기를 lo 로, 다른 층은 lo + (차 × CLIFF_SPREAD) 로 올림 (색마다 제 빛깔로 곱함, 성분 ≤ 255). 안 낮으면 받은 배열 그대로
static func cliff_floor(bands: Array, lo: float) -> Array:
	var darkest := 1.0
	for c in bands:
		darkest = minf(darkest, luma(c))
	if darkest >= lo:
		return bands
	var out := []
	for c in bands:
		var i := int(c)
		var l := luma(c)
		var rgb := [(i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff]
		var v := 0
		for ch in rgb:
			# 올림: 반올림으로 하한 바로 아래로 떨어지지 않게. 검정 (l = 0) 은 회색으로
			var want := lo + (l - darkest) * CLIFF_SPREAD
			var x: float = ch * want / l if l > 0.0 else want * 255.0
			v = (v << 8) | clampi(ceili(x), 0, 255)
		out.append(float(v))
	return out


# 하늘 띠 uniform 값 (sky.gdshader): 세기·glow 섞기 + 색 대비 (테마마다 SKY_BAND_THEME, 없으면 기본). 낮춤이면 세기 0. id 가 표에 없으면 (예전 노을) 띠만
static func sky_band(id, low: bool) -> Dictionary:
	var o: Dictionary = SKY_BAND_THEME.get(id, {}) if id != null else {}
	var tone := {"band_mix": float(o.get("mix", SKY_BAND_MIX)), "band_lift": float(o.get("lift", SKY_BAND_LIFT))}
	if low:
		return {"band_k": 0.0, "band_glow": 0.0}.merged(tone)
	var sky: Dictionary = theme(id).get("sky", {})
	return {"band_k": float(o.get("k", SKY_BAND_K)), "band_glow": SKY_BAND_GLOW if sky.has("glow") else 0.0}.merged(tone)


# 그래픽 낮춤일 때 하늘 색 (top·mid·horizon·below) 에 곱할 값: TUNE 이 하늘을 밝힌 테마 (DARK) 만 SKY_LOW_DIM, 나머지·보통 화질은 1
# (C8: 성·사막도 TUNE 에 sky 가 생겼지만 밝힌 게 아니라 빛깔만 바꾼 것 — 낮추지 않음)
static func sky_low_dim(id, low: bool) -> float:
	return SKY_LOW_DIM if low and DARK.has(id) and TUNE.get(id, {}).has("sky") else 1.0

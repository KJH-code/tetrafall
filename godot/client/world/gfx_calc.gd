# 화질 계산 (W6 2026-11-02, 재혁 PC 랙 — 노트북 Core Ultra 7 내장 그래픽 + RTX 5070 하이브리드). 순수 계산 (테스트 tests/test_gfx.gd), 적용은 world/gfx.gd.
# 어댑터 이름 → 내장 그래픽인가, 'reg query' 출력 → 이 PC 의 다른 (외장) GPU, 설정 (자동·높음·보통·낮음) + 창 크기 → 실제 화질과 3D 해상도 배율·MSAA·거울 크기
extends RefCounted

const WC := preload("res://world/world_config.gd")
const PC := preload("res://ui/perf_calc.gd")

# 외장 그래픽 이름 (내장 쪽 이름 규칙보다 먼저): 인텔 Arc A·B 시리즈 카드 (A380·A770·B580·Arc Pro A60), AMD Radeon RX·Pro, NVIDIA 전부
const DISCRETE_RE := "(?i)(nvidia|geforce|quadro|rtx|gtx|radeon\\s*(\\(tm\\)\\s*)?(rx|pro)\\b|arc(\\(tm\\))?\\s*(pro\\s*)?[ab]\\d{2,3}\\b)"
# 내장 그래픽: 인텔 (UHD·Iris·HD Graphics·Core Ultra 의 'Arc(TM) Graphics'·'Arc 140V'), AMD APU (Radeon(TM) Graphics·Vega 8·780M), 퀄컴 Adreno
const INTEGRATED_RE := "(?i)(intel|radeon\\s*(\\(tm\\)\\s*)?(graphics|vega|\\d{3}m\\b)|vega\\s*\\d+\\s*graphics|adreno)"
# 소프트웨어·가상 (개발 확인용 llvmpipe, 원격·기본 드라이버) — 내장으로 치지 않음 (자동이 낮추지 않음, 다른 GPU 로도 안 셈)
const SOFTWARE_RE := "(?i)(llvmpipe|softpipe|swiftshader|software|basic render|basic display|virtual|parsec|vmware|remote\\s+display|\\bidd)"


static func _m(re: String, s: String) -> bool:
	return RegEx.create_from_string(re).search(s) != null


# 어댑터 이름 (RenderingServer.get_video_adapter_name, ANGLE 이면 'ANGLE (…)' 째) → 소프트웨어 렌더인가
static func is_software(adapter: String) -> bool:
	return _m(SOFTWARE_RE, PC.short_gpu(adapter))


# → 내장 그래픽인가 (vendor = get_video_adapter_vendor 도 같이 봄: 이름만 'Arc(TM) Graphics' 여도 제조사가 Intel)
static func is_integrated(adapter: String, vendor := "") -> bool:
	var n := PC.short_gpu(adapter)
	if n == "" or is_software(n):
		return false
	if _m(DISCRETE_RE, n):
		return false
	return _m(INTEGRATED_RE, n) or _m("(?i)intel", vendor)


# Windows 'reg query …\Class\{4d36e968-…} /s /v DriverDesc' 출력 → 이 PC 에 깔린 외장 GPU 이름들 (지금 쓰는 것과 다른, 소프트웨어·가상·내장 빼고)
static func discrete_in_reg(text: String) -> Array:
	var out := []
	var re := RegEx.create_from_string("(?im)^\\s*DriverDesc\\s+REG_SZ\\s+(.+?)\\s*$")
	for m in re.search_all(text):
		var n := m.get_string(1)
		if n == "" or is_software(n) or is_integrated(n) or not _m(DISCRETE_RE, n) or out.has(n):
			continue
		out.append(n)
	return out


# 자동 화질: 내장 그래픽 → 낮음, 창 픽셀 > GFX_BIG_PX → 보통, 아니면 높음
static func auto_level(adapter: String, vendor: String, size: Vector2i) -> String:
	if is_integrated(adapter, vendor):
		return "low"
	if size.x * size.y > WC.GFX_BIG_PX:
		return "medium"
	return "high"


# 설정 (View.settings.gfx, 없거나 모르는 값이면 자동) → 실제 화질
static func effective(choice, adapter: String, vendor: String, size: Vector2i) -> String:
	var c := str(choice)
	if c in ["high", "medium", "low"]:
		return c
	return auto_level(adapter, vendor, size)


# 예전 설정 파일 (gfx 없이 lowGfx 만) → 화질 선택: 그래픽 낮춤 켬이면 낮음, 아니면 자동
static func migrate(settings: Dictionary) -> String:
	var c := str(settings.get("gfx", ""))
	if c in WC.GFX_CHOICES:
		return c
	return "low" if bool(settings.get("lowGfx", false)) else "auto"


# 3D 해상도 배율: 창 픽셀이 화질 상한 (GFX_MAX_PX) 을 넘으면 sqrt(상한 / 픽셀), 하한 GFX_MIN_SCALE, 소수 둘째 자리 (창을 조금 늘일 때마다 흔들리지 않게)
static func scale_3d(level: String, size: Vector2i) -> float:
	var cap := int(WC.GFX_MAX_PX.get(level, 0))
	var px := maxi(1, size.x * size.y)
	if cap <= 0 or px <= cap:
		return 1.0
	var s := sqrt(float(cap) / px)
	return maxf(float(WC.GFX_MIN_SCALE.get(level, 1.0)), floorf(s * 100.0) / 100.0)


# 화질 → 적용할 값 {level, low (= 예전 lowGfx), msaa (Viewport.MSAA), scale (3D 배율), mirror (거울 크기 배율)}
static func plan(level: String, size: Vector2i, web := false) -> Dictionary:
	var s := scale_3d(level, size)
	return {"level": level, "low": level == "low", "msaa": WC.msaa_3d(level == "low", web, level), "scale": s, "mirror": WC.mirror_scale(s, level) if level != "low" else 0.0}


static func msaa_x(m: int) -> int:
	return [1, 2, 4, 8][clampi(m, 0, 3)]


# 화면 구석·F3 의 화질 글: "보통 (자동) · 3D 75% · MSAA 2×"
static func level_text(choice, p: Dictionary) -> String:
	var t := "%s%s" % [WC.GFX_LABEL.get(p.level, p.level), " (자동)" if str(choice) not in ["high", "medium", "low"] else ""]
	return "%s · 3D %d%% · MSAA %d×" % [t, roundi(float(p.scale) * 100.0), msaa_x(int(p.msaa))]


# 하이브리드 노트북 안내: 지금 내장 그래픽인데 이 PC 에 외장 GPU 가 있으면 (Windows). 아니면 ""
static func hybrid_hint(adapter: String, vendor: String, others: Array) -> String:
	if not is_integrated(adapter, vendor) or others.is_empty():
		return ""
	return "내장 그래픽으로 실행 중 (%s 있음) — Windows 설정 > 그래픽에서 tetrafall.exe 를 고성능으로" % str(others[0])


# 렌더러 글: "opengl3 · GL Compatibility" (드라이버·방식)
static func renderer_text(driver: String, method: String) -> String:
	var m := {"gl_compatibility": "GL Compatibility", "forward_plus": "Forward+", "mobile": "Mobile"}
	return "%s · %s" % [driver, m.get(method, method)]

# W29 웹 성능: 웹 주소 ?키=값 → 인자 변환 (core/opts.gd), 웹 기본 몸 (외부 모델 끔, ?ext=1 로 켬), 웹 기본 화질 (낮음 + 3D 0.75), 먼 몸 자세 간격
extends RefCounted

const Opts := preload("res://core/opts.gd")
const WC := preload("res://world/world_config.gd")
const GC := preload("res://world/gfx_calc.gd")
const Lod := preload("res://world/pose_lod.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func test_opts_override_and_web_flag() -> void:
	Opts.override = PackedStringArray(["--ext", "1", "--gfx", "high"])
	check(Opts.has("ext") and Opts.has("gfx") and not Opts.has("no-ext"), "Opts.has")
	Opts.override = null
	Opts.web_override = true
	check(Opts.web(), "web 강제 켬")
	Opts.web_override = false
	check(not Opts.web(), "web 강제 끔")
	Opts.web_override = null
	check(Opts.web() == OS.has_feature("web"), "web 기본 = 실행 환경")


func test_web_default_gfx_is_low() -> void:
	var sz := Vector2i(1280, 720)
	check(GC.effective("auto", "ANGLE (NVIDIA GeForce RTX 4070)", "NVIDIA", sz, true) == "low", "웹 자동 = 낮음 (GPU 가 좋아도)")
	check(GC.effective("auto", "ANGLE (NVIDIA GeForce RTX 4070)", "NVIDIA", sz, false) == "high", "PC 자동은 그대로")
	check(GC.effective("high", "x", "", sz, true) == "high" and GC.effective("medium", "x", "", sz, true) == "medium", "웹도 설정에서 올리면 그대로")
	var p := GC.plan("low", sz, true)
	check(p.low and p.scale == WC.WEB_LOW_SCALE and p.msaa == Viewport.MSAA_DISABLED, "웹 낮음: 3D 0.75·MSAA 끔: %s" % str(p))
	check(GC.plan("low", sz, false).scale == 1.0, "PC 낮음은 720p 에서 1")
	check(GC.plan("high", sz, true).scale == 1.0, "웹 높음은 1")


func test_web_pose_lod_sparser() -> void:
	var w: Dictionary = WC.POSE_LOD_WEB
	var d: Dictionary = WC.POSE_LOD
	check(w.far_hz < d.far_hz and w.far2_hz < d.far2_hz and w.off_hz < d.off_hz and w.near == d.near, "웹 먼 몸 자세 간격이 더 김")
	check(Lod.interval_ms(5.0, true, false, w) > Lod.interval_ms(5.0, true, false, d), "중간 거리 간격")
	check(Lod.interval_ms(1.0, true, false, w) == 0.0 and Lod.interval_ms(50.0, true, true, w) == 0.0, "가까운 몸·내 몸은 매 프레임")


func test_export_excludes_ext_for_web_only() -> void:
	var f := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	var txt := f.get_as_text() if f != null else ""
	var parts := txt.split("[preset.")
	var web := ""
	var other := ""
	for s in parts:
		if s.contains('platform="Web"'):
			web = s
		elif s.contains("exclude_filter"):
			other += s
	check(web.contains("assets/models/ext/*"), "웹 묶음은 외부 모델 폴더 제외")
	check(not other.contains("assets/models/ext/*"), "PC 묶음은 외부 모델 포함")

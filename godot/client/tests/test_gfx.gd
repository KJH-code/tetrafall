# W6 화질·성능 측정 (2026-11-02, 재혁 PC 랙): 내장 그래픽 알아보기·하이브리드 다른 GPU 찾기 (reg 출력)·자동 화질·3D 배율·MSAA·거울,
# 예전 설정 옮기기, 적용 노드 (world/gfx.gd). F3 쪽은 tests/test_perf.gd, 배포 묶음 start 스크립트는 godot/server/tools/package.test.mjs (node)
extends RefCounted

const WC := preload("res://world/world_config.gd")
const GC := preload("res://world/gfx_calc.gd")
const Gfx := preload("res://world/gfx.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func test_integrated_names() -> void:
	var yes := ["Intel(R) UHD Graphics 620", "Intel(R) Arc(TM) Graphics", "Intel(R) Arc(TM) 140V GPU (16GB)", "Intel(R) Iris(R) Xe Graphics", "Mesa Intel(R) Xe Graphics (TGL GT2)",
		"ANGLE (Intel, Intel(R) UHD Graphics 770 (0x00004680) Direct3D11 vs_5_0 ps_5_0, D3D11)", "AMD Radeon(TM) Graphics", "AMD Radeon 780M", "AMD Radeon(TM) Vega 8 Graphics", "Qualcomm(R) Adreno(TM) X1-85 GPU"]
	var no := ["NVIDIA GeForce RTX 5070 Laptop GPU", "Intel(R) Arc(TM) A770 Graphics", "Intel(R) Arc(TM) B580 Graphics", "Intel(R) Arc(TM) Pro A60", "AMD Radeon RX 7600M XT", "AMD Radeon Pro W7900",
		"ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 (0x00002504) Direct3D11 vs_5_0 ps_5_0, D3D11)", "llvmpipe (LLVM 15.0.7, 256 bits)", "Microsoft Basic Render Driver", "SwiftShader Device (Subzero)", ""]
	for n in yes:
		check(GC.is_integrated(n), "내장: %s" % n)
	for n in no:
		check(not GC.is_integrated(n), "내장 아님: %s" % n)
	check(GC.is_integrated("Arc Graphics", "Intel"), "이름이 애매해도 제조사 Intel 이면 내장")
	check(not GC.is_integrated("NVIDIA GeForce RTX 5070", "Intel"), "외장 이름이 먼저")
	check(GC.is_software("llvmpipe (LLVM 15.0.7, 256 bits)") and not GC.is_software("Intel(R) UHD Graphics 620"), "소프트웨어 렌더")


func test_other_gpus_from_reg() -> void:
	var out := "\r\nHKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}\\0000\r\n    DriverDesc    REG_SZ    Intel(R) Arc(TM) Graphics\r\n\r\n" + \
		"HKEY_LOCAL_MACHINE\\...\\0001\r\n    DriverDesc    REG_SZ    NVIDIA GeForce RTX 5070 Laptop GPU\r\n\r\n" + \
		"HKEY_LOCAL_MACHINE\\...\\0002\r\n    DriverDesc    REG_SZ    Microsoft Basic Display Adapter\r\n" + \
		"HKEY_LOCAL_MACHINE\\...\\0003\r\n    DriverDesc    REG_SZ    Parsec Virtual Display Adapter\r\n" + \
		"HKEY_LOCAL_MACHINE\\...\\0004\r\n    DriverDesc    REG_SZ    NVIDIA GeForce RTX 5070 Laptop GPU\r\n\r\n검색을 마쳤습니다: 5개 일치\r\n"
	check(GC.discrete_in_reg(out) == ["NVIDIA GeForce RTX 5070 Laptop GPU"], "외장만 한 번: %s" % str(GC.discrete_in_reg(out)))
	check(GC.discrete_in_reg("") == [] and GC.discrete_in_reg("오류: 지정된 레지스트리 키 또는 값을 찾을 수 없습니다.") == [], "못 읽으면 빈 목록")
	var h := GC.hybrid_hint("Intel(R) Arc(TM) Graphics", "Intel", ["NVIDIA GeForce RTX 5070 Laptop GPU"])
	check(h.contains("내장 GPU") and h.contains("tetrafall.exe") and h.contains("고성능") and h.contains("RTX 5070"), "안내 한 줄: %s" % h)
	check(GC.hybrid_hint("Intel(R) Arc(TM) Graphics", "Intel", []) == "", "다른 GPU 없으면 안내 없음")
	check(GC.hybrid_hint("NVIDIA GeForce RTX 5070 Laptop GPU", "NVIDIA Corporation", ["NVIDIA GeForce RTX 5070 Laptop GPU"]) == "", "외장으로 돌면 안내 없음")


# W32 하이브리드 GPU 경고: 이름만으로 내장 판정 (UHD·Iris 는 'Intel' 글자가 없어도), 경고 글, 시작 로그 줄, 설정 도움말
func test_gpu_warning() -> void:
	for n in ["Intel(R) UHD Graphics 620", "Intel(R) Iris(R) Xe Graphics", "UHD Graphics 770", "Iris Xe Graphics", "ANGLE (Intel, Intel(R) UHD Graphics 630 Direct3D11 vs_5_0 ps_5_0)", "Intel(R) Arc(TM) Graphics"]:
		check(GC.is_integrated(n), "내장: %s" % n)
	check(not GC.is_integrated("NVIDIA GeForce RTX 4060 Laptop GPU") and not GC.is_integrated("Intel(R) Arc(TM) A770 Graphics"), "외장은 내장 아님")
	var h := GC.hybrid_hint("Intel(R) UHD Graphics 620", "Intel", ["NVIDIA GeForce MX150"])
	check(h.contains("내장 GPU 로 도는 것 같음") and h.contains("MX150") and h.contains("설정 > 시스템 > 디스플레이 > 그래픽") and h.contains("고성능") and h.contains("tetrafall.exe"), "경고 한 줄: %s" % h)
	check(GC.hybrid_hint("NVIDIA GeForce RTX 4060 Laptop GPU", "NVIDIA", ["NVIDIA GeForce RTX 4060 Laptop GPU"]) == "", "외장으로 돌면 경고 없음")
	check(GC.hybrid_hint("Intel(R) UHD Graphics 620", "Intel", []) == "", "다른 GPU 를 못 찾으면 경고 없음 (내장뿐인 PC 에 소음 안 냄)")
	check(GC.gpu_kind("Intel(R) UHD Graphics 620", "Intel") == "내장" and GC.gpu_kind("NVIDIA GeForce RTX 4060 Laptop GPU") == "" and GC.gpu_kind("llvmpipe (LLVM 19.1.1, 256 bits)") == "소프트웨어 렌더" and GC.gpu_kind("") == "", "GPU 이름 뒤 말")
	var l := GC.startup_line("Intel(R) UHD Graphics 620", "Intel")
	check(l.begins_with("[GPU] ") and l.contains("UHD") and l.contains("내장") and not l.contains("경고"), "시작 로그 줄: %s" % l)
	check(GC.startup_line("Intel(R) UHD Graphics 620", "Intel", h).contains("경고: 내장 GPU 로 도는 것 같음"), "경고가 있으면 이어서")
	check(GC.GPU_HELP.contains("그래픽 설정") and GC.GPU_HELP.contains("tetrafall.exe") and GC.GPU_HELP.contains("고성능"), "설정 도움말 한 줄")
	# 설정 창: 도움말은 늘 보이고, 하이브리드 안내가 있으면 그 글 (주황)
	var st = load("res://ui/settings.gd").new()
	st._ready()
	var was_hint: String = Gfx.hint
	Gfx.hint = ""
	st._show_gpu_help()
	check(st.gfx_help.text == GC.GPU_HELP and st.gfx_help.visible, "도움말 한 줄이 늘 있음")
	st.gfx_help.size.x = 460.0 # 설정 창 안쪽 폭
	check(st.gfx_help.get_line_count() == 1, "도움말은 한 줄에 들어감 (%d줄) — 설정 창이 작은 화면에서도 안 넘치게" % st.gfx_help.get_line_count())
	Gfx.hint = h
	st._show_gpu_help()
	check(st.gfx_help.text == h, "안내가 있으면 그 글")
	Gfx.hint = was_hint
	st.free()


func test_auto_level() -> void:
	var hd := Vector2i(1920, 1080)
	check(GC.auto_level("Intel(R) Arc(TM) Graphics", "Intel", hd) == "low", "내장 → 낮음")
	check(GC.auto_level("NVIDIA GeForce RTX 5070 Laptop GPU", "NVIDIA Corporation", hd) == "high", "외장 1080p → 높음")
	check(GC.auto_level("NVIDIA GeForce RTX 5070 Laptop GPU", "", Vector2i(2560, 1440)) == "high", "1440p 까지 높음")
	# W15: 고성능 외장 (RTX·Radeon RX 네 자리) 은 GFX_BIG_PX_FAST (3200×2000) 까지 높음 — 재혁 노트북 2880×1800 은 높음, 4K 는 보통
	check(GC.auto_level("NVIDIA GeForce RTX 5070 Laptop GPU", "", Vector2i(2560, 1600)) == "high", "RTX 1600p 높음")
	check(GC.auto_level("NVIDIA GeForce RTX 5070 Laptop GPU", "NVIDIA Corporation", Vector2i(2880, 1800)) == "high", "RTX 2880×1800 (재혁 노트북) 높음")
	check(GC.auto_level("ANGLE (NVIDIA, NVIDIA GeForce RTX 5070 Laptop GPU (0x00002F58) Direct3D11 vs_5_0 ps_5_0, D3D11)", "", Vector2i(3024, 1964)) == "high", "ANGLE 이름도")
	check(GC.auto_level("NVIDIA GeForce RTX 5070 Laptop GPU", "", Vector2i(3840, 2160)) == "medium", "RTX 4K → 보통")
	check(GC.auto_level("AMD Radeon RX 7600", "ATI Technologies Inc.", Vector2i(2880, 1800)) == "high", "Radeon RX 네 자리 = 고성능")
	check(GC.auto_level("NVIDIA GeForce GTX 1650", "", Vector2i(2560, 1600)) == "medium", "GTX 는 예전 기준 (1440p 넘으면 보통)")
	check(GC.auto_level("Radeon RX 580 Series", "", Vector2i(2560, 1600)) == "medium", "옛 RX (세 자리) 는 예전 기준")
	check(GC.auto_level("NVIDIA Quadro P2000", "", Vector2i(2560, 1600)) == "medium", "Quadro 는 예전 기준")
	check(GC.is_fast("NVIDIA GeForce RTX 3050 Laptop GPU") and not GC.is_fast("Intel(R) Arc(TM) Graphics", "Intel") and not GC.is_fast("AMD Radeon(TM) Graphics") and not GC.is_fast("llvmpipe (LLVM 15.0.7, 256 bits)"), "고성능 이름 규칙")
	check(GC.auto_level("llvmpipe (LLVM 15.0.7, 256 bits)", "Mesa", Vector2i(1280, 720)) == "high", "소프트웨어 GL (개발 확인) 은 높음 그대로 — 화면 대조 스샷이 안 바뀜")
	check(GC.effective("high", "Intel(R) UHD Graphics", "Intel", hd) == "high" and GC.effective("low", "NVIDIA RTX", "", hd) == "low", "직접 고르면 그것")
	check(GC.effective("", "Intel(R) UHD Graphics", "Intel", hd) == "low" and GC.effective("bogus", "NVIDIA RTX", "", hd) == "high", "빈·모르는 값 = 자동")


func test_migrate_old_settings() -> void:
	check(GC.migrate({}) == "auto", "설정 없음 → 자동")
	check(GC.migrate({"lowGfx": true}) == "low", "예전 그래픽 낮춤 켬 → 낮음")
	check(GC.migrate({"lowGfx": true, "gfx": ""}) == "low", "빈 gfx (view.gd 기본) → 예전 값으로")
	check(GC.migrate({"lowGfx": true, "gfx": "medium"}) == "medium", "고른 화질이 먼저")
	check(GC.migrate({"lowGfx": false, "gfx": "auto"}) == "auto", "자동")


func test_scale_and_plan() -> void:
	var k4 := Vector2i(3840, 2160)
	check(GC.scale_3d("high", k4) == 1.0, "높음은 늘 1")
	check(GC.scale_3d("medium", Vector2i(2560, 1440)) == 1.0, "보통 1440p 까지 1")
	check(GC.scale_3d("medium", Vector2i(3440, 1440)) == 0.86, "보통 3440×1440 → 0.86: %s" % GC.scale_3d("medium", Vector2i(3440, 1440)))
	check(GC.scale_3d("medium", k4) == 0.75, "보통 4K → 하한 0.75 (0.67 이면 흐려 보임)")
	check(GC.scale_3d("low", Vector2i(1920, 1080)) == 1.0 and GC.scale_3d("low", Vector2i(1280, 720)) == 1.0, "낮음 1080p 까지 1")
	check(GC.scale_3d("low", Vector2i(2560, 1440)) == 0.75 and GC.scale_3d("low", k4) == 0.5, "낮음 1440p 0.75 · 4K 0.5")
	var hi := GC.plan("high", Vector2i(1920, 1080))
	check(hi.msaa == Viewport.MSAA_4X and hi.scale == 1.0 and not hi.low and hi.mirror == 0.5, "높음 = 예전 그대로 (4×, 1, 거울 반): %s" % str(hi))
	var md := GC.plan("medium", k4)
	check(md.msaa == Viewport.MSAA_2X and md.scale == 0.75 and not md.low and is_equal_approx(md.mirror, 0.35 * 0.75), "보통 4K: %s" % str(md))
	var lo := GC.plan("low", k4, true)
	check(lo.msaa == Viewport.MSAA_DISABLED and lo.low and lo.scale == 0.5 and lo.mirror == 0.0, "낮음 = 그래픽 낮춤 + 3D 반: %s" % str(lo))
	check(WC.msaa_3d(false, false, "high") == WC.MSAA_3D_PC and WC.msaa_3d(false, false, "medium") == Viewport.MSAA_2X and WC.msaa_3d(false, false, "low") == WC.MSAA_LOW, "MSAA 고르기 화질별")
	check(WC.msaa_3d(true, false, "high") == WC.MSAA_LOW, "lowGfx 면 화질과 상관없이 끔 (예전 그대로)")
	check(WC.mirror_scale(1.0, "high") == 0.5 and is_equal_approx(WC.mirror_scale(0.8, "medium"), 0.28), "거울 크기")
	check(GC.level_text("auto", md) == "보통 (자동) · 3D 75% · MSAA 2×" and GC.level_text("high", hi) == "높음 · 3D 100% · MSAA 4×", "화질 글: %s" % GC.level_text("auto", md))
	check(GC.renderer_text("opengl3", "gl_compatibility") == "opengl3 · GL Compatibility", "렌더러 글")


# 적용 노드: 화질 → WC.level·판 화면 3D 배율·MSAA·lowGfx (설정 파일은 안 씀 — apply(false))
func test_gfx_node_applies() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var keep_low = View.settings.get("lowGfx", false)
	var keep_gfx = View.settings.get("gfx", "")
	var keep = [root.msaa_3d, root.scaling_3d_scale, WC.level]
	var g = Gfx.new() # 러너는 트리 밖 (_ready 안 돎) → 창을 넘김
	for lv in ["low", "medium", "high"]:
		g.forced = lv
		g.apply(false, root)
		var want := GC.plan(lv, root.size, OS.has_feature("web"))
		check(WC.level == lv and Gfx.plan.get("level") == lv and root.msaa_3d == want.msaa and is_equal_approx(root.scaling_3d_scale, want.scale), "%s 적용: 수준 %s MSAA %d 배율 %s" % [lv, WC.level, root.msaa_3d, root.scaling_3d_scale])
		check(bool(View.settings.lowGfx) == (lv == "low"), "%s: lowGfx = 낮음일 때만" % lv)
	# 1인칭 팔 SubViewport: 화질 MSAA + 판과 같은 3D 배율 (World 대신 사전 — world.get("vm"))
	var vm = preload("res://chars/viewmodel.gd").new()
	vm._ready()
	g.world = {"vm": vm}
	g.forced = "medium"
	g.apply(false, root)
	check(vm.view.msaa_3d == Viewport.MSAA_2X, "팔: 보통 2×")
	Gfx.scale_now = 0.75
	g.sync_vm()
	check(is_equal_approx(vm.view.scaling_3d_scale, 0.75) and vm.view.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "팔: 판 3D 배율")
	g.world = null
	vm.free()
	g.forced = ""
	View.settings["gfx"] = "low"
	g.apply(false, root)
	check(Gfx.choice == "low" and WC.level == "low", "설정 gfx 를 읽음")
	g.free()
	View.settings["gfx"] = keep_gfx
	View.settings["lowGfx"] = keep_low
	root.msaa_3d = keep[0]
	root.scaling_3d_scale = keep[1]
	WC.level = keep[2]

# 화질 적용 (W6 2026-11-02, 재혁 PC 랙): 설정 '화질' (View.settings.gfx: 자동·높음·보통·낮음) + 창 크기 + GPU 어댑터 → (계산 world/gfx_calc.gd)
#   View.settings.lowGfx (예전 '그래픽 낮춤' = 낮음 — 그림자·블룸·거울·장식은 예전처럼 lowGfx 를 듣는 쪽이 끔), 판 3D 해상도 배율·MSAA, 1인칭 팔 MSAA·3D 배율, 거울 크기 (WC.level)
# World 가 _ready 맨 처음에 붙임 (그 뒤 world·타이틀이 lowGfx 를 읽음). 창 크기가 바뀌면 다시 (자동이면 높음 ↔ 보통, 배율)
# 하이브리드 노트북 안내: Windows 에서 내장 그래픽으로 돌면 'reg query' 로 이 PC 의 다른 GPU 를 찾음 (스레드 — 타이틀을 안 멈춤) → hint (F3·화면 구석이 읽음)
# W31 적응형 3D 해상도: 판 중 (playing) 에만 프레임 시간을 보고 배율을 천장(화질이 정한 배율)~바닥 사이에서 조절 (world/adapt_calc.gd). 대기실·메뉴·창 크기 바뀔 때는 천장 그대로.
#   설정 adaptRes (기본 켬), 웹·소프트웨어 렌더(llvmpipe 등)에서는 안 함. 확인용: --adapt (소프트웨어에서도 켬) · --adapt-off · --adapt-fake-gpu <ms> (배율 1 에서 GPU 가 이만큼 걸리는 척, 배율² 로 줄어듦)
# 확인용: --gfx auto|high|medium|low (설정에 안 남김) · --fake-gpu "<이름>" (어댑터 이름 흉내) · --fake-gpu-others "<이름>" (다른 GPU 흉내, reg 안 부름)
extends Node
const Opts := preload("res://core/opts.gd")
const Hitch := preload("res://core/hitch.gd")

const WC := preload("res://world/world_config.gd")
const GC := preload("res://world/gfx_calc.gd")
const AC := preload("res://world/adapt_calc.gd")
const REG_KEY := "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}" # 디스플레이 어댑터 장치 종류

# 읽기 (F3 ui/perf.gd·화면 구석): 지금 값
static var adapter := ""
static var vendor := ""
static var choice := "auto" # 설정 선택 (자동·높음·보통·낮음)
static var plan := {} # GC.plan: {level, low, msaa, scale, mirror}
static var others: Array = [] # 이 PC 의 다른 (외장) GPU 이름 (Windows reg, 내장 그래픽일 때만 찾음)
static var hint := "" # 하이브리드 안내 한 줄 (없으면 "")
static var scale_now := 1.0 # 지금 3D 배율 (적응형이면 조절 중인 값, 아니면 plan.scale)
static var adapting := false # 적응형이 지금 돌고 있나 (판 중)
static var adapt_info := "" # F3·설정에 보일 한 줄 ("자동 해상도 (천장 100%)"), 안 돌면 ""

var world = null # world.gd (1인칭 팔 vm 의 MSAA 를 같이)
var forced := "" # --gfx
var _thread: Thread = null
var ctl = null # AC.Ctl (판 중에만 일함)
var _adapt_since_us := 0 # W41 적응형 켠 (판이 playing 이 된) 시각
var _tail: Node = null
var _head_us := 0
var _script_ms := 0.0
var _last_us := 0
var _fake_gpu := 0.0
var _force_adapt := false
var _off_adapt := false


func _ready() -> void:
	name = "Gfx"
	var args := Opts.args()
	adapter = RenderingServer.get_video_adapter_name()
	vendor = RenderingServer.get_video_adapter_vendor()
	var fake := _arg(args, "--fake-gpu")
	if fake != "":
		adapter = fake
		vendor = ""
	forced = _arg(args, "--gfx")
	print(GC.startup_line(adapter, vendor)) # W32: 시작 로그에 GPU 이름 (Godot 로그 파일에도 남음)
	_force_adapt = args.has("--adapt")
	_off_adapt = args.has("--adapt-off")
	var fg := _arg(args, "--adapt-fake-gpu")
	_fake_gpu = float(fg) if fg != "" else 0.0
	process_priority = -2147483648 # 프레임 맨 앞 (스크립트 시간 재기 시작)
	apply(false)
	get_tree().root.size_changed.connect(func(): apply(true))
	View.changed.connect(func(k): if k == "gfx": apply(true))
	var fo := _arg(args, "--fake-gpu-others")
	if fo != "":
		_got_others(GC.discrete_in_reg("    DriverDesc    REG_SZ    %s" % fo))
	elif OS.get_name() == "Windows" and GC.is_integrated(adapter, vendor):
		_thread = Thread.new()
		_thread.start(_find_others)


static func _arg(args: PackedStringArray, key: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else ""


# 설정·창 크기로 화질을 정해 적용. emit: lowGfx 가 바뀌면 View.changed 로 알림 (시작할 땐 world 가 곧바로 읽으니 조용히). win: 창 (테스트는 트리 밖이라 넘김)
func apply(emit: bool, win: Window = null) -> void:
	choice = forced if forced != "" else GC.migrate(View.settings)
	var root := win if win != null else get_tree().root
	var size := root.size
	var lv := GC.effective(choice, adapter, vendor, size, Opts.web())
	var p := GC.plan(lv, size, Opts.web())
	WC.level = lv
	plan = p
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	scale_now = p.scale
	if ctl != null:
		ctl.set_ceiling(p.scale)
		if adapting:
			scale_now = ctl.scale
	root.scaling_3d_scale = scale_now
	root.msaa_3d = WC.msaa_3d(p.low, Opts.web(), lv)
	if bool(View.settings.get("lowGfx", false)) != p.low:
		if emit:
			View.set_setting("lowGfx", p.low) # 듣는 쪽 (world·g3·타이틀·효과) 이 예전 '그래픽 낮춤' 처럼 바꿈
		else:
			View.settings["lowGfx"] = p.low
	sync_vm()


# 1인칭 팔 SubViewport (chars/viewmodel.gd — 창 크기 그대로, 1인칭이면 매 프레임): MSAA (WC.msaa_3d 가 WC.level 을 봄) + 판과 같은 3D 배율. World 가 팔을 만든 뒤에도 부름
func sync_vm() -> void:
	var vm = world.get("vm") if world != null else null
	if vm == null:
		return
	if vm.has_method("set_msaa"):
		vm.set_msaa()
	var sv = vm.get("view")
	if sv is SubViewport:
		(sv as SubViewport).scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		(sv as SubViewport).scaling_3d_scale = scale_now


func _find_others() -> void:
	var out := []
	OS.execute("reg", ["query", REG_KEY, "/s", "/v", "DriverDesc"], out, true)
	var found := GC.discrete_in_reg("\n".join(out))
	call_deferred("_got_others", found)


func _got_others(found: Array) -> void:
	others = found
	hint = GC.hybrid_hint(adapter, vendor, others)
	if hint != "":
		push_warning(GC.startup_line(adapter, vendor, hint)) # W32: 로그에도 경고 (F3·화면 구석에도 뜸)
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


# ---- 적응형 3D 해상도 (W31) ----
func _wants_adapt() -> bool:
	if _off_adapt or plan.is_empty() or Opts.web() or not bool(View.settings.get("adaptRes", true)):
		return false
	if GC.is_software(adapter) and not _force_adapt:
		return false
	return Store.in_room() and Store.phase() == "playing" # 판 중에만 (대기실·메뉴·결과·카운트다운은 고정)


func _process(_dt: float) -> void:
	var want := _wants_adapt()
	if want != adapting:
		_adapt_switch(want)
	if not adapting:
		return
	_head_us = Time.get_ticks_usec()
	var now := _head_us
	var f := (now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	if f <= 0.0 or f > 500.0: # 처음·멈춤 (로딩) 은 안 셈
		return
	if (now - _adapt_since_us) / 1000.0 < float(WC.ADAPT.get("grace_ms", 0.0)):
		return # W41: 판 시작 직후 유예 — 몸 만들기·첫 사용 값 때문에 느린 프레임을 GPU 병목으로 안 봄
	var vp := get_viewport().get_viewport_rid()
	var rcpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	if _fake_gpu > 0.0: # 확인용: 가짜 부하 (배율² 에 비례)
		g = maxf(g, _fake_gpu * scale_now * scale_now)
		f = maxf(f, g)
	if ctl.push(f, _script_ms + rcpu, g):
		_apply_adapt()


func _adapt_switch(on: bool) -> void:
	adapting = on
	var vp := get_viewport().get_viewport_rid()
	if on:
		if ctl == null:
			var acfg: Dictionary = WC.ADAPT
			if Opts.args().has("--no-body-pressure"): # W45 확인용: 몸 압박 끔 (해상도·MSAA 까지만)
				acfg = WC.ADAPT.duplicate()
				acfg["press_max"] = 0
			ctl = AC.Ctl.new(float(plan.scale), AC.target_ms(DisplayServer.screen_get_refresh_rate()), acfg)
		ctl.set_ceiling(float(plan.scale))
		ctl.set_target(AC.target_ms(DisplayServer.screen_get_refresh_rate()))
		ctl.restart()
		_last_us = 0
		_adapt_since_us = Time.get_ticks_usec()
		if _tail == null:
			_tail = _Tail.new()
			_tail.gfx = self
			_tail.process_priority = 2147483647
			add_child(_tail)
		RenderingServer.viewport_set_measure_render_time(vp, true)
	else:
		if ctl != null:
			ctl.restart()
		WC.msaa_cut = false
		_press_off()
		RenderingServer.viewport_set_measure_render_time(vp, Hitch.on)
		adapt_info = ""
	_apply_adapt()


# W45: 판이 끝나면 몸 압박을 되돌림 (외곽선 거리 전역 값 포함)
func _press_off() -> void:
	if WC.body_press != 0:
		WC.body_press = 0
		var oc := WC.outline_far_cfg(0)
		load("res://shaders/g3.gd").set_outline_far(float(oc.taper_from), float(oc.gone), float(oc.min_k))


# 계산기 값(배율·MSAA 낮춤) → 창·1인칭 팔에 적용. 안 돌면 천장 그대로
func _apply_adapt() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var s: float = ctl.scale if adapting and ctl != null else float(plan.get("scale", 1.0))
	var cut: bool = adapting and ctl != null and ctl.cut
	var press: int = ctl.press if adapting and ctl != null else 0
	adapt_info = ("자동 해상도 (천장 %d%%)%s%s" % [roundi(float(plan.scale) * 100.0), " · MSAA 낮춤" if cut else "", (" · 몸 압박 %d" % press) if press > 0 else ""]) if adapting else ""
	var ch := absf(s - scale_now) > 0.0001 or cut != WC.msaa_cut
	var press_ch := press != WC.body_press
	scale_now = s
	WC.msaa_cut = cut
	WC.body_press = press
	if press_ch: # W45: 몸 외곽선 거리 (셰이더 전역 값) 를 압박 단계에 맞춤 — 3D 버퍼를 안 건드림
		var oc := WC.outline_far_cfg(press)
		load("res://shaders/g3.gd").set_outline_far(float(oc.taper_from), float(oc.gone), float(oc.min_k))
		Hitch.tag("몸 압박", "%d단계" % press)
	if not ch:
		return
	Hitch.tag("해상도 변경", "%d%%%s" % [roundi(s * 100.0), " MSAA 낮춤" if cut else ""]) # 3D 버퍼를 다시 만드는 순간 — 히치 로거가 원인으로 적음
	root.scaling_3d_scale = s
	root.msaa_3d = WC.msaa_3d(bool(plan.get("low", false)), Opts.web(), WC.level)
	sync_vm()


# 프레임 맨 끝 (스크립트 일 끝): 맨 앞 시각과의 차 = 스크립트 시간
class _Tail:
	extends Node
	var gfx = null

	func _process(_dt: float) -> void:
		if gfx != null and gfx.adapting:
			gfx._script_ms = (Time.get_ticks_usec() - gfx._head_us) / 1000.0

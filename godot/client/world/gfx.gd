# 화질 적용 (W6 2026-11-02, 재혁 PC 랙): 설정 '화질' (View.settings.gfx: 자동·높음·보통·낮음) + 창 크기 + GPU 어댑터 → (계산 world/gfx_calc.gd)
#   View.settings.lowGfx (예전 '그래픽 낮춤' = 낮음 — 그림자·블룸·거울·장식은 예전처럼 lowGfx 를 듣는 쪽이 끔), 판 3D 해상도 배율·MSAA, 1인칭 팔 MSAA·3D 배율, 거울 크기 (WC.level)
# World 가 _ready 맨 처음에 붙임 (그 뒤 world·타이틀이 lowGfx 를 읽음). 창 크기가 바뀌면 다시 (자동이면 높음 ↔ 보통, 배율)
# 하이브리드 노트북 안내: Windows 에서 내장 그래픽으로 돌면 'reg query' 로 이 PC 의 다른 GPU 를 찾음 (스레드 — 타이틀을 안 멈춤) → hint (F3·화면 구석이 읽음)
# 확인용: --gfx auto|high|medium|low (설정에 안 남김) · --fake-gpu "<이름>" (어댑터 이름 흉내) · --fake-gpu-others "<이름>" (다른 GPU 흉내, reg 안 부름)
extends Node
const Opts := preload("res://core/opts.gd")

const WC := preload("res://world/world_config.gd")
const GC := preload("res://world/gfx_calc.gd")
const REG_KEY := "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}" # 디스플레이 어댑터 장치 종류

# 읽기 (F3 ui/perf.gd·화면 구석): 지금 값
static var adapter := ""
static var vendor := ""
static var choice := "auto" # 설정 선택 (자동·높음·보통·낮음)
static var plan := {} # GC.plan: {level, low, msaa, scale, mirror}
static var others: Array = [] # 이 PC 의 다른 (외장) GPU 이름 (Windows reg, 내장 그래픽일 때만 찾음)
static var hint := "" # 하이브리드 안내 한 줄 (없으면 "")

var world = null # world.gd (1인칭 팔 vm 의 MSAA 를 같이)
var forced := "" # --gfx
var _thread: Thread = null


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
	root.scaling_3d_scale = p.scale
	root.msaa_3d = p.msaa
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
		(sv as SubViewport).scaling_3d_scale = float(plan.get("scale", 1.0))


func _find_others() -> void:
	var out := []
	OS.execute("reg", ["query", REG_KEY, "/s", "/v", "DriverDesc"], out, true)
	var found := GC.discrete_in_reg("\n".join(out))
	call_deferred("_got_others", found)


func _got_others(found: Array) -> void:
	others = found
	hint = GC.hybrid_hint(adapter, vendor, others)
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

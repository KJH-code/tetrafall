# 아이템 견본 (c10-u2): 서버·봇 없이 필드 아이템 모델 (world/items_view.gd·item_models.gd)·넉백 투사체·놓인 폭탄 (world/shots.gd) 을 정해진 판·카메라로 찍음 (모양을 바꾸기 전·뒤 비교용)
#   xvfb-run -a godot --path godot/client --resolution 1280x720 --rendering-driver opengl3 -s res://tools/item_sheet.gd -- --out <폴더> [--only row,far,fp,proj,born,gone,held,crate] [--low]
# 나오는 파일 (10장):
#   items-row-meadow-eye.png · items-row-volcano-eye.png  가장자리 칸 눈높이에서 3칸 앞에 7종 한 줄 (왼쪽부터 item_look.gd KINDS 순서) — 밝은 초원 / 어두운 화산 바닥
#   items-row-meadow-over.png  같은 줄을 비스듬히 위에서 필드 전체로
#   items-far-meadow-eye.png  8칸 앞에 7종 한 줄
#   items-fp-meadow.png  기본 1인칭 (눈높이 C.EYE_HEIGHT, 고개 0, 시야각 C.FOV_DEFAULT) 에서 2칸 앞에 5종 + 받침 고리.
#     고개 0 이면 바닥은 눈높이 ÷ tan(시야각 절반) = 1.89칸 앞부터 화면에 들어옴 → 2칸 앞 고리 (반지름 0.38칸, 앞 끝 1.62칸) 는 앞쪽이 화면 아래로 잘림 (아이템 모델은 화면 안). 고리 전체는 2.25칸부터
#   items-fp3-meadow.png  같은 기본 1인칭에서 3칸 앞에 7종 — 아이템과 받침 고리 전체가 화면 안
#   items-proj.png  날아가는 넉백 투사체 셋 + 놓인 폭탄 둘 (왼쪽은 깜빡임이 켜진 반 주기, 오른쪽은 꺼진 반 주기) + 가운데 견줄 바닥 아이템 폭탄 하나
#   items-born-meadow-fp.png · items-born-volcano-eye.png  나옴 신호 (c10-fix F3): 4칸 앞 세 칸에 아이템이 막 나온 순간 (나이 SIG_AGE.born ms 로 고정) — 짧은 빛 기둥 + 퍼지는 고리. 기본 1인칭 / 화산 눈높이
#   items-gone-meadow-fp.png  사라짐 신호: 같은 줄의 양옆 두 칸에서 아이템이 막 없어진 순간 (터지는 고리, 종류 주색을 섞은 노랑), 가운데 칸은 견줄 보통 아이템
#   --low 면 그래픽 낮춤 + 외곽선 끔 (웹 기본값) 으로 한 장만: items-row-low.png (외곽선·판 빛 없이 3칸 앞 한 줄)
# c11-u2 든 아이템·착지 상자 (--only held,crate 로 골라야 찍음 — 안 고르면 위 10장 그대로):
#   held-row-eye.png  3칸 앞에 선 세 사람 (탱크·바드·닌자) 이 폭탄·넉백 글러브·설치 블록을 듦 — 오른 어깨 옆 모델 (world/held_view.gd)
#   held-4dir.png  폭탄을 든 탱크 넷: 왼쪽부터 앞·오른쪽·뒤·왼쪽에서 본 모습
#   held-all-eye.png  5칸 앞에 캐릭터 8명이 한 줄로 (세 종류를 돌아가며 듦) — 몸이 넓은 캐릭터에서도 모델이 몸 밖에 보이는지
#   held-fp3.png  기본 1인칭에서 3칸 앞 사람이 폭탄을 듦 (이름표 아래)
#   held-all-back.png  같은 여덟 명을 뒤에서 (3인칭 카메라가 보는 쪽 — 오른 어깨 옆에 붙어 보이는지)
#   held-third-me.png  3인칭 (판 카메라 world/cam_rig.gd) 에서 내가 (건축가) 설치 블록을 듦 · held-third-tank.png  내가 탱크 (넓은 몸) 로 폭탄을 듦
#   crate-eye-meadow.png · crate-eye-volcano.png  착지한 설치 블록 두 칸 (world/crate_look.gd 나무 상자) — 왼쪽에 견줄 설치 블록 아이템, 오른쪽에 쌓인 테마 모양 칸
#   --low --only held 면 held-low.png (세 사람 줄을 그래픽 낮춤으로)
# 판 그리기 (world/world.tscn) 를 이벤트 견본 (tools/event_sheet.gd) 처럼 띄우고 가짜 판 상태를 넣음: 지형 단 둘 · 사람 하나 (크기 견줌) · 아이템·투사체·폭탄.
# 아이템이 도는 각도는 items_view.hold_spin 으로 고정 (출렁임은 실제 시각이라 높이만 조금 다를 수 있음). 놓인 폭탄 깜빡임은 그리기 바로 앞에 가짜 시각 BOMB_NOW 로 다시 맞춤.
# 끝나면 저장한 파일 목록 (출력 줄 머리는 '효과 사진' — 본문 글꼴 글자 검사가 스크립트 따옴표 글을 다 훑어서 글꼴에 있는 글자만 씀), 종료 코드 0 (못 만든 사진·스크립트 오류가 있으면 1, 그릴 수 없는 환경 (--headless) 이면 2)
extends SceneTree

const K := preload("res://tools/gallery_config.gd")
const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const LP := preload("res://world/lobby_preview.gd")
const Cells := preload("res://world/cells.gd")
const ExtMotion := preload("res://chars/ext_motion.gd")
const IL := preload("res://world/item_look.gd")

const SCENES := ["row", "far", "fp", "proj", "born", "gone"]
const EXTRA := ["held", "crate"] # --only 로 골라야 찍는 장면 묶음 (c11-u2). 장면 이름이 "held:row" 꼴이면 ":" 앞이 묶음
# [파일 이름, 테마 이름, 그 테마 맵 id, 장면, 시점]
const JOBS := [
	["items-row-meadow-eye.png", "meadow", "flat", "row", "eye"],
	["items-row-meadow-over.png", "meadow", "flat", "row", "over"],
	["items-far-meadow-eye.png", "meadow", "flat", "far", "eye"],
	["items-fp-meadow.png", "meadow", "flat", "fp", "fp"],
	["items-fp3-meadow.png", "meadow", "flat", "row", "fp"],
	["items-proj.png", "meadow", "flat", "proj", "eye"],
	["items-row-volcano-eye.png", "volcano", "bowl", "row", "eye"],
	["items-born-volcano-eye.png", "volcano", "bowl", "born", "eye"],
	["items-born-meadow-fp.png", "meadow", "flat", "born", "fp"],
	["items-gone-meadow-fp.png", "meadow", "flat", "gone", "fp"],
	["held-row-eye.png", "meadow", "flat", "held:row", "eye"],
	["held-4dir.png", "meadow", "flat", "held:4dir", "eye"],
	["held-all-eye.png", "meadow", "flat", "held:all", "eye"],
	["held-fp3.png", "meadow", "flat", "held:fp3", "fp"],
	["held-all-back.png", "meadow", "flat", "held:back", "eye"],
	["held-third-me.png", "meadow", "flat", "held:me", "me"],
	["held-third-tank.png", "meadow", "flat", "held:me-tank", "me"],
	["crate-eye-meadow.png", "meadow", "flat", "crate", "eye"],
	["crate-eye-volcano.png", "volcano", "bowl", "crate", "eye"],
]
const LOW_JOBS := [["items-row-low.png", "meadow", "flat", "row", "eye"], ["held-low.png", "meadow", "flat", "held:row", "eye"]]
const HOLD_FRAMES := 3 # 시점만 바뀐 장면에서 찍기 전 그릴 프레임
const EYE_LOOK_Z := 1.0 # 눈높이 시점이 보는 높이 (필드 가운데 위)
const SPIN := 0.6 # 아이템이 도는 각도 고정 (rad — 앞면이 비스듬히 보이게)
# 가짜 판 (필드 가운데 x·서는 변 y = 0 기준 칸): 지형 단 [dx0, dx1, y0, y1, 높이] · 사람 [dx, y] (먼 줄 뒤 왼쪽 바깥 — 아이템을 안 가림) · 아이템 줄 [앞 칸 수, 가운데에서 칸 오프셋들]
const STEPS := [[-7, -4, 11, 13, 1], [3, 6, 12, 14, 1]]
const MAN := [-4.5, 9.5]
const ROWS := {"row": [3, [-3, -2, -1, 0, 1, 2, 3]], "far": [8, [-3, -2, -1, 0, 1, 2, 3]], "fp": [2, [-2, -1, 0, 1, 2]], "born": [4, [-2, 0, 2]], "gone": [4, [-2, 0, 2]]}
const FP_KINDS := ["jump", "bomb", "knockback", "ghost", "counter"]
const SIG_KINDS := ["knockback", "jump", "speed"] # 나옴·사라짐 신호 장면의 세 칸
const SIG_AGE := {"born": 120.0, "gone": 100.0} # 신호 나이를 이 값 (ms) 으로 고정해 찍음 (items_view.hold_sig)
# 투사체·폭탄 장면: 투사체 [dx, 앞 거리, 높이] · 놓인 폭탄 [dx 칸, 앞 칸, 남은 ms] · 견줄 바닥 아이템 폭탄 [dx 칸, 앞 칸]
const PROJS := [[-1.6, 3.0, 1.0], [0.4, 4.0, 1.3], [2.2, 5.0, 0.9]]
const BOMBS := [[-1, 3, 1400.0], [1, 3, 200.0]]
const BOMB_ITEM := [0, 3]
const BOMB_NOW := 130.0 # 놓인 폭탄 깜빡임을 재는 가짜 시각 (ms): 남은 1400ms 폭탄은 켜진 반 주기, 200ms 폭탄은 꺼진 반 주기 (item_view_math.bomb_on)
# c11-u2 든 아이템 장면의 사람들 [캐릭터, dx, y, 보는 쪽 yaw, 든 것] (dx = 필드 가운데 x 에서 칸, 카메라는 −y 쪽 변에서 +y 를 봄 → yaw −90° 가 카메라를 봄). 첫 사람이 P1 (held:me 에서는 나)
const HELD_MEN := {
	"held:row": [["tank", -1.6, 3.5, -PI / 2.0, "bomb"], ["bard", 0.0, 3.5, -PI / 2.0, "knockback"], ["ninja", 1.6, 3.5, -PI / 2.0, "brick"]],
	"held:4dir": [["tank", -2.7, 4.0, -PI / 2.0, "bomb"], ["tank", -0.9, 4.0, 0.0, "bomb"], ["tank", 0.9, 4.0, PI / 2.0, "bomb"], ["tank", 2.7, 4.0, PI, "bomb"]],
	"held:all": [["tank", -5.6, 5.5, -PI / 2.0, "bomb"], ["ninja", -4.0, 5.5, -PI / 2.0, "knockback"], ["builder", -2.4, 5.5, -PI / 2.0, "brick"], ["hook", -0.8, 5.5, -PI / 2.0, "bomb"],
		["hunter", 0.8, 5.5, -PI / 2.0, "knockback"], ["cannon", 2.4, 5.5, -PI / 2.0, "brick"], ["berserker", 4.0, 5.5, -PI / 2.0, "bomb"], ["bard", 5.6, 5.5, -PI / 2.0, "knockback"]],
	"held:fp3": [["hunter", 0.0, 3.5, -PI / 2.0, "bomb"]],
	"held:back": [["tank", -5.6, 5.5, PI / 2.0, "bomb"], ["ninja", -4.0, 5.5, PI / 2.0, "knockback"], ["builder", -2.4, 5.5, PI / 2.0, "brick"], ["hook", -0.8, 5.5, PI / 2.0, "bomb"],
		["hunter", 0.8, 5.5, PI / 2.0, "knockback"], ["cannon", 2.4, 5.5, PI / 2.0, "brick"], ["berserker", 4.0, 5.5, PI / 2.0, "bomb"], ["bard", 5.6, 5.5, PI / 2.0, "knockback"]],
	"held:me": [["builder", 0.0, 6.5, PI / 2.0, "brick"], ["ninja", 1.5, 9.5, -PI / 2.0, "bomb"]],
	"held:me-tank": [["tank", 0.0, 6.5, PI / 2.0, "bomb"], ["ninja", 1.5, 9.5, -PI / 2.0, "brick"]],
}
const ME_SCENES := ["held:me", "held:me-tank"] # P1 이 나인 장면 (판 카메라 3인칭)
const ME_PITCH := -0.1 # held:me 의 고개 (3인칭 카메라)
# 착지 상자 장면 (가운데 x 기준 칸 [dx, y, z]): 상자 칸 (값 Cells.THROWN) · 옆에 쌓인 테마 모양 칸 [dx, y, z, 모양 번호] · 견줄 설치 블록 아이템 [dx, y]
const CRATE_CELLS := [[-1, 3, 0], [0, 3, 0]]
const CRATE_SHAPES := [[1, 3, 0, 2], [2, 3, 0, 2], [2, 3, 1, 2], [1, 4, 0, 5], [1, 4, 1, 5]]
const CRATE_ITEM := [-3, 3]


# 도는 동안 난 엔진·스크립트 오류 (tools/gallery.gd 와 같음)
class ErrorLog extends Logger:
	var lines: Array = []
	var lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		lock.lock()
		lines.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function])
		lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var out_dir := ""
var only: Array = SCENES
var low := false
var jobs: Array = []
var job_i := -1
var wait := 0
var saved: Array = []
var failed: Array = []
var counts: Array = [] # 장마다 그린 인스턴스 수 (출력 줄)
var done := false
var errors := ErrorLog.new()
var store: Node
var view: Node
var world: Node3D
var cam := Camera3D.new()
var grid_ver := 4000
var last_floor := ""
var input: Node
var t0 := 0
var clock_steps := 0 # 몸 동작 가상 시계 걸음 (그린 프레임 수)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_dir = a[i + 1]
		elif a[i] == "--only" and i + 1 < a.size():
			only = Array(a[i + 1].split(",", false))
		elif a[i] == "--low":
			low = true
	if DisplayServer.get_name() == "headless":
		print("효과 사진: 화면을 그릴 수 없는 환경 (--headless) 입니다 — xvfb-run -a godot --rendering-driver opengl3 … 로 돌리세요")
		_end(2)
		return
	for k in only:
		if not SCENES.has(k) and not EXTRA.has(k):
			print("효과 사진: --only 는 %s 중에서 (받은 것 '%s')" % [",".join(SCENES + EXTRA), k])
			_end(1)
			return
	if out_dir == "" or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		print("효과 사진: --out <폴더> 가 필요합니다 (만들 수 없는 폴더 '%s')" % out_dir)
		_end(1)
		return
	OS.add_logger(errors)
	t0 = Time.get_ticks_msec()
	ExtMotion.clock = func(): return K.clock_s(clock_steps) # 사람 몸 (외부 모델 천·클립) 은 벽시계 대신 이 시계 — 프레임마다 한 걸음 (tools/gallery.gd 와 같음)


# 첫 프레임에 (자동 로드 View 의 _ready 가 user://settings.json 을 읽은 뒤): 설정 고정 → 판·카메라
func _setup() -> void:
	store = root.get_node("Store")
	view = root.get_node("View")
	input = root.get_node("PlayerInput")
	for k in K.SETTINGS:
		view.settings[k] = K.SETTINGS[k]
	view.settings["third"] = true # 사람 몸이 보이게 (여기선 내가 없지만 같은 설정으로)
	view.settings["lowGfx"] = low
	view.settings["gfx"] = K.gfx_choice(low)
	view.settings["outline"] = not low # --low 는 가장 약한 모습으로: 그래픽 낮춤 + 외곽선 끔 (웹 기본값이 외곽선 끔 — core/view.gd)
	world = load("res://world/world.tscn").instantiate()
	root.add_child(world)
	world.items_view.hold_spin = SPIN
	world.bodies.held_view.hold_spin = SPIN
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	cam.near = WC.CAM_CLIP[0]
	cam.far = WC.CAM_CLIP[1]
	root.add_child(cam)
	cam.make_current()
	for job in (LOW_JOBS if low else JOBS):
		if only.has(group(str(job[3]))):
			jobs.append(job)


# 장면 이름의 묶음 ("held:row" → "held", 그 밖은 이름 그대로)
static func group(scene: String) -> String:
	return scene.get_slice(":", 0)


# 그리기 바로 앞 (판 노드들이 이번 프레임 처리를 끝낸 뒤): 놓인 폭탄 깜빡임을 가짜 시각으로 다시 맞춤 (shots.gd 는 실제 시각으로 깜빡여서 찍을 때마다 달라짐)
func _pre_draw() -> void:
	if done or world == null or job_i < 0 or job_i >= jobs.size() or str(jobs[job_i][3]) != "proj":
		return
	world.shots._bombs(store.state.get("bombs", []), BOMB_NOW)


func _end(code: int) -> void:
	done = true
	ExtMotion.clock = Callable() # 끝나면 가상 시계를 뺌
	quit(code)


func _process(_dt: float) -> bool:
	if done:
		return true
	if world == null:
		_setup()
	clock_steps += 1
	if job_i >= 0:
		wait -= 1
		if wait > 0:
			return false
		_save(str(jobs[job_i][0]))
	job_i += 1
	if job_i >= jobs.size():
		_report()
		return true
	var job: Array = jobs[job_i]
	cam.make_current() # 판 카메라 (cam_rig) 는 자기 _ready 에서 current 가 됨 → 장면마다 다시 가져옴
	wait = K.WARM_FRAMES
	var floor_key := "%s|%s" % [job[1], "crate" if group(str(job[3])) == "crate" else ""] # 착지 상자 장면은 격자가 달라 판을 다시 깖
	if floor_key != last_floor:
		_stage(str(job[2]), group(str(job[3])) == "crate")
		wait = K.FIRST_WARM_FRAMES * 3 # 사람 몸 (외부 모델) 이 올라올 때까지 넉넉히
		last_floor = floor_key
	elif group(str(job[3])) == "held":
		wait = K.FIRST_WARM_FRAMES * 3 # 사람이 바뀜 (새 몸이 올라올 때까지)
	elif job_i > 0 and str(jobs[job_i - 1][3]) == str(job[3]):
		wait = HOLD_FRAMES
	_aim(str(job[4]))
	_fill(str(job[3]))
	return false


func _save(file: String) -> void:
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(file)
	if img == null or img.is_empty() or img.save_png(path) != OK:
		failed.append(file)
		return
	saved.append("%s (%d×%d)" % [path, img.get_width(), img.get_height()])
	var iv = world.items_view
	var n := []
	for kind in iv.models:
		var node: MultiMeshInstance3D = iv.models[kind]
		if node.visible:
			n.append("%s %d" % [kind, node.multimesh.visible_instance_count])
	var hv = world.bodies.held_view
	for kind in hv.models:
		var node: MultiMeshInstance3D = hv.models[kind]
		if node.visible:
			n.append("held-%s %d" % [kind, node.multimesh.visible_instance_count])
	if world.grid_view.crate_mmi.visible:
		n.append("crate %d" % world.grid_view.crate_cells.size())
	counts.append("%s 그림 %s · draws %d · prims %d" % [file, ", ".join(n) if not n.is_empty() else "없음",
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _report() -> void:
	for s in saved:
		print("효과 사진 저장 %s" % s)
	for s in counts:
		print("효과 사진 %s" % s)
	for f in failed:
		print("효과 사진 실패 %s" % f)
	for e in errors.lines:
		print("효과 사진 오류 %s" % e)
	var ok := failed.is_empty() and errors.lines.is_empty() and saved.size() == jobs.size()
	print("효과 사진: %d장 저장, 실패 %d, 오류 %d줄, %.1f초%s" % [saved.size(), failed.size(), errors.lines.size(), (Time.get_ticks_msec() - t0) / 1000.0, " (그래픽 낮춤)" if low else ""])
	_end(0 if ok else 1)


# ---------- 가짜 판 ----------
static func field_n() -> int:
	return LP.field_size_for(K.PLAYERS)


# 필드 가운데 칸 x (서는 자리는 −y 쪽 변 가운데 칸 = (mid_x, 0))
static func mid_x() -> int:
	return field_n() / 2


# 사람 한 명 (스냅샷 players 한 줄)
static func _man(id: int, ch: String, x: float, y: float, yaw: float, held) -> Dictionary:
	return {"id": id, "slot": id - 1, "away": false, "color": id - 1, "name": "P%d" % id, "nick": "", "spectator": false, "team": null, "isBot": true,
		"x": x, "y": y, "z": 0.0, "yaw": yaw, "pitch": 0.0, "alive": true, "stunned": false, "hasControl": false,
		"dummy": false, "emote": -1, "emoteLeft": 0, "held": held, "damage": 0.0, "wins": 0, "controlling": false, "cause": null, "master": false, "zombie": false,
		"char": ch, "skillCd": 0, "ult": 0, "ultMax": 100, "iframeLeft": 0, "combo": 0, "marks": [], "respawnIn": null}


# 장면의 사람들을 판 상태에 넣음: 든 아이템 장면 (HELD_MEN) 이면 그 사람들 (held:me 는 P1 이 나), 그 밖은 견줄 사람 하나 (먼 줄 뒤 왼쪽)
func _people(st: Dictionary, scene: String) -> void:
	var mx := mid_x()
	var men := []
	if HELD_MEN.has(scene):
		var list: Array = HELD_MEN[scene]
		for k in list.size():
			var m: Array = list[k]
			men.append(_man(k + 1, str(m[0]), mx + 0.5 + float(m[1]), float(m[2]), float(m[3]), m[4]))
	else:
		men.append(_man(1, "ninja", mx + 0.5 + float(MAN[0]), float(MAN[1]), -PI / 2.0, null))
	st["players"] = men
	var by := {}
	for m in men:
		by[int(m.id)] = m
	store._players_by_id = by
	store.my_id = 1 if ME_SCENES.has(scene) else null
	if ME_SCENES.has(scene):
		input.set_yaw_pitch(float(men[0].yaw), ME_PITCH)


# 판 중 (playing) 스냅샷 모양으로: 지형 단 둘 (사람·아이템·투사체·폭탄은 _fill 이 넣음). crate 면 착지 상자 칸·쌓인 모양 칸도 깖
func _stage(map_id: String, crate := false) -> void:
	var n := field_n()
	var h := int(C.GRID_H)
	var mx := mid_x()
	var grid := PackedByteArray()
	grid.resize(n * n * h)
	for s in STEPS:
		for x in range(mx + int(s[0]), mx + int(s[1]) + 1):
			for y in range(int(s[2]), int(s[3]) + 1):
				for z in int(s[4]):
					grid[(z * n + y) * n + x] = Cells.TERRAIN
	if crate:
		for c in CRATE_CELLS:
			grid[(int(c[2]) * n + int(c[1])) * n + mx + int(c[0])] = Cells.THROWN
		for c in CRATE_SHAPES:
			grid[(int(c[2]) * n + int(c[1])) * n + mx + int(c[0])] = Cells.SHAPE_BASE + int(c[3])
	grid_ver += 1
	store.my_id = null
	store.grid = grid
	store.grid_version = grid_ver
	store.state = {
		"phase": "playing", "mode": "survival", "time": 0.0, "gridVersion": grid_ver,
		"field": {"w": n, "d": n, "h": h}, "map": {"id": map_id, "choice": map_id},
		"players": [], "pieces": [], "items": [], "projectiles": [], "bombs": [], "events": [],
		"lava": {"active": false, "z": C.LAVA_START_Z}, "round": {"n": 1, "winnerId": null},
	}
	store._players_by_id = {}
	# 판 빛의 하늘 어둡게는 프레임 dt 로 서서히 켜짐 — 여기서 끝까지 돌려 둠 (tools/event_sheet.gd 와 같음)
	var lf = world.light_fx
	if lf != null and lf.has_method("frame"):
		for i in ceili(1.0 / (C.GAME_LIGHT_SKY_SPEED * 0.1)) + 1:
			lf.frame(true, [], 0.1)


# 장면의 아이템·투사체·폭탄을 판 상태에 넣음 (높이는 그 칸 기둥 꼭대기)
func _fill(scene: String) -> void:
	var st: Dictionary = store.state.duplicate() # 새 스냅샷처럼 (판 빛 무리는 스냅샷이 바뀔 때만 다시 만듦 — world._halo_st)
	store.state = st
	var mx := mid_x()
	var items := []
	var projs := []
	var bombs := []
	if scene == "proj":
		for p in PROJS:
			projs.append({"x": mx + 0.5 + float(p[0]), "y": 0.5 + float(p[1]), "z": float(p[2])})
		for b in BOMBS:
			var bx := mx + int(b[0])
			bombs.append({"x": bx, "y": int(b[1]), "z": world.column_top(bx, int(b[1])), "left": float(b[2])})
		var ix := mx + int(BOMB_ITEM[0])
		items.append({"type": "bomb", "x": ix, "y": int(BOMB_ITEM[1]), "z": world.column_top(ix, int(BOMB_ITEM[1]))})
	elif scene == "crate":
		var cx := mx + int(CRATE_ITEM[0])
		items.append({"type": "brick", "x": cx, "y": int(CRATE_ITEM[1]), "z": world.column_top(cx, int(CRATE_ITEM[1]))})
	elif group(scene) != "held":
		var row: Array = ROWS[scene]
		var kinds: Array = FP_KINDS if scene == "fp" else (SIG_KINDS if SIG_AGE.has(scene) else IL.KINDS)
		for k in row[1].size():
			var x := mx + int(row[1][k])
			items.append({"type": kinds[k], "x": x, "y": int(row[0]), "z": world.column_top(x, int(row[0]))})
	# 나옴·사라짐 신호 (c10-fix F3): 스냅샷 견주기 대신 신호를 직접 넣고 나이를 고정 (다른 장면에서는 비움)
	var iv = world.items_view
	iv.sigs.clear()
	iv.hold_sig = SIG_AGE.get(scene)
	iv._seen_st = st
	if scene == "born":
		for it in items:
			iv.add_signal("born", [it.x, it.y, it.z, it.type], 0.0)
	elif scene == "gone":
		for k in [2, 0]: # 양옆 두 칸은 막 없어짐, 가운데는 그대로
			var it: Dictionary = items[k]
			iv.add_signal("gone", [it.x, it.y, it.z, it.type], 0.0)
			items.remove_at(k)
	st["items"] = items
	st["projectiles"] = projs
	st["bombs"] = bombs
	_people(st, scene)


# 카메라: eye = −y 쪽 변 가운데 칸에 선 눈높이에서 필드 가운데를 봄 · fp = 같은 자리 기본 1인칭 (고개 0 — 수평으로 +y 쪽) · over = 갤러리 맵 사진처럼 비스듬히 위에서 필드 전체
# me = 판 카메라 (world/cam_rig.gd) 의 3인칭 그대로 (P1 이 나 — _people 이 내 번호·보는 쪽을 넣음)
func _aim(v: String) -> void:
	world.rig.force = "third" if v == "me" else ""
	if v == "me":
		world.rig.cam.make_current()
		return
	var n := float(field_n())
	var eye := Co.gxyz(mid_x() + 0.5, 0.5, C.EYE_HEIGHT)
	if v == "eye":
		cam.fov = C.FOV_DEFAULT
		cam.look_at_from_position(eye, Co.gxyz(mid_x() + 0.5, n / 2.0, EYE_LOOK_Z), Vector3.UP)
		return
	if v == "fp":
		cam.fov = C.FOV_DEFAULT
		cam.look_at_from_position(eye, Co.gxyz(mid_x() + 0.5, n / 2.0, C.EYE_HEIGHT), Vector3.UP)
		return
	var V: Dictionary = K.MAP_OVER
	var fwd := Co.dir(deg_to_rad(float(V.yaw)), -deg_to_rad(float(V.pitch)))
	var basis := Basis.looking_at(fwd, Vector3.UP)
	var tv := tan(deg_to_rad(float(V.fov)) / 2.0) * float(V.margin)
	var th := tv * float(root.size.x) / maxf(1.0, float(root.size.y))
	var at := Co.gxyz(n / 2.0, n / 2.0, 0.0)
	var dist := 1.0
	while dist < 4000.0: # 필드 네 모서리가 화면 안에 드는 거리까지 물러남
		var inv := Transform3D(basis, at - fwd * dist).affine_inverse()
		var inside := true
		for p in [Co.gxyz(0, 0, 0), Co.gxyz(n, 0, 0), Co.gxyz(0, n, 0), Co.gxyz(n, n, 0)]:
			var q: Vector3 = inv * p
			if -q.z <= 0.01 or absf(q.x) > -q.z * th or absf(q.y) > -q.z * tv:
				inside = false
		if inside:
			break
		dist += 0.25
	cam.fov = float(V.fov)
	cam.global_transform = Transform3D(basis, at - fwd * dist)

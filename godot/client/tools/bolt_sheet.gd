# 번개 견본 (c9): 서버·봇 없이 돌발 이벤트 '번개' 의 예고 고리·번개 띠를 정해진 자리·시각·카메라로 찍음 (tools/fx_sheet.gd 와 같은 틀 — 찍을 때마다 같은 사진)
#   xvfb-run -a godot --path godot/client --resolution 1280x720 --rendering-driver opengl3 -s res://tools/bolt_sheet.gd -- --out <폴더>
# 나오는 파일 (8장):
#   bolt-warn-<meadow|volcano>-<eye|over>.png — 예고 고리 둘 (가운데 = 거의 다 참, 오른쪽 = 막 뜸) + 견줄 고리 둘:
#     왼쪽 = F 준비 예고 고리 (world/ring_look.gd windup, 1번 사람 색 — 이어진 고리), 가운데 예고 안 = 발밑 스킬 고리 (aura, 3번 사람 색 — 예고가 덮지 않는지)
#     eye = 눈높이 가까이, over = 비스듬히 위에서
#   bolt-strike-meadow-eye.png — 가운데 예고에 번개가 떨어진 직후 (띠 3단 + 바닥 고리). '번개 사진 줄기 화면 높이 비 0.xx' 한 줄 (줄기 = 번개 띠 — 본문 글꼴에 있는 글자로): 그려진 띠 토막들의 화면 세로 길이 ÷ 화면 높이 (상한 bolt_fx_math STRIKE.cap)
#   bolt-warn-low.png — 그래픽 낮춤 (초원, 눈높이)
#   bolt-warn-meadow-fp.png · bolt-strike-meadow-fp.png — 1인칭 (c9 리뷰 F2): 내가 가운데 예고 한가운데에 서서 정면을 봄 (눈높이 EYE_HEIGHT, 고개 각 0 — 기본 시점).
#     발밑 고리는 화면 아래 끝보다 더 아래라 안 보임 → 화면 신호 (ui/bolt_alert.gd: 가운데 아래 판 '번개! 고리 밖으로' + 남은 초·막대, 가장자리 연노랑 테) 가 보여야 함.
#     strike = 내 자리에 떨어진 직후: 번개 띠는 화면 상한으로 안 그려지고 (줄기 비를 안 잼) 가장자리 테만 진하게, 판은 꺼짐
# 판 그리기 (world/world.tscn) 에 가짜 판 상태를 넣고 world.bolt_fx (+ 화면 신호 ui/bolt_alert.gd) 에 가짜 서버 이벤트 (boltWarn·bolt) 를 넣음. 엔진 시간 배율 0, 번개 시계 (bolt_fx.clock) 는 이 도구가 정함.
# 끝나면 저장한 파일 목록, 종료 코드 0 (못 만든 사진·스크립트 오류가 있으면 1, 그릴 수 없는 환경 (--headless) 이면 2)
extends SceneTree

const K := preload("res://tools/gallery_config.gd")
const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const LP := preload("res://world/lobby_preview.gd")
const RL := preload("res://world/ring_look.gd")
const M := preload("res://world/bolt_fx_math.gd")

const FLOORS := {"meadow": "flat", "volcano": "bowl"} # 테마 이름 (파일 이름에) → 그 테마 맵 id
# [파일, 바닥, 종류 (warn | strike), 시점 (eye | over), 그래픽 낮춤]
const JOBS := [
	["bolt-warn-meadow-eye.png", "meadow", "warn", "eye", false], ["bolt-warn-meadow-over.png", "meadow", "warn", "over", false],
	["bolt-warn-volcano-eye.png", "volcano", "warn", "eye", false], ["bolt-warn-volcano-over.png", "volcano", "warn", "over", false],
	["bolt-strike-meadow-eye.png", "meadow", "strike", "eye", false], ["bolt-warn-low.png", "meadow", "warn", "eye", true],
	["bolt-warn-meadow-fp.png", "meadow", "warn", "fp", false], ["bolt-strike-meadow-fp.png", "meadow", "strike", "fp", false],
]
const VIEWS := {"eye": [6.5, 14.0, 0.5], "over": [8.5, 52.0, 0.0]} # 시점 → [카메라 거리 (칸), 내려다보는 각 (도), 보는 높이 (칸)]
const FP := "fp" # 1인칭 시점: 가운데 예고 한가운데에 선 내 눈 (높이 C.EYE_HEIGHT, 고개 각 0) — VIEWS 밖 (_aim 이 따로)
const ME_ID := 1
const CAM_YAW := 90.0 # 보는 방향 (도, 게임 +y 쪽)
const BOLT_R := 1.2 # 맞는 반지름 (서버 EVENT_BOLT_RADIUS)
const WARN_MS := 1200.0 # 예고 시간 (서버 EVENT_BOLT_WARN_MS)
const WARN_U := [0.75, 0.2] # 찍는 순간 흐른 비율: 가운데 예고 · 오른쪽 예고
const SIDE_GAP := 3.1 # 가운데에서 좌우 고리까지 (칸)
const STRIKE_AT_MS := 50.0 # 번개가 떨어진 뒤 찍는 시각
const WINDUP_U := 0.5 # 견줄 F 예고 고리의 흐른 비율
const AURA_U := 0.3 # 견줄 발밑 스킬 고리의 흐른 비율 (커짐 1.8 — world/body_fx.gd aura)


# 도는 동안 난 엔진·스크립트 오류 (tools/fx_sheet.gd 와 같음)
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
var job_i := -1
var wait := 0
var saved: Array = []
var failed: Array = []
var spans: Array = []
var done := false
var errors := ErrorLog.new()
var store: Node
var view: Node
var world: Node3D
var bolt: Node3D # world.bolt_fx
var bolt_script: GDScript # 끝날 때 끼워 둔 시계를 빼려고 쥐고 있음
var alert: Control # ui/bolt_alert.gd (판에서는 ui/hud_extra.gd 가 만들어 넣음)
var me := {} # 1인칭 장면의 나 (스냅샷 players[] 한 명 꼴) — 다른 시점은 {} (화면 신호 꺼짐)
var clock_ms := 0.0
var cam := Camera3D.new()
var extras: Array = [] # 견줄 고리 노드
var grid_ver := 3000
var last_floor := ""
var is_low := false
var t0 := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_dir = a[i + 1]
	if DisplayServer.get_name() == "headless":
		print("번개 사진: 화면을 그릴 수 없는 환경 (--headless) 입니다 — xvfb-run -a godot --rendering-driver opengl3 … 로 돌리세요")
		_end(2)
		return
	if out_dir == "" or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		print("번개 사진: --out <폴더> 가 필요합니다 (만들 수 없는 폴더 '%s')" % out_dir)
		_end(1)
		return
	OS.add_logger(errors)
	t0 = Time.get_ticks_msec()
	Engine.time_scale = 0.0


# 첫 프레임에 (자동 로드 View 가 설정 파일을 읽은 뒤): 설정 고정 → 판·카메라
func _setup() -> void:
	store = root.get_node("Store")
	view = root.get_node("View")
	for k in K.SETTINGS:
		view.settings[k] = K.SETTINGS[k]
	_gfx(false)
	world = load("res://world/world.tscn").instantiate()
	root.add_child(world)
	bolt = world.bolt_fx
	bolt_script = bolt.get_script()
	bolt_script.clock = func() -> float: return clock_ms
	alert = load("res://ui/bolt_alert.gd").new()
	root.add_child(alert)
	cam.near = WC.CAM_CLIP[0]
	cam.far = WC.CAM_CLIP[1]
	cam.fov = C.FOV_DEFAULT
	root.add_child(cam)
	cam.make_current()


# 화질: 높음 · 그래픽 낮춤 (설정 파일에는 안 씀). 판이 떠 있으면 world/gfx.gd 가 다시 적용하게 알림
func _gfx(low: bool) -> void:
	is_low = low
	view.settings["lowGfx"] = low
	view.settings["gfx"] = "low" if low else "high"
	if world != null:
		view.changed.emit("gfx")


func _end(code: int) -> void:
	done = true
	if bolt_script != null: # 정적 변수에 이 도구의 함수가 남은 채 엔진이 내려가지 않게
		bolt_script.clock = Callable()
	RL.clear_static()
	M.clear_static()
	quit(code)


func _process(_dt: float) -> bool:
	if done:
		return true
	if world == null:
		_setup()
	if job_i >= 0:
		alert.refresh(me, clock_ms, true)
		wait -= 1
		if wait > 0:
			return false
		_save(str(JOBS[job_i][0]))
		if str(JOBS[job_i][2]) == "strike" and str(JOBS[job_i][3]) != FP:
			_span()
	job_i += 1
	if job_i >= JOBS.size():
		_report()
		return true
	var job: Array = JOBS[job_i]
	cam.make_current() # 판 카메라 (cam_rig) 는 자기 _ready 에서 current 가 됨 → 장면마다 다시 가져옴
	wait = K.WARM_FRAMES
	if bool(job[4]) != is_low:
		_gfx(bool(job[4]))
		wait = K.FIRST_WARM_FRAMES
	if str(job[1]) != last_floor:
		last_floor = str(job[1])
		_stage(str(FLOORS[last_floor]))
		wait = K.FIRST_WARM_FRAMES
	_aim(str(job[3]))
	_fire(str(job[2]))
	return false


func _save(file: String) -> void:
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(file)
	if img == null or img.is_empty() or img.save_png(path) != OK:
		failed.append(file)
		return
	saved.append("%s (%d×%d)" % [path, img.get_width(), img.get_height()])


# 번개 띠가 화면을 얼마나 덮는지: 지금 그려진 띠 토막 (MultiMesh 인스턴스) 양 끝을 화면에 비춘 세로 범위 ÷ 화면 높이
func _span() -> void:
	var vh := float(root.get_visible_rect().size.y)
	var mm: MultiMesh = bolt.bolt_mm
	var lo := INF
	var hi := -INF
	for i in mm.visible_instance_count:
		var t: Transform3D = bolt.bolt_mmi.global_transform * mm.get_instance_transform(i)
		for p in [t.origin, t.origin + t.basis.y]:
			if cam.is_position_behind(p):
				continue
			var y: float = cam.unproject_position(p).y
			lo = minf(lo, y)
			hi = maxf(hi, y)
	if hi < lo:
		spans.append("줄기 화면 높이 비 없음 (안 그려짐)")
		failed.append("bolt-strike (줄기 없음)")
		return
	var ratio := (hi - lo) / vh
	spans.append("줄기 화면 높이 비 %.2f (상한 %.2f, 토막 %d개)" % [ratio, float(M.STRIKE.cap), mm.visible_instance_count])
	if ratio > float(M.STRIKE.cap) + 0.005: # 반올림 몫만
		failed.append("bolt-strike (화면 상한을 넘음)")


func _report() -> void:
	for s in saved:
		print("번개 사진 저장 %s" % s)
	for s in spans:
		print("번개 사진 %s" % s)
	for f in failed:
		print("번개 사진 실패 %s" % f)
	for e in errors.lines:
		print("번개 사진 오류 %s" % e)
	var ok := failed.is_empty() and errors.lines.is_empty() and saved.size() == JOBS.size()
	print("번개 사진: %d장 저장, 실패 %d, 오류 %d줄, %.1f초" % [saved.size(), failed.size(), errors.lines.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	_end(0 if ok else 1)


# ---------- 가짜 판 ----------
static func field_n() -> int:
	return LP.field_size_for(K.PLAYERS)


static func mid() -> Vector2:
	return Vector2(field_n() / 2.0, field_n() / 2.0)


# 판 중 (playing) 스냅샷 모양으로: 지형·사람·블록 없는 빈 바닥 (tools/fx_sheet.gd _stage 와 같은 꼴)
func _stage(map_id: String) -> void:
	var n := field_n()
	var grid := PackedByteArray()
	grid.resize(n * n * int(C.GRID_H))
	grid_ver += 1
	store.my_id = null
	store.grid = grid
	store.grid_version = grid_ver
	store.state = {
		"phase": "playing", "mode": "survival", "time": 0.0, "gridVersion": grid_ver,
		"field": {"w": n, "d": n, "h": int(C.GRID_H)}, "map": {"id": map_id, "choice": map_id},
		"players": [], "pieces": [], "items": [], "events": [],
		"lava": {"active": false, "z": C.LAVA_START_Z}, "round": {"n": 1, "winnerId": null},
	}
	store._players_by_id = {}
	# 판 빛의 하늘 어둡게는 프레임 dt 로 서서히 켜짐 — 시간 배율 0 이라 여기서 끝까지 돌려 둠
	var lf = world.light_fx
	if lf != null and lf.has_method("frame"):
		for i in ceili(1.0 / (C.GAME_LIGHT_SKY_SPEED * 0.1)) + 1:
			lf.frame(true, [], 0.1)


# 카메라: 필드 가운데를 dist 칸 떨어져서 pitch 도 내려다봄
func _aim(view_id: String) -> void:
	var m := mid()
	if view_id == FP: # 내 눈: 가운데 예고 한가운데, 정면 (고개 각 0)
		me = {"id": ME_ID, "x": m.x, "y": m.y, "z": 0.0, "alive": true}
		cam.fov = C.FOV_DEFAULT
		cam.global_transform = Transform3D(Basis.looking_at(Co.dir(deg_to_rad(CAM_YAW), 0.0), Vector3.UP), Co.gxyz(m.x, m.y, C.EYE_HEIGHT))
		return
	me = {}
	var v: Array = VIEWS[view_id]
	var fwd := Co.dir(deg_to_rad(CAM_YAW), -deg_to_rad(float(v[1])))
	var at := Co.gxyz(m.x, m.y, float(v[2]))
	cam.fov = C.FOV_DEFAULT
	cam.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), at - fwd * float(v[0]))


# ---------- 번개·견줄 고리 ----------
func _fire(kind: String) -> void:
	var m := mid()
	bolt.clear()
	alert.clear()
	for n in extras:
		n.queue_free()
	extras.clear()
	clock_ms = 0.0
	# 가운데 예고 (먼저 뜸) · 오른쪽 예고 (나중에 뜸) — 찍는 순간 흐른 비율이 WARN_U
	_event({"type": "boltWarn", "id": 1, "x": m.x, "y": m.y, "z": 0.0, "r": BOLT_R, "ms": WARN_MS})
	clock_ms = WARN_MS * (float(WARN_U[0]) - float(WARN_U[1]))
	_event({"type": "boltWarn", "id": 2, "x": m.x + SIDE_GAP, "y": m.y, "z": 0.0, "r": BOLT_R, "ms": WARN_MS})
	clock_ms = WARN_MS * float(WARN_U[0])
	if kind == "strike":
		_event({"type": "bolt", "id": 1, "x": m.x, "y": m.y, "z": 0.0, "r": BOLT_R, "hits": [ME_ID] if not me.is_empty() else []})
		clock_ms += STRIKE_AT_MS
	# 견줄 고리: 왼쪽 = F 준비 예고 고리 (1번 사람 색), 가운데 예고 안 = 발밑 스킬 고리 (3번 사람 색 — 2번 초록은 초원 바닥에 묻힘)
	var wr := RL.windup_radius(WINDUP_U)
	_ring(RL.mesh("windup", int(C.PLAYER_PALETTE[0])), RL.material(RL.windup_alpha(WINDUP_U), int(RL.WINDUP.priority)), Vector3(m.x - SIDE_GAP, m.y, float(RL.WINDUP.lift)), wr)
	var ar := float(RL.AURA.r) * (1.0 + 1.8 * AURA_U)
	_ring(RL.mesh("aura", int(C.PLAYER_PALETTE[2])), RL.material(float(RL.AURA.alpha) * (1.0 - AURA_U)), Vector3(m.x, m.y, float(RL.AURA.lift)), ar)


# 가짜 서버 이벤트: 세계 그리기 + 화면 신호 둘 다 (판에서는 Store.game_event 가 둘에 알림)
func _event(e: Dictionary) -> void:
	bolt.on_event(e)
	alert.on_event(e, me, clock_ms)


func _ring(mesh: Mesh, mat: Material, at: Vector3, r: float) -> void:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.position = Co.gpos(at)
	n.scale = Vector3(r, 1, r)
	root.add_child(n)
	extras.append(n)

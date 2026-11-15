# 효과 견본 (c6): 서버·봇 없이 싸움 효과를 정해진 자리·시각·카메라로 찍음 (찍을 때마다 같은 사진 → 효과 모양을 바꾸기 전·뒤 비교용)
#   xvfb-run -a godot --path godot/client --resolution 1280x720 --rendering-driver opengl3 -s res://tools/fx_sheet.gd -- --out <폴더> [--only crit,boom] [--low]
# 나오는 파일 (48장): fx-<종류>-<바닥>-<거리>-<시점>.png
#   종류 KINDS 6: crit 치명타 · boom 폭탄 폭발 · bigshell 대형 포탄 · quake 땅 흔들기 (탱크 내려찍기) · rings 고리 세로 (왼쪽)·가로 (오른쪽) · ko 낙사 스매시
#   바닥 FLOORS 2: meadow (밝은 초원 바닥) · volcano (어두운 화산 바닥) — 지형 없는 빈 바닥 판 하나
#   거리 DISTS 2: far (카메라 7칸) · near (2.5칸) / 시점 TIMES 2: a (시작 뒤 0.08초) · b (0.2초)
# 판 그리기 (world/world.tscn) 를 갤러리 (tools/gallery.gd) 처럼 띄우고 가짜 판 상태를 넣음 → 바닥·빛·판 빛이 판 중과 같음.
# 효과는 이 도구의 fx/fx.gd 노드에 가짜 서버 이벤트를 넣어 냄 (치명타·폭탄·땅 흔들기·낙사 = 판과 같은 처리 함수), 대형 포탄은 world/shots.gd bigShellBlast 줄 그대로,
# 고리는 effects.ring 을 직접. 엔진 시간 배율 0 이라 효과가 스스로 안 흐름 → effects.update(dt, cam)·ko.update(dt) 를 손으로 STEP 초씩 돌려 시각을 맞춤.
# 효과 수준은 '높음' (빛·연기·조각 켬), --low 면 '그래픽 낮춤' (덧칠 없이 파편·고리만). 난수 시드는 사진마다 고정.
# 끝나면 저장한 파일 목록 (출력 줄 머리는 '효과 사진' — 본문 글꼴 글자 검사 (test_ui_nodes) 가 스크립트 따옴표 글을 다 훑어서 글꼴에 있는 글자만 씀), 종료 코드 0 (못 만든 사진·스크립트 오류가 있으면 1, 그릴 수 없는 환경 (--headless) 이면 2)
extends SceneTree

const K := preload("res://tools/gallery_config.gd")
const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const WC := preload("res://world/world_config.gd")
const LP := preload("res://world/lobby_preview.gd")
const FXC := preload("res://fx/fx_config.gd")

const KINDS := ["crit", "boom", "bigshell", "quake", "rings", "ko"]
const FLOORS := [["meadow", "flat"], ["volcano", "bowl"]] # [테마 이름 (파일 이름에), 그 테마 맵 id]
const DISTS := [["far", 7.0], ["near", 2.5]] # 카메라 거리 (칸)
const TIMES := [["a", 0.08], ["b", 0.2]] # 효과 시작 뒤 (초)
const STEP := 1.0 / 60.0 # 효과를 손으로 돌리는 한 걸음 (초)
const LOOK_Z := 1.0 # 카메라가 보는 높이 (가슴)
const CAM_PITCH := 12.0 # 내려다보는 각 (도)
const CAM_YAW := 90.0 # 보는 방향 (도, 게임 +y 쪽)
const HOLD_FRAMES := 3 # 같은 장면에서 시각만 흐른 뒤 찍기 전 그릴 프레임
const CLEAR_STEPS := 40 # 앞 효과 지우기: 0.1초씩 이만큼 돌림
const RING_GAP := 1.6 # 고리 견본: 세로·가로 고리를 가운데에서 좌우로 이만큼
const QUAKE_R := 2.5 # 땅 흔들기 반지름 (TANK_SLAM_RANGE)
const BIGSHELL_R := 2.2 # 대형 포탄 반지름 (shots.gd 기본)


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
var only: Array = KINDS
var low := false
var jobs: Array = [] # [파일 이름, 바닥 [테마, 맵], 종류, 거리, 시각 (초), 새 효과인지]
var job_i := -1
var wait := 0
var saved: Array = []
var failed: Array = []
var done := false
var errors := ErrorLog.new()
var store: Node
var view: Node
var world: Node3D
var fx: Node3D
var cam := Camera3D.new()
var grid_ver := 2000
var last_floor := ""
var fx_t := 0.0 # 지금 효과가 흐른 시간 (초)
var t0 := 0


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
		if not KINDS.has(k):
			print("효과 사진: --only 는 %s 중에서 (받은 것 '%s')" % [",".join(KINDS), k])
			_end(1)
			return
	if out_dir == "" or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		print("효과 사진: --out <폴더> 가 필요합니다 (만들 수 없는 폴더 '%s')" % out_dir)
		_end(1)
		return
	OS.add_logger(errors)
	t0 = Time.get_ticks_msec()
	Engine.time_scale = 0.0


# 첫 프레임에 (자동 로드 View 의 _ready 가 user://settings.json 을 읽은 뒤 — _initialize 에서 넣으면 그 파일 값에 덮임): 설정 고정 → 판·효과·카메라
func _setup() -> void:
	store = root.get_node("Store")
	view = root.get_node("View")
	for k in K.SETTINGS:
		view.settings[k] = K.SETTINGS[k]
	view.settings["lowGfx"] = low
	view.settings["gfx"] = "low" if low else "high" # world/gfx.gd 가 이 값으로 화질을 정함 (파일에는 안 씀)
	world = load("res://world/world.tscn").instantiate()
	root.add_child(world)
	# 판의 효과 노드 (world.fx_root 아래) 와 따로: 카메라·시각을 이 도구가 정함. fx.gd 는 자동 로드 (Store) 를 써서 -s 스크립트에선 실행 중에 불러야 함
	fx = load("res://fx/fx.gd").new()
	root.add_child(fx)
	cam.near = WC.CAM_CLIP[0]
	cam.far = WC.CAM_CLIP[1]
	cam.fov = C.FOV_DEFAULT
	root.add_child(cam)
	cam.make_current()
	for fl in FLOORS:
		for kind in KINDS:
			if not only.has(kind):
				continue
			for d in DISTS:
				for ti in TIMES.size():
					jobs.append(["fx-%s-%s-%s-%s.png" % [kind, fl[0], d[0], TIMES[ti][0]], fl, kind, float(d[1]), float(TIMES[ti][1]), ti == 0])


func _end(code: int) -> void:
	done = true
	quit(code)


func _process(_dt: float) -> bool:
	if done:
		return true
	if world == null:
		_setup()
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
	var floor_id := str(job[1][0])
	wait = HOLD_FRAMES
	if job[5]:
		if floor_id != last_floor:
			_stage(str(job[1][1]))
			wait = K.FIRST_WARM_FRAMES
		else:
			wait = K.WARM_FRAMES
		last_floor = floor_id
		_clear()
		_aim(float(job[3]))
		seed(K.SEED + job_i)
		_fire(str(job[2]))
	_run_to(float(job[4]))
	return false


func _save(file: String) -> void:
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(file)
	if img == null or img.is_empty() or img.save_png(path) != OK:
		failed.append(file)
		return
	saved.append("%s (%d×%d)" % [path, img.get_width(), img.get_height()])


func _report() -> void:
	for s in saved:
		print("효과 사진 저장 %s" % s)
	for f in failed:
		print("효과 사진 실패 %s" % f)
	for e in errors.lines:
		print("효과 사진 오류 %s" % e)
	var ok := failed.is_empty() and errors.lines.is_empty() and saved.size() == jobs.size()
	print("효과 사진: %d장 저장, 실패 %d, 오류 %d줄, %.1f초, 효과 수준 %s%s" % [saved.size(), failed.size(), errors.lines.size(), (Time.get_ticks_msec() - t0) / 1000.0, "낮음" if low else "%s (빛 %s·연기 %s·조각 %s)" % [WC.level, fx.effects.lv.glow, fx.effects.lv.smoke, fx.effects.lv.chunks], " (그래픽 낮춤)" if low else ""])
	_end(0 if ok else 1)


# ---------- 가짜 판 ----------
static func field_n() -> int:
	return LP.field_size_for(K.PLAYERS)


static func mid() -> Vector2:
	return Vector2(field_n() / 2.0, field_n() / 2.0)


# 판 중 (playing) 스냅샷 모양으로: 지형·사람·블록 없는 빈 바닥 (tools/gallery.gd _stage 와 같은 꼴)
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
	# 맞는 사람·때린 사람 (이벤트가 자리를 찾을 때만 씀 — state.players 에는 없어 몸은 안 그려짐)
	var m := mid()
	var a := {"id": 1, "x": m.x - 1.0, "y": m.y, "z": 0.0, "alive": true, "slot": 0, "color": 0}
	var b := {"id": 2, "x": m.x, "y": m.y, "z": 0.0, "alive": true, "slot": 1, "color": 1}
	store._players_by_id = {1: a, 2: b}
	# 판 빛의 하늘 어둡게는 프레임 dt 로 서서히 켜짐 — 시간 배율 0 이라 여기서 끝까지 돌려 둠
	var lf = world.light_fx
	if lf != null and lf.has_method("frame"):
		for i in ceili(1.0 / (C.GAME_LIGHT_SKY_SPEED * 0.1)) + 1:
			lf.frame(true, [], 0.1)


# 카메라: 필드 가운데 가슴 높이를 dist 칸 떨어져서 조금 내려다봄
func _aim(dist: float) -> void:
	var m := mid()
	var fwd := Co.dir(deg_to_rad(CAM_YAW), -deg_to_rad(CAM_PITCH))
	var at := Co.gxyz(m.x, m.y, LOOK_Z)
	cam.fov = C.FOV_DEFAULT
	cam.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), at - fwd * dist)


# ---------- 효과 ----------
# 앞 사진의 효과를 다 흘려보냄
func _clear() -> void:
	for i in CLEAR_STEPS:
		_step(0.1)
	fx_t = 0.0


func _step(dt: float) -> void:
	fx.ko.cam = cam
	fx.ko.update(dt)
	fx.effects.update(dt, cam)


func _run_to(t: float) -> void:
	while fx_t + STEP * 0.5 < t:
		_step(STEP)
		fx_t += STEP


func _fire(kind: String) -> void:
	fx.read_settings() # 효과 수준 = 화질 (위 _setup 의 설정): 높음이면 빛·연기·조각 켬
	var m := mid()
	var e = fx.effects
	match kind:
		"crit":
			fx.on_event({"type": "hit", "by": 1, "target": 2, "ok": true, "crit": true, "kind": "melee"})
		"boom":
			fx.on_event({"type": "boom", "x": m.x, "y": m.y, "z": 0.6})
		"bigshell": # world/shots.gd bigShellBlast 줄 그대로
			var p := Vector3(m.x, m.y, 0.8)
			var gz := maxf(0.05, p.z - 0.5)
			e.ring(p, 0xffa040, BIGSHELL_R * 2.2, 0.4)
			e.ring(Vector3(p.x, p.y, gz), 0xffd080, BIGSHELL_R * 2, 0.45, true)
			e.burst(p, null, 0xff8020, 40, 9, 0.16, 0.5)
			e.burst(p, null, 0x666666, 30, 4, 0.22, 1.0)
			e.explode(p, FXC.BOOM_K.bigShell, null, gz)
		"quake":
			fx.on_event({"type": "slam", "x": m.x, "y": m.y, "z": 0.0, "r": QUAKE_R})
		"rings": # 왼쪽 = 카메라를 보는 고리 (치명타 금빛 고리), 오른쪽 = 바닥에 눕힌 고리 (닌자 벽차기 발밑)
			e.ring(Vector3(m.x - RING_GAP, m.y, LOOK_Z), 0xffd030, 4.2)
			e.ring(Vector3(m.x + RING_GAP, m.y, 0.1), 0xffffff, C.NINJA_WALLKICK_RANGE * 2, 0.35, true)
		"ko":
			fx.on_event({"type": "death", "who": 2, "cause": "fall", "x": m.x, "y": m.y, "z": 0.0, "out": {"x": -1, "y": 0}})

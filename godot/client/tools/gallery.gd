# 겉모습 갤러리: 서버·봇 없이 캐릭터·맵·블록을 정해진 시점으로 찍음 (찍을 때마다 같은 사진 → 겉모습을 바꾸기 전·뒤 비교용)
#   xvfb-run -a godot --path godot/client --resolution 1280x720 --rendering-driver opengl3 -s res://tools/gallery.gd -- --out <폴더> [--only chars,maps,pieces] [--low]
# 나오는 파일 (30장):
#   char-<캐릭터 id>.png ×8  — 한 캐릭터를 앞·비스듬히 앞·옆·뒤로 나란히 (팔레트 첫 색)
#   chars-lineup.png          — 8명 정면 한 줄 (팔레트 순서 색)
#   map-<맵 id>-over.png ×7  — 8명 판 크기 시작 지형을 비스듬히 위에서 (필드 전체)
#   map-<맵 id>-eye.png ×7   — 필드 가장자리에 선 사람 눈높이에서 가운데를 봄
#   pieces-<테마 id>.png ×7  — 그 테마 바닥·지형 단 위에 쌓인 테트리미노 7종 + 떨어지는 블록 하나와 그림자 칸
# 판 그리기 (world/world.tscn) 를 그대로 띄우고 서버 스냅샷 자리 (Store.state·Store.grid) 에 가짜 판 상태를 넣음 → 재질·빛·판 빛·먼 배경이 판 중과 같음.
# 캐릭터 몸은 chars.make_body 를 판처럼 자리 노드 아래에 세움. 카메라는 이 도구 것 (판 카메라 대신).
# 같은 사진이 나오게: 난수 시드 고정, 설정은 gallery_config.SETTINGS + 화질 (--low 면 낮음, 아니면 높음) 로 고정 (user://settings.json 과 상관없음, 파일에 안 씀), 엔진 시간 배율 0 (셰이더 TIME·프레임 dt 가 멈춤 — 구름·물결·먼 섬이 그 자리),
# 몸 동작 시계 (chars/ext_motion.gd clock — 외부 모델의 천·클립·가산 층, 몸 효과) 는 벽시계 대신 이 도구의 가상 시계 (자세 걸음·프레임마다 정해진 만큼만 감).
# --low = 설정 '그래픽 낮춤'. 끝나면 저장한 파일 목록, 종료 코드 0 (못 만든 사진·스크립트 오류가 있으면 1, 그릴 수 없는 환경 (--headless) 이면 2)
extends SceneTree

const K := preload("res://tools/gallery_config.gd")
const C := preload("res://core/config.gd")
const Co := preload("res://core/coords.gd")
const Cells := preload("res://world/cells.gd")
const WC := preload("res://world/world_config.gd")
const LP := preload("res://world/lobby_preview.gd")
const ExtMotion := preload("res://chars/ext_motion.gd")
const KINDS := ["chars", "maps", "pieces"]


# 도는 동안 난 엔진·스크립트 오류 (GDScript 는 예외가 없어 그냥 넘어감 → tests/run_tests.gd 처럼 Logger 로 잡음)
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
var jobs: Array = [] # [파일 이름, Callable (장면 깔기), 테마 키]
var job_i := -1
var wait := 0
var saved: Array = []
var failed: Array = []
var done := false
var errors := ErrorLog.new()
var store: Node
var view: Node
var world: Node3D
var cam := Camera3D.new()
# 캐릭터 몸 자리들 (world/bodies.gd 처럼 자리 노드 아래 몸). 그리지 않는 SubViewport 아래에 둠: 같은 3D 세계라 화면 카메라에 그대로 보이지만
# 몸이 '판 화면이 아님' 으로 알아 래그돌 (물리) 을 안 켬 (초상·대기실 큰 캐릭터와 같은 길) — 물리는 시간 배율 0 에서 못 돌고, 켜면 사진마다 자세가 달라짐
var stage_vp := SubViewport.new()
var hide_scenery := false # 캐릭터 사진: 떠 있는 섬·먼 배경을 숨김 (몸 윤곽이 하늘·바닥만 뒤에 두고 보이게)
var Chars = null
var grid_ver := 1000
var last_theme := ""
var t0 := 0
# 몸 동작 가상 시계의 걸음 수 (시각 = gallery_config.clock_s). 자세 한 걸음 (_place)·그린 한 프레임 (_process) 마다 1 — 벽시계와 무관해 찍을 때마다 같은 천·자세
var clock_steps := 0


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
		print("갤러리: 화면을 그릴 수 없는 환경 (--headless) 입니다 — xvfb-run -a godot --rendering-driver opengl3 … 로 돌리세요")
		_end(2)
		return
	for k in only:
		if not KINDS.has(k):
			print("갤러리: --only 는 %s 중에서 (받은 것 '%s')" % [",".join(KINDS), k])
			_end(1)
			return
	if out_dir == "" or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		print("갤러리: --out <폴더> 가 필요합니다 (만들 수 없는 폴더 '%s')" % out_dir)
		_end(1)
		return
	OS.add_logger(errors)
	t0 = Time.get_ticks_msec()
	seed(K.SEED)
	Engine.time_scale = 0.0
	ExtMotion.clock = func(): return K.clock_s(clock_steps)


# 첫 프레임에 (자동 로드 View 의 _ready 가 user://settings.json 을 읽은 뒤 — _initialize 에서 넣으면 그 파일 값에 덮임, tools/fx_sheet.gd 와 같음): 설정 고정 → 판·카메라·찍을 차례.
# 예전엔 _initialize 에서 넣어, 파일에 gfx: low 가 남아 있으면 (확인용 --low 실행 뒤) 갤러리가 통째로 낮음 화질로 찍혔음 (c6 리뷰 M1)
func _setup() -> void:
	store = root.get_node("Store")
	view = root.get_node("View")
	for k in K.SETTINGS:
		view.settings[k] = K.SETTINGS[k]
	view.settings["lowGfx"] = low
	view.settings["gfx"] = K.gfx_choice(low) # world/gfx.gd 가 이 값으로 화질을 정함 (파일에는 안 씀)
	Chars = load("res://chars/chars.gd")
	world = load("res://world/world.tscn").instantiate()
	root.add_child(world)
	stage_vp.size = Vector2i(2, 2)
	stage_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(stage_vp)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	cam.near = WC.CAM_CLIP[0]
	cam.far = WC.CAM_CLIP[1]
	root.add_child(cam)
	cam.make_current()
	_plan()


func _end(code: int) -> void:
	done = true
	ExtMotion.clock = Callable() # 끝나면 가상 시계를 뺌 (core/replay.gd 처럼)
	quit(code)


# 찍을 사진 차례 (맵·테마·캐릭터 목록은 config 에서)
func _plan() -> void:
	if only.has("chars"):
		var first := int(C.PLAYER_PALETTE[0])
		for c in C.CHARACTERS:
			var row := []
			for turn in K.CHAR_TURNS:
				row.append([str(c), first, float(turn)])
			jobs.append(["char-%s.png" % c, _scene_chars.bind(row), K.CHAR_MAP])
		var line := []
		for i in C.CHARACTERS.size():
			line.append([str(C.CHARACTERS[i]), int(C.PLAYER_PALETTE[i % C.PLAYER_PALETTE.size()]), 0.0])
		jobs.append(["chars-lineup.png", _scene_chars.bind(line), K.CHAR_MAP])
	if only.has("maps"):
		for m in C.MAPS:
			jobs.append(["map-%s-over.png" % m, _scene_map.bind(str(m), true), str(m)])
			jobs.append(["map-%s-eye.png" % m, _scene_map.bind(str(m), false), str(m)])
	if only.has("pieces"):
		var seen := {}
		for m in C.MAPS:
			var th = C.WORLD_MAP_THEME.get(m)
			if th == null or seen.has(th):
				continue
			seen[th] = true
			jobs.append(["pieces-%s.png" % th, _scene_pieces.bind(str(m)), str(m)])


func _process(_dt: float) -> bool:
	if done:
		return true
	if world == null:
		_setup()
		return false
	clock_steps += 1 # 이 프레임의 몸 _process (외부 모델 천) 가 볼 시각 — 이 함수가 노드들보다 먼저 돎
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
	(job[1] as Callable).call()
	wait = K.WARM_FRAMES if str(job[2]) == last_theme else K.FIRST_WARM_FRAMES
	last_theme = str(job[2])
	return false


# 방금 그린 화면을 저장 (빈 화면·못 쓴 파일은 실패로)
func _save(file: String) -> void:
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(file)
	if img == null or img.is_empty() or img.save_png(path) != OK:
		failed.append(file)
		return
	saved.append("%s (%d×%d)" % [path, img.get_width(), img.get_height()])


func _report() -> void:
	for s in saved:
		print("갤러리 저장 %s" % s)
	for f in failed:
		print("갤러리 실패 %s" % f)
	for e in errors.lines:
		print("갤러리 오류 %s" % e)
	var ok := failed.is_empty() and errors.lines.is_empty() and saved.size() == jobs.size()
	print("갤러리: %d장 저장, 실패 %d, 오류 %d줄, %.1f초%s" % [saved.size(), failed.size(), errors.lines.size(), (Time.get_ticks_msec() - t0) / 1000.0, " (그래픽 낮춤)" if low else ""])
	_end(0 if ok else 1)


# 판 (world.gd) 이 프레임마다 묶음 보임을 다시 정함 → 그리기 직전에 덮어씀
func _pre_draw() -> void:
	if hide_scenery and world != null and world.scenery != null:
		world.scenery.visible = false


# ---------- 가짜 판 상태 ----------
static func field_n() -> int:
	return LP.field_size_for(K.PLAYERS)


static func grid_h() -> int:
	return int(C.GRID_H)


# 판 중 (playing) 스냅샷 모양으로: 격자·떨어지는 블록만, 사람·아이템·위험 없음
func _stage(map_id: String, n: int, grid: PackedByteArray, pieces: Array) -> void:
	for f in stage_vp.get_children():
		stage_vp.remove_child(f)
		f.queue_free()
	hide_scenery = false
	grid_ver += 1
	store.my_id = null
	store.grid = grid
	store.grid_version = grid_ver
	store.state = {
		"phase": "playing", "mode": "survival", "time": 0.0, "gridVersion": grid_ver,
		"field": {"w": n, "d": n, "h": grid_h()}, "map": {"id": map_id, "choice": map_id},
		"players": [], "pieces": pieces, "items": [], "events": [],
		"lava": {"active": false, "z": C.LAVA_START_Z}, "round": {"n": 1, "winnerId": null},
	}
	# 판 빛의 하늘 어둡게는 프레임 dt 로 서서히 켜짐 — 시간 배율 0 이라 여기서 끝까지 돌려 둠 (판 중 모습 = 다 켜진 상태)
	var lf = world.light_fx
	if lf != null and lf.has_method("frame"):
		for i in ceili(1.0 / (C.GAME_LIGHT_SKY_SPEED * 0.1)) + 1:
			lf.frame(true, [], 0.1)


static func empty_grid(n: int) -> PackedByteArray:
	var g := PackedByteArray()
	g.resize(n * n * grid_h())
	return g


static func cell_index(n: int, x: int, y: int, z: int) -> int:
	return (z * n + y) * n + x


# ---------- 카메라 ----------
# 게임 좌표 look (바라볼 점) 을 화면 가운데에 두고 (yaw 쪽을 pitch 만큼 내려다봄) 물러난 자리에서 봄.
# 거리 = pts (게임 좌표 점들) 가 전부 화면 안 (margin 비율) 에 드는 가장 가까운 거리
func _aim(look: Vector3, yaw: float, pitch: float, fov: float, pts: Array, margin: float) -> void:
	var fwd := Co.dir(yaw, -deg_to_rad(pitch))
	var back := -fwd
	var basis := Basis.looking_at(fwd, Vector3.UP)
	var size := Vector2(root.size)
	var tv := tan(deg_to_rad(fov) / 2.0) * margin
	var th := tv * size.x / maxf(1.0, size.y)
	var at := Co.gpos(look)
	var gp := []
	for p in pts:
		gp.append(Co.gpos(p))
	var inside := func(dist: float) -> bool:
		var inv := Transform3D(basis, at + back * dist).affine_inverse()
		for p in gp:
			var v: Vector3 = inv * p
			if -v.z <= 0.01 or absf(v.x) > -v.z * th or absf(v.y) > -v.z * tv:
				return false
		return true
	var hi := 1.0
	while not inside.call(hi) and hi < 4000.0:
		hi *= 2.0
	var lo := hi / 2.0
	for i in 24:
		var mid := (lo + hi) / 2.0
		if inside.call(mid):
			hi = mid
		else:
			lo = mid
	cam.fov = fov
	cam.global_transform = Transform3D(basis, at + back * hi)


# ---------- 캐릭터 ----------
# list: [캐릭터 id, 색 0xRRGGBB, 돌린 각 (도)] 를 화면 왼쪽부터 한 줄로. 초원 낮 빛·빈 바닥 위, 카메라는 해 쪽에서
func _scene_chars(list: Array) -> void:
	var n := field_n()
	_stage(K.CHAR_MAP, n, empty_grid(n), [])
	hide_scenery = true
	var sun: Array = Cells.theme_of(K.CHAR_MAP).get("sunDir", C.SUN_DIR)
	var az := atan2(float(sun[1]), float(sun[0])) + deg_to_rad(K.CHAR_SUN_OFF) # 필드 가운데에서 카메라가 있는 쪽
	var to_cam := Vector2(cos(az), sin(az))
	var right := Vector2(-sin(az), cos(az)) # 카메라가 가운데를 볼 때 화면 오른쪽 (게임 x, y)
	var mid := Vector2(n / 2.0, n / 2.0)
	# 줄 좌표 (x 화면 오른쪽, y 위, z 카메라 쪽) → 고도 좌표
	var frame := Transform3D(Basis(Co.gxyz(right.x, right.y, 0), Vector3.UP, Co.gxyz(to_cam.x, to_cam.y, 0)), Co.gxyz(mid.x, mid.y, 0))
	var figs := []
	for e in list:
		var holder := Node3D.new()
		stage_vp.add_child(holder)
		var body: Node3D = Chars.make_body(str(e[0]), Co.color(e[1]))
		holder.add_child(body)
		figs.append({"holder": holder, "body": body, "turn": deg_to_rad(float(e[2])), "id": 9001 + figs.size(), "at": mid})
	# 몸마다 줄 방향 폭을 재서 틈 CHAR_GAP 으로 붙여 세우고, 전부 화면에 들게 카메라 거리를 맞춤.
	# 정면 = 그 몸에서 카메라를 보는 방향 (가장자리 몸도 정확히 앞·옆·뒤가 보이게) → 카메라 자리에 따라 조금 달라져 몇 번 되풀이
	var dist := 30.0
	for pass_i in K.CHAR_FIT_PASSES:
		var cam_xy := mid + to_cam * dist * cos(deg_to_rad(K.CHAR_CAM_PITCH))
		var boxes := []
		var total := -K.CHAR_GAP
		var top := 0.0
		for f in figs:
			_place(f, f.at, (cam_xy - Vector2(f.at)).angle() + float(f.turn))
			var box := bounds_in(f.holder, frame)
			box.position.x -= frame.basis.x.dot(f.holder.position - frame.origin) # 몸 축 기준 폭
			boxes.append(box)
			total += box.size.x + K.CHAR_GAP
			top = maxf(top, box.end.y)
		var x := -total / 2.0
		var pts := []
		for i in figs.size():
			var box: AABB = boxes[i]
			var ax := x - box.position.x # 이 몸 축이 설 줄 좌표
			figs[i].at = mid + right * ax
			for k in 8:
				pts.append(Co.game(frame * (box.get_endpoint(k) + Vector3(ax, 0, 0))))
			x += box.size.x + K.CHAR_GAP
		_aim(Vector3(mid.x, mid.y, top / 2.0), az + PI, K.CHAR_CAM_PITCH, K.CHAR_FOV, pts, K.CHAR_MARGIN)
		dist = (cam.global_position - Co.gxyz(mid.x, mid.y, top / 2.0)).length()
	for f in figs:
		_place(f, f.at, (Vector2(Co.game(cam.global_position).x, Co.game(cam.global_position).y) - Vector2(f.at)).angle() + float(f.turn))
	_settle(figs)


# 몸 자리·방향 (world/bodies.gd 처럼 자리 노드를 옮기고 몸은 pose) + 가만히 선 자세로 돌림 (늘 같은 시각 값 → 같은 자세)
func _place(f: Dictionary, at: Vector2, yaw: float) -> void:
	var holder: Node3D = f.holder
	holder.position = Co.gxyz(at.x, at.y, 0.0)
	holder.rotation = Vector3(0, Co.rot_y(yaw), 0)
	var p := {"id": f.id, "alive": true, "x": at.x, "y": at.y, "z": 0.0, "yaw": yaw, "damage": 0.0}
	for i in K.CHAR_POSE_STEPS:
		clock_steps += 1
		f.body.pose(p, i * K.CHAR_POSE_MS)


# 마지막 자리에 선 채로 가상 시간만 더 흘림 (c6 리뷰 F7). 찍는 프레임들에서 외부 모델은 자기 _process 의 sync() (클립 층 없는 코드 자세) 로 돌아서,
# 자세 돌리기 (_place — pose 가 클립 층까지 맞춘 자세, 몸마다 옮기고 돌리기 여러 번) 직후엔 천 (사냥꾼 망토 등) 이 그 사이를 옮겨 가며 크게 흔들리는 중.
# 찍기 전 데우기 (8~20프레임 = 0.13~0.32초) 로는 못 가라앉아 망토가 옆으로 뻗은 순간이 사진에 고정됐음 → 찍는 프레임과 같은 걸음 (시계 한 걸음 + sync()) 을 미리 돌림.
# 외부 모델이 없는 몸 (천 없음) 은 건드리지 않음 — 예전 사진과 같음
func _settle(figs: Array) -> void:
	for i in K.CHAR_SETTLE_STEPS:
		clock_steps += 1
		for f in figs:
			var ext = f.body.get("ext")
			if ext != null:
				ext.sync()


# n 아래 보이는 메시들의 상자를 frame 좌표로 (ui/portrait.gd _bounds 와 같되 줄 방향 축으로 — 비스듬한 줄에서도 폭이 부풀지 않게)
static func bounds_in(n: Node, frame: Transform3D) -> AABB:
	var inv := frame.affine_inverse()
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var local := m.get_aabb()
		var xf := inv * m.global_transform
		for k in 8:
			var v := xf * local.get_endpoint(k)
			if first:
				out = AABB(v, Vector3.ZERO)
				first = false
			else:
				out = out.expand(v)
	return out


# ---------- 맵 ----------
func _scene_map(map_id: String, over: bool) -> void:
	var n := field_n()
	var P := LP.build(map_id, n, grid_h())
	_stage(map_id, n, P.grid, [])
	var top_max := 0.0
	for t in P.top:
		top_max = maxf(top_max, t)
	if over:
		var V: Dictionary = K.MAP_OVER
		var pts := []
		for x in [0.0, float(n)]:
			for y in [0.0, float(n)]:
				pts.append(Vector3(x, y, 0.0))
				pts.append(Vector3(x, y, top_max))
		_aim(Vector3(n / 2.0, n / 2.0, float(V.look_z)), deg_to_rad(float(V.yaw)), float(V.pitch), float(V.fov), pts, float(V.margin))
		return
	var E: Dictionary = K.MAP_EYE
	var mid := Vector2(n / 2.0, n / 2.0)
	var mid_top: float = P.top[int(mid.y) * n + int(mid.x)]
	var spot := eye_spot(P, n)
	var eye := Vector3(spot.x + 0.5, spot.y + 0.5, float(P.top[spot.y * n + spot.x]) + C.EYE_HEIGHT)
	cam.fov = C.FOV_DEFAULT
	cam.look_at_from_position(Co.gpos(eye), Co.gxyz(mid.x, mid.y, mid_top + float(E.look_z)), Vector3.UP)


# 눈높이 사진을 찍을 가장자리 칸: 후보를 차례로, 가운데 쪽 앞 clear 칸 안에 눈높이를 넘는 기둥이 없는 첫 자리 (다 막혔으면 첫 후보)
static func eye_spot(P: Dictionary, n: int) -> Vector2i:
	var first := Vector2i(-1, -1)
	for s in K.MAP_EYE_SPOTS:
		var c := Vector2i(roundi(float(s[0]) * (n - 1)), roundi(float(s[1]) * (n - 1)))
		if first.x < 0:
			first = c
		var eye_z: float = P.top[c.y * n + c.x] + C.EYE_HEIGHT
		var dir := (Vector2(n / 2.0, n / 2.0) - (Vector2(c) + Vector2(0.5, 0.5))).normalized()
		var open := true
		for k in range(1, int(K.MAP_EYE.clear) + 1):
			var q := Vector2(c) + Vector2(0.5, 0.5) + dir * k
			var qi := Vector2i(floori(q.x), floori(q.y))
			if qi.x >= 0 and qi.y >= 0 and qi.x < n and qi.y < n and P.top[qi.y * n + qi.x] >= eye_z:
				open = false
		if open:
			return c
	return first


# ---------- 블록 ----------
# 그 테마 바닥 위: 뒤 지형 단 + 쌓인 테트리미노 7종 (세워서) + 떨어지는 블록 하나와 그림자 칸. 카메라는 해가 있는 쪽 변에서
func _scene_pieces(map_id: String) -> void:
	var n := field_n()
	var sun: Array = Cells.theme_of(map_id).get("sunDir", C.SUN_DIR)
	var flip := float(sun[1]) > 0.0 # 해가 +y 쪽이면 카메라도 +y 변에서 -y 쪽을 봄 (배치를 180도 돌림)
	var at := func(u: int, v: int) -> Vector2i:
		return Vector2i(n - 1 - u, n - 1 - v) if flip else Vector2i(u, v)
	var grid := empty_grid(n)
	var pts := []
	var put := func(u: int, v: int, z: int, value: int) -> void:
		var c: Vector2i = at.call(u, v)
		grid[cell_index(n, c.x, c.y, z)] = value
		for dz in 2:
			for k in 4:
				pts.append(Vector3(c.x + (k & 1), c.y + (k >> 1), z + dz))
	var L: Dictionary = K.PIECES_LEDGE
	for u in range(int(L.u[0]), int(L.u[1]) + 1):
		for v in range(int(L.v[0]), int(L.v[1]) + 1):
			for z in int(L.h):
				put.call(u, v, z, Cells.TERRAIN)
	for e in K.PIECES_LANDED:
		var value: int = Cells.SHAPE_BASE + Cells.SHAPE_NAMES.find(str(e[0]))
		for c in e[4]:
			put.call(int(e[1]) + int(c[0]), int(e[2]), int(e[3]) + int(c[1]), value)
	var F: Dictionary = K.PIECES_FALL
	var cells := []
	var shadow := []
	for c in F.cells:
		var q: Vector2i = at.call(int(F.u) + int(c[0]), int(F.v) + int(c[1]))
		cells.append([q.x, q.y, int(F.z)])
		shadow.append([q.x, q.y])
		for k in 4:
			pts.append(Vector3(q.x + (k & 1), q.y + (k >> 1), 0.0))
			pts.append(Vector3(q.x + (k & 1), q.y + (k >> 1), int(F.z) + 1.0))
	var piece := {"id": 1, "shape": str(F.shape), "phase": "fall", "cells": cells, "shadow": shadow, "landZ": 0.0, "shadowVisible": true, "eta": float(F.eta)}
	_stage(map_id, n, grid, [piece])
	# 바라볼 점 = 놓은 것들의 가운데
	var lo: Vector3 = pts[0]
	var hi: Vector3 = pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var V: Dictionary = K.PIECES_CAM
	_aim((lo + hi) / 2.0, -PI / 2.0 if flip else PI / 2.0, float(V.pitch), float(V.fov), pts, float(V.margin))

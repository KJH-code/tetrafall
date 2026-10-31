# 캐릭터 몸 하나 (client/figure.js buildFigure·figureAnim + render.js 몸 애니 부분 옮김). chars.gd make_body 가 만듦
# 몸 모양 (맨몸 + 옷·무기·소품, 노드 나무·정점·재질) 은 tools/gen-bodies.mjs 가 JS buildFigure 를 실제로 돌려 뽑은 chars/data/bodies.json 그대로 → JS 와 같은 모양
# 관절 (엉덩이·허리·목·어깨·팔꿈치·손·허벅지·무릎·발) 과 특별 노드 (천 자락·방패·총·활·뿔·바드 폼…) 는 그 자료의 refs 표로 찾음
# 몸 안은 게임 좌표 그대로 (앞 +x, 왼쪽 +y, 위 +z, three.js 와 같은 XYZ 회전 순서) — 맨 위 'frame' 노드 하나가 고도 (x, z, -y) 로 돌림 (core/coords.gd 와 같은 돌림)
# 아직: 광전사 분노 표시 (눈 충혈·핏줄)·어지러움 눈동자·바드 폼 전환 튀기기·유령화 반투명·체크 무늬 반복 수·그리기 수 줄이기
extends Node3D

const C := preload("res://core/config.gd")
const G3 := preload("res://shaders/g3.gd")
const Pose := preload("res://chars/figure_pose.gd")
const Motion := preload("res://chars/figure_motion.gd")
const Moves := preload("res://chars/moves.gd")

# 스킬·필살기 이벤트 → 몸 동작 (main.js handleEvent 의 renderer.skillMove). [동작, 준비 ms 를 e.ms 에서 받음]
const SKILL_START := {"leapWarn": ["hunterLeap", true], "aim": ["hunterAim", true], "blink": ["ninjaDash", false], "wallKick": ["ninjaWallKick", false], "charge": ["tankCharge", false], "slamWarn": ["tankSlam", true], "wallWarn": ["builderWall", true], "bigBombWarn": ["builderBig", false], "padBoost": ["builderPad", false], "song": ["bardSong", false], "rush": ["berserkerLeap", false], "rushLand": ["berserkerSlam", false], "groundShot": ["cannonJump", false], "blockGrab": ["hookSlam", true]}
# 판정 순간 → 준비하던 동작을 타격으로 (renderer.skillStrike). [동작, 준비 중일 때만]
const SKILL_STRIKE := {"leap": ["hunterLeap", false], "shot": ["hunterAim", false], "slam": ["tankSlam", false], "wallRise": ["builderWall", true], "hookThrow": ["hookThrow", false], "blockSlam": ["hookSlam", false]}
# 몸이 크게 휘청하는 공격 (render.js HEAVY_HITS)
const HEAVY_HITS := ["bomb", "shock", "projectile", "slam", "wall", "blast", "bigbomb", "quake", "blockslam", "execute", "pounce", "shell", "bigshell", "groundshot", "leapwave", "spinend"]

var char_id := ""
var d := {} # 체형 (FIGURE_BODIES 한 줄)
var skin_color := Color.WHITE
var mats: Array[Material] = []
var nodes: Array[Node3D] = []
var refs := {} # figure 의 특별 노드 표 (gen-bodies.mjs refs: flaps·shields·gun·bow·horns·formParts…)
var torso: Node3D
var flap_s := {"x": 0.0, "v": 0.0}
var form := ""
var frame: Node3D # 게임 좌표 → 고도
var rig: Node3D # 몸 전체 기울임·공중제비·구르기 (render.js rig)
var hips: Node3D
var waist: Node3D
var neck: Node3D
var shoulders: Array[Node3D] = []
var elbows: Array[Node3D] = []
var hands: Array[Node3D] = []
var thighs: Array[Node3D] = []
var knees: Array[Node3D] = []
var feet: Array[Node3D] = []

# 자세 상태 (figureAnim fig.*)
var P := {} # 지금 자세
var V := {} # 관절 속도
var sw := {"x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0}
var sway_id := -1
var spin_s := 0.0
var drop_s = null
var twist_k := 0.0

# 움직임 상태 (render.js animate 의 a.*)
var pid := -1
var last_ms = null
var prev_pos = null
var hs := 0.0
var vz := 0.0
var vxs := 0.0
var vys := 0.0
var pvxs = null
var pvys = null
var acc_f := 0.0
var acc_s := 0.0
var walk := 0.0
var t := 0.0
var fall_vz := 0.0
var land := 0.0
var land_pow := 0.0
var recover := 0.0
var recover_pow := 0.0
var was_stunned := false
var recover_pending := false
var tumbled := false
var tumbling := false
var tumble_amt := 0.0
var tumble_spin := 0.0
var tumble_axis := Vector3(0, 1, 0)
var flip := -1.0
var flip_rest := 0.0
var air_dash_t := 0.0
var air_dashes_prev = null
var idle_t := 0.0
var vic_t := -1.0
var emote_t := 0.0

# 공격·맞음 (render.js acts·hits): 시각은 초 (Time 기준)
var seq := 0
var act = null # {id, move, t0, windup, struck, rec, broken, air}
var hit = null # {id, t0, stop, dir (Vector2 게임), pow}
var finish_at := -1e9
var counter_at := -1e9


func build(char_id_: String, color: Color) -> void:
	char_id = char_id_
	var data := _data()
	var cd: Dictionary = data.chars.get(char_id, data.chars[C.FIGURE_CHARS[0]])
	var body_kind: String = C.FIGURE_BODY.get(char_id, "lean")
	d = C.FIGURE_BODIES.get(body_kind, C.FIGURE_BODIES.lean)
	skin_color = color
	frame = Node3D.new()
	frame.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)) # 게임 x→x, y→-z, z→y (coords.gd 와 같은 돌림)
	add_child(frame)
	# 재질 (figure.js flat·costume·eyeWhiteMat…): 피부 = 플레이어 색, 근육 홈 = 피부 × FIGURE_MUSCLE_SHADE, 나머지는 옷 색 그대로
	for m in cd.mats:
		mats.append(_material(m, color))
	# 노드 나무: 몸 안 게임 좌표 그대로 (three.js 와 같은 XYZ 회전 순서)
	for e in cd.nodes:
		var n: Node3D
		if e.has("geo"):
			var mi := MeshInstance3D.new()
			mi.mesh = _mesh(data, int(e.geo))
			mi.material_override = mats[int(e.mat)]
			if e.get("noShadow", false):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n = mi
		else:
			n = Node3D.new()
		n.rotation_order = EULER_ORDER_XYZ
		n.position = Vector3(e.p[0], e.p[1], e.p[2])
		n.quaternion = Quaternion(e.q[0], e.q[1], e.q[2], e.q[3])
		n.scale = Vector3(e.s[0], e.s[1], e.s[2])
		n.visible = not e.get("hidden", false)
		var parent: int = int(e.parent)
		(frame if parent < 0 else nodes[parent]).add_child(n)
		nodes.append(n)
	refs = cd.refs
	rig = _n(refs.rig)
	hips = _n(refs.hips)
	waist = _n(refs.waist)
	neck = _n(refs.neck)
	torso = _n(refs.torso)
	for i in 2:
		shoulders.append(_n(refs.shoulders[i]))
		elbows.append(_n(refs.elbows[i]))
		hands.append(_n(refs.hands[i]))
		thighs.append(_n(refs.thighs[i]))
		knees.append(_n(refs.knees[i]))
		feet.append(_n(refs.feet[i]))
	var hammer := _n(refs.get("hammer"))
	if hammer != null:
		hammer.visible = char_id == "builder" # 건축가 무기
	P = Motion.rest_pose(d)
	V = Motion.zero_pose(P)
	_apply(0.0)


# 노드 표 번호 {node: i} → 노드 (없으면 null)
func _n(r) -> Node3D:
	if r is Dictionary and r.has("node"):
		return nodes[int(r.node)]
	return null


# ---------- 만든 몸 자료 (tools/gen-bodies.mjs 가 client/figure.js 에서 뽑은 chars/data/bodies.json) ----------
static var _cache := {}


static func _data() -> Dictionary:
	if not _cache.has("data"):
		_cache.data = JSON.parse_string(FileAccess.get_file_as_string("res://chars/data/bodies.json"))
		_cache.meshes = {}
		_cache.plaid = {}
	return _cache.data


static func _floats(s) -> PackedFloat32Array:
	return Marshalls.base64_to_raw(s).to_float32_array() if s != null else PackedFloat32Array()


# 정점 묶음 → ArrayMesh (몸끼리 같이 씀). three 는 반시계가 앞면, 고도는 시계가 앞면 → 삼각형 두 점을 바꿈. uv 의 v 는 뒤집음
static func _mesh(data: Dictionary, gi: int) -> ArrayMesh:
	if _cache.meshes.has(gi):
		return _cache.meshes[gi]
	var g: Dictionary = data.geos[gi]
	var pos := _floats(g.pos)
	var nor := _floats(g.get("nor"))
	var uvs := _floats(g.get("uv"))
	var n := int(g.n)
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var us := PackedVector2Array()
	vs.resize(n)
	if nor.size() == n * 3:
		ns.resize(n)
	if uvs.size() == n * 2:
		us.resize(n)
	for tri in range(0, n - 2, 3):
		for k in 3:
			var src: int = tri + k
			var dst: int = tri + [0, 2, 1][k]
			vs[dst] = Vector3(pos[src * 3], pos[src * 3 + 1], pos[src * 3 + 2])
			if ns.size() == n:
				ns[dst] = Vector3(nor[src * 3], nor[src * 3 + 1], nor[src * 3 + 2])
			if us.size() == n:
				us[dst] = Vector2(uvs[src * 2], 1.0 - uvs[src * 2 + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	if ns.size() == n:
		arr[Mesh.ARRAY_NORMAL] = ns
	if us.size() == n:
		arr[Mesh.ARRAY_TEX_UV] = us
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_cache.meshes[gi] = am
	return am


# 재질 하나 (gen-bodies.mjs mats 한 줄)
static func _material(m: Dictionary, skin: Color) -> Material:
	var col := Color.from_rgba8((int(m.color) >> 16) & 0xff, (int(m.color) >> 8) & 0xff, int(m.color) & 0xff)
	if m.get("skin", false):
		col = skin
	elif m.get("shade", false):
		col = Color(skin.r * C.FIGURE_MUSCLE_SHADE, skin.g * C.FIGURE_MUSCLE_SHADE, skin.b * C.FIGURE_MUSCLE_SHADE)
	var alpha: float = m.opacity if m.get("transparent", false) else 1.0
	if m.kind == "basic":
		var b := StandardMaterial3D.new()
		b.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		b.albedo_color = Color(col.r, col.g, col.b, alpha)
		if alpha < 1.0:
			b.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if m.get("double", false):
			b.cull_mode = BaseMaterial3D.CULL_DISABLED
		return b
	var opts := {"outline": m.get("outline", true), "opacity": alpha}
	if int(m.get("emissive", 0)) != 0:
		opts.emissive = int(m.emissive)
	if m.has("plaid"):
		opts.map = _plaid(m.plaid)
	return G3.toon_material(col, opts)


# 체크 무늬 천 (figure.js plaidTexture: 32×32 에 칠한 사각형을 그 투명도로 겹침)
static func _plaid(fills: Array) -> Texture2D:
	var key := JSON.stringify(fills)
	if _cache.plaid.has(key):
		return _cache.plaid[key]
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for f in fills:
		var c := Color.html(str(f[0]))
		var a: float = f[1]
		for y in range(int(f[3]), mini(32, int(f[3]) + int(f[5]))):
			for x in range(int(f[2]), mini(32, int(f[2]) + int(f[4]))):
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(c.r, c.g, c.b, 1.0), a))
	var tex := ImageTexture.create_from_image(img)
	_cache.plaid[key] = tex
	return tex


# 자동 로드 Store (이름으로 직접 쓰면 '-s' 테스트 실행에선 컴파일이 안 됨 → 노드로 찾음, 없으면 null)
static func _store():
	var ml = Engine.get_main_loop()
	return ml.root.get_node_or_null("Store") if ml is SceneTree else null


# ---------- 매 프레임 (World 가 부름) ----------
func pose(p: Dictionary, now_ms: float) -> void:
	pid = int(p.id)
	var dt := 0.0 if last_ms == null else clampf((now_ms - last_ms) / 1000.0, 0.0, 0.1)
	last_ms = now_ms
	var store = _store()
	var pos: Vector3 = store.view_pos(pid) if store != null else Vector3(float(p.get("x", 0.0)), float(p.get("y", 0.0)), float(p.get("z", 0.0)))
	_move_state(p, pos, dt)
	var st := _anim_state(p, now_ms)
	_figure_anim(st, dt)
	_apply(dt)


# 속도·공중·걷기·착지·경직 회복·2단 점프·공중 대시·가만히 (render.js animate·figureFlight·figureHabits)
func _move_state(p: Dictionary, pos: Vector3, dt: float) -> void:
	if prev_pos == null or dt <= 0.0:
		prev_pos = pos
		return
	var pp: Vector3 = prev_pos
	var vx := (pos.x - pp.x) / maxf(dt, 1e-3)
	var vy := (pos.y - pp.y) / maxf(dt, 1e-3)
	var vzr := (pos.z - pp.z) / maxf(dt, 1e-3)
	prev_pos = pos
	var k := 1.0 - exp(-C.ANIM_SMOOTH * dt)
	hs += (Vector2(vx, vy).length() - hs) * k
	vz += (vzr - vz) * k
	var air := absf(vz) > C.ANIM_AIR_VZ or not _feet_on_ground(pos)
	var walking := not air and hs > C.ANIM_WALK_MIN_SPEED
	if walking:
		walk += dt * hs * C.ANIM_WALK_FREQ * float(Pose.gait_of(char_id).freq)
	vxs += (vx - vxs) * k
	vys += (vy - vys) * k
	var stunned: bool = p.get("stunned", false)
	# 구르기: 경직 중 빠르게 날아가면 날아가는 쪽으로 머리부터
	var fast := hs > C.FIGURE_TUMBLE_MIN_SPEED
	tumbling = stunned and (fast or (tumbling and hs > C.FIGURE_TUMBLE_MIN_SPEED * 0.4))
	var yaw: float = p.get("yaw", 0.0)
	if tumbling:
		tumbled = true
		var lx := cos(yaw) * vxs + sin(yaw) * vys
		var ly := -sin(yaw) * vxs + cos(yaw) * vys
		var ln := Vector2(lx, ly).length()
		if ln > 0.5:
			tumble_axis = Vector3(-ly / ln, lx / ln, 0)
		tumble_spin += dt * C.FIGURE_TUMBLE_SPEED
	elif tumble_spin != 0.0:
		var to := PI * 2 * ceilf(tumble_spin / (PI * 2) - 0.25)
		tumble_spin += (to - tumble_spin) * k
		if absf(to - tumble_spin) < 0.01:
			tumble_spin = 0.0
	tumble_amt += ((1.0 if tumbling else 0.0) - tumble_amt) * k
	# 경직이 풀리면 (땅에 닿은 뒤) 쪼그렸다 일어남
	if was_stunned and not stunned:
		recover_pending = true
	if stunned:
		recover_pending = false
	was_stunned = stunned
	if recover_pending and not air:
		recover = 1.0
		recover_pow = 1.0 if tumbled else 0.5
		recover_pending = false
		tumbled = false
	recover = maxf(0.0, recover - dt / C.FIGURE_RECOVER_S)
	# 착지: 떨어진 속도만큼 무릎
	if air:
		fall_vz = minf(fall_vz, vz)
	elif fall_vz < -C.ANIM_AIR_VZ:
		land = 1.0
		land_pow = minf(1.0, -fall_vz / C.FIGURE_LAND_FALL_VZ)
		fall_vz = 0.0
	else:
		fall_vz = 0.0
	land = maxf(0.0, land - dt / C.FIGURE_LAND_S)
	# 2단 점프 공중제비 (airJump 이벤트가 flip = 0)
	if flip >= 0.0:
		flip += dt
		if stunned or flip >= C.FIGURE_FLIP_S:
			flip = -1.0
	# 몸 기준 가속도
	if pvxs != null and dt > 0.0:
		var ax: float = (vxs - pvxs) / dt
		var ay: float = (vys - pvys) / dt
		acc_f = cos(yaw) * ax + sin(yaw) * ay
		acc_s = -sin(yaw) * ax + cos(yaw) * ay
	pvxs = vxs
	pvys = vys
	# 공중 대시: 공중에서 남은 공중 대시가 줄면 슈퍼맨 자세 잠깐
	var ad = p.get("airDashes")
	if air and ad != null and air_dashes_prev != null and float(ad) < float(air_dashes_prev):
		air_dash_t = C.FIGURE_AIR_DASH.s
	air_dashes_prev = ad
	air_dash_t = 0.0 if stunned else maxf(0.0, air_dash_t - dt)
	var busy := walking or air or stunned or act != null or float(p.get("emote", -1)) >= 0
	idle_t = 0.0 if busy else idle_t + dt
	t += dt
	# 판 끝 승자: 승리 포즈 시간
	var won := _is_winner(p)
	vic_t = (vic_t + dt if vic_t >= 0.0 else 0.0) if won else -1.0
	emote_t = emote_t + dt if float(p.get("emote", -1)) >= 0 else 0.0
	set_meta("air", air)
	set_meta("walking", walking)


func _is_winner(p: Dictionary) -> bool:
	var store = _store()
	if store == null:
		return false
	var st: Dictionary = store.state
	if st.get("phase") != "over" or st.get("practice", false):
		return false
	var rd: Dictionary = st.get("round", {})
	for w in rd.get("winnerIds", []):
		if int(w) == pid:
			return true
	var wt = rd.get("winnerTeam")
	return wt != null and p.get("team") == wt


# 발밑 (네 모서리) 바로 아래가 바닥·블록인가 (render.js feetOnGround)
func _feet_on_ground(s: Vector3) -> bool:
	if s.z <= 0.03 and s.z > -0.3:
		return true
	var store = _store()
	if store == null:
		return true
	var f: Dictionary = store.state.get("field", {})
	var grid: PackedByteArray = store.grid
	if f.is_empty():
		return true
	var w := int(f.w)
	var dd := int(f.d)
	var hh := int(f.get("h", C.GRID_H))
	var h: float = C.PLAYER_HALF
	for c in [[-h, -h], [h, -h], [-h, h], [h, h]]:
		var gx := floori(s.x + c[0])
		var gy := floori(s.y + c[1])
		var gz := floori(s.z - 0.08)
		if gx < 0 or gy < 0 or gx >= w or gy >= dd or gz >= hh:
			continue
		if gz < 0:
			return true
		var i := (gz * dd + gy) * w + gx
		if i < grid.size() and grid[i] != 0:
			return true
	return false


# figureAnim 에 넘길 상태 (render.js figureAnim(fig, {...}))
func _anim_state(p: Dictionary, now_ms: float) -> Dictionary:
	return {
		"air": get_meta("air", false), "walking": get_meta("walking", false), "hs": hs, "walk": walk, "vz": vz, "t": t,
		"stunned": p.get("stunned", false), "emote": int(p.get("emote", -1)), "emoteT": emote_t, "victory": vic_t,
		"hit": _hit_for(p, now_ms), "act": _act_for(now_ms), "accF": acc_f, "accS": acc_s,
		"tumble": tumble_amt, "recover": recover * recover_pow, "land": land * land_pow,
		"flip": flip / C.FIGURE_FLIP_S if flip >= 0.0 else -1.0, "idle": idle_t, "airDash": air_dash_t / C.FIGURE_AIR_DASH.s,
		"form": str(p.get("bard", {}).get("form", "")) if p.get("bard") is Dictionary else "",
		"loaded": p.get("loaded", false) == true, "ammo": float(p.get("cannon", {}).get("ammo", 3)) if p.get("cannon") is Dictionary else 3.0,
	}


# ---------- 몸 자세 (figure.js figureAnim) ----------
func _figure_anim(st: Dictionary, dt: float) -> void:
	var T := Motion.rest_pose(d)
	var tt: float = st.t
	var hit_ = st.hit
	if hit_ != null and hit_.id != sway_id:
		sway_id = hit_.id
		sw.x = hit_.dx * C.FIGURE_HIT_LEAN * hit_.pow
		sw.y = hit_.dy * C.FIGURE_HIT_LEAN * hit_.pow
		sw.vx = hit_.dx * C.FIGURE_HIT_KICK * hit_.pow
		sw.vy = hit_.dy * C.FIGURE_HIT_KICK * hit_.pow
	var frozen: bool = hit_ != null and hit_.age < hit_.stop
	if not frozen:
		Motion.step_sway(sw, dt)
	var actv = st.act
	if st.walking:
		Pose.gait_pose(T, d, st.hs, st.walk, Pose.gait_of(char_id))
	else:
		T.waistPitch = d.hunch + sin(tt * 2.0) * 0.02 # 숨쉬기
		for i in 2:
			T.shOut[i] += sin(tt * 1.7 + i) * 0.03
		if char_id == "hunter" and actv == null:
			# 사냥꾼 킁킁: 몇 초마다 고개를 내밀고 빠르게 까딱
			var ph := fmod(tt, C.FIGURE_SNIFF_EVERY)
			var on := sin(PI * ph / C.FIGURE_SNIFF_LEN) if ph < C.FIGURE_SNIFF_LEN else 0.0
			T.neckPitch += on * (0.25 + sin(tt * 38.0) * 0.12)
			T.waistPitch += on * 0.12
	if st.air:
		Pose.air_pose(T, d, st.vz, tt, actv != null and actv.phase != "broken")
	if st.airDash > 0.0 and not st.stunned:
		Pose.overlay_t(T, Pose.SUPERMAN, minf(1.0, st.airDash * 4.0))
	if not st.stunned and not (st.flip >= 0.0):
		Pose.acc_lean(T, st.accF, st.accS)
	if st.flip >= 0.0:
		var tuck := minf(1.0, minf(st.flip * 5.0, (1.0 - st.flip) * 3.0))
		T.thFwd = [1.9 * tuck, 1.9 * tuck]
		T.knee = [2.2 * tuck, 2.2 * tuck]
		T.shFwd = [1.2 * tuck, 1.2 * tuck]
		T.shOut = [0.3, 0.3]
		T.elbow = [1.6 * tuck, 1.6 * tuck]
		T.waistPitch = 0.5 * tuck
		T.neckPitch = 0.3 * tuck
	if st.stunned:
		# 맞고 날아가는 중: 팔다리를 크게 벌리고 버둥
		T.shOut = [1.5 + sin(tt * 20.0) * 0.3, 1.5 + cos(tt * 18.0) * 0.3]
		T.shFwd = [sin(tt * 16.0) * 0.5, cos(tt * 15.0) * 0.5]
		T.thOut = [0.35, 0.35]
		T.thFwd = [sin(tt * 17.0) * 0.5, -sin(tt * 17.0) * 0.5]
		T.knee = [0.5, 0.5]
		T.neckPitch = -0.3
		T.waistRoll = 0.0
		T.waistSide = 0.0
		if st.tumble > 0.0:
			var c: float = st.tumble
			for i in 2:
				T.thFwd[i] = T.thFwd[i] * (1.0 - c) + 1.6 * c
				T.knee[i] = T.knee[i] * (1.0 - c) + 2.0 * c
				T.shFwd[i] = T.shFwd[i] * (1.0 - c) + 1.0 * c
				T.shOut[i] = T.shOut[i] * (1.0 - c) + 0.6 * c
			T.elbow = [1.2, 1.2]
			T.waistPitch = 0.6 * c
			T.neckPitch = 0.4 * c
	elif st.recover > 0.0:
		# 경직이 풀림: 쪼그려 앉았다가 손으로 균형 잡으며 일어남
		var r: float = st.recover * st.recover * (3.0 - 2.0 * st.recover)
		for i in 2:
			T.thFwd[i] += 1.1 * r
			T.knee[i] += 1.9 * r
			T.shFwd[i] += 0.7 * r
			T.shOut[i] += 0.6 * r
			T.elbow[i] += 0.3 * r
		T.waistPitch += 0.55 * r
		T.neckPitch -= 0.45 * r
	if st.land > 0.0 and not st.air and not st.stunned:
		# 착지: 무릎을 굽혀 받음
		var l: float = st.land
		for i in 2:
			T.thFwd[i] += 0.6 * C.FIGURE_LAND_KNEE * l
			T.knee[i] += 1.1 * C.FIGURE_LAND_KNEE * l
			T.shOut[i] += 0.5 * l
		T.waistPitch += 0.3 * C.FIGURE_LAND_KNEE * l
		T.neckPitch -= 0.2 * C.FIGURE_LAND_KNEE * l
	_costume_pose(T, st, actv, tt)
	if st.idle > C.FIGURE_IDLE_AFTER and not st.walking and not st.air and not st.stunned and actv == null and st.emote < 0 and not (st.victory >= 0.0):
		# 평소 버릇: 가만히 있으면 몇 초마다 캐릭터별 짧은 동작
		var hb = C.FIGURE_IDLE.get(char_id)
		if hb != null:
			var ph := fmod(st.idle - C.FIGURE_IDLE_AFTER, hb.every)
			if ph < hb.len:
				Pose.idle_pose(T, hb.kind, ph / hb.len, ph, st.form)
	if st.emote == 1:
		T.shOut = [2.3 + sin(tt * 12.0) * 0.5, 2.3 - sin(tt * 12.0) * 0.5] # 춤: 양팔을 번갈아 위로 펌프
		T.elbow = [0.6, 0.6]
		T.thFwd = [0.2 * sin(tt * 12.0), -0.2 * sin(tt * 12.0)]
	elif st.emote == 0:
		T.shOut[0] = 2.7 # 손 흔들기
		T.elbow[0] = 0.5 + sin(st.emoteT * 12.0) * 0.5
	elif st.emote == 2:
		T.shFwd = [0.5, 0.5] # 웃기: 배를 잡고 들썩
		T.shOut = [0.1, 0.1]
		T.elbow = [1.7, 1.7]
		T.waistPitch = -0.25 + sin(st.emoteT * 22.0) * 0.18
		T.neckPitch = -0.3
	elif st.emote == 3:
		T.shFwd[1] = 1.4 # 도발: 왼팔을 앞으로 뻗어 손짓
		T.shOut[1] = 0.1
		T.elbow[1] = 0.6 + sin(st.emoteT * 10.0) * 0.6
		T.waistPitch = 0.1 + sin(st.emoteT * 8.0) * 0.12
	if frozen:
		Motion.hit_pose(T, hit_.dx, hit_.dy, hit_.pow)
	# 따라가기: 관절마다 스프링 (히트스톱은 바로 그 자세)
	if frozen:
		for key in T:
			P[key] = T[key].duplicate() if T[key] is Array else T[key]
			V[key] = [0.0, 0.0] if T[key] is Array else 0.0
	else:
		var lim: float = C.FIGURE_LAG_ACC_MAX
		var f := clampf(st.accF, -lim, lim) * dt
		var sd := clampf(st.accS, -lim, lim) * dt
		for i in 2:
			V.shFwd[i] -= f * C.FIGURE_LAG_ARM
			V.shOut[i] += (-sd if i else sd) * C.FIGURE_LAG_ARM
		V.neckPitch -= f * C.FIGURE_LAG_NECK
		Motion.spring_pose(P, V, T, dt, C.FIGURE_SPRING_FLIP if st.flip >= 0.0 else 1.0)
	# 공격 동작: 따라가기를 건너뛰고 바로 덮어씀
	var spin := 0.0
	var a = actv if (actv != null and (actv.phase == "broken" or (not frozen and (not st.stunned or Moves.MOVES[actv.move].get("stunOk", false))))) else null
	if a != null:
		var m: Dictionary = Moves.MOVES.get(a.move, Moves.MOVES.punch)
		match a.phase:
			"wind":
				Motion.overlay(P, T, m.get("W"), Motion.ease01(a.u * 1.4), V)
			"strike":
				Motion.overlay(P, T, m.get("W"), 1.0 - a.u, V)
				Motion.overlay(P, T, m.get("S"), Motion.ease01(a.u * 2.0), V)
			"rec":
				Motion.overlay(P, T, m.get("S"), 1.0 - Motion.ease01(a.u * 2.2 if a.air else a.u), V)
				if m.get("pull", false):
					Motion.overlay(P, T, {"shFwd": [null, 0.4], "elbow": [null, 2.0], "waistPitch": -0.3}, sin(PI * minf(1.0, a.u * 1.5)), V)
			"broken":
				if sw.get("broken_id") != a.id:
					sw.broken_id = a.id
					sw.vx -= C.FIGURE_HIT_KICK * 0.3
				Motion.overlay(P, T, Moves.BROKEN, 1.0 if a.u < 0.25 else 1.0 - Motion.ease01((a.u - 0.25) / 0.75), V)
		if m.has("spin") and (a.phase == "strike" or a.phase == "rec"):
			spin = m.spin * Motion.ease01(a.u * 0.2 if a.phase == "strike" else 0.2 + a.u * 0.8)
		if m.has("turn") and (a.phase == "strike" or a.phase == "rec"):
			spin = m.turn * (Motion.ease01(a.u) if a.phase == "strike" else 1.0 - Motion.ease01((a.u - 0.6) / 0.4))
	# 도발·승리 포즈 (figure.js POSES)
	if a == null and not frozen and not st.stunned:
		var who := "metal" if (char_id == "bard" and st.form == "metal") else char_id
		if Moves.POSES.has(who):
			if st.victory >= 0.0:
				Motion.pose_at(P, T, V, who, "victory", st.victory, INF)
			elif st.emote == C.EMOTE_CHAR:
				Motion.pose_at(P, T, V, who, "taunt", st.emoteT, C.EMOTE_MS / 1000.0)
	# 도는 동작이 끝나면 가장 가까운 한 바퀴 각으로
	if spin != 0.0:
		spin_s = spin
	else:
		var to := roundf(spin_s / (PI * 2)) * PI * 2
		spin_s += (to - spin_s) * (1.0 - exp(-C.FIGURE_SETTLE * dt))
		if absf(to - spin_s) < 1e-3:
			spin_s = 0.0
	# 땅에 있으면 더 뻗은 다리의 발이 바닥에 닿게 엉덩이를 내림
	var drop := 0.0
	var floating: bool = a != null and Moves.MOVES.get(a.move, {}).get("float", false) and a.phase != "wind"
	if not st.air and st.flip < 0.0 and not (st.tumble > 0.0) and not floating:
		var reach := 0.0
		for i in 2:
			reach = maxf(reach, (d.thigh * cos(P.thFwd[i]) + d.shin * cos(P.thFwd[i] - P.knee[i])) * cos(P.thOut[i]))
		drop = maxf(0.0, d.thigh + d.shin - reach)
	if drop_s == null or frozen:
		drop_s = drop
	else:
		drop_s += (drop - drop_s) * (1.0 - exp(-C.FIGURE_DROP_FOLLOW * dt))
	twist_k += ((1.0 if (a != null and a.phase != "broken") else 0.0) - twist_k) * (1.0 - exp(-C.FIGURE_HIP_TWIST_FOLLOW * dt))
	_costume_parts(st, a, dt, tt)
	set_meta("pose_ok", _pose_ok())


func _pose_ok() -> bool:
	for k in P:
		var v = P[k]
		if v is Array:
			for x in v:
				if not is_finite(x):
					return false
		elif not is_finite(v):
			return false
	return is_finite(sw.x) and is_finite(sw.y)


# 자세 → 관절 회전 (figure.js figureAnim 끝부분) + 몸 전체 기울임·공중제비·구르기 (render.js rig)
func _apply(_dt: float) -> void:
	if not get_meta("pose_ok", true):
		P = Motion.rest_pose(d)
		V = Motion.zero_pose(P)
		sw = {"x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0}
	var lean := minf(1.0, hs / C.MOVE_SPEED) * C.ANIM_LEAN
	var flip_angle := 0.0
	if flip >= 0.0:
		var f := flip / C.FIGURE_FLIP_S
		flip_angle = PI * 2 * f * f * (3.0 - 2.0 * f)
	var dash: float = C.FIGURE_AIR_DASH.tilt * minf(1.0, (air_dash_t / C.FIGURE_AIR_DASH.s) * 4.0)
	rig.rotation = Vector3(0, lean + flip_angle + dash, 0)
	if tumble_spin != 0.0:
		rig.basis = Basis(tumble_axis, tumble_spin) * rig.basis
	var drop: float = drop_s if drop_s != null else 0.0
	hips.position.z = d.foot + d.shin + d.thigh + P.hipsZ - drop
	var hip_twist: float = P.waistRoll * C.FIGURE_HIP_TWIST * twist_k
	hips.rotation = Vector3(0, 0, spin_s + hip_twist)
	waist.rotation = Vector3(-(P.waistSide + sw.y), P.waistPitch + sw.x, P.waistRoll - hip_twist)
	neck.rotation = Vector3(sw.y * 0.5, P.neckPitch - sw.x * 0.5, 0)
	for i in 2:
		var side := 1.0 if i else -1.0 # 0 = 오른쪽(-y)
		shoulders[i].rotation = Vector3(side * P.shOut[i], -P.shFwd[i], -side * P.shTwist[i])
		elbows[i].rotation = Vector3(0, -P.elbow[i], 0)
		thighs[i].rotation = Vector3(side * P.thOut[i], -P.thFwd[i], 0)
		knees[i].rotation = Vector3(0, P.knee[i], 0)


# ---------- 옷·무기가 바꾸는 자세 (figure.js figureAnim 의 fig.axe·forms·cannon·gun 부분) ----------
func _costume_pose(T: Dictionary, st: Dictionary, actv, tt: float) -> void:
	if refs.has("axe") and not st.stunned and actv == null and st.emote < 0 and not st.air:
		# 도끼를 어깨에 걸침: 오른팔꿈치를 접어 자루가 어깨 위로 넘어감
		T.shFwd[0] = 0.35
		T.shOut[0] = 0.55
		T.elbow[0] = 1.95
	if refs.has("formParts") and not st.stunned and actv == null and st.emote < 0 and not st.air:
		# 바드: 악기를 가슴 앞에 들고 (왼손 목, 오른손 줄). 메탈은 대기 중 헤드뱅잉
		T.shFwd = [0.45, 0.75]
		T.shOut = [0.3, 0.05]
		T.elbow = [1.6, 1.45]
		if st.form == "metal" and not st.walking:
			var bang := maxf(0.0, sin(tt * C.BARD_HEADBANG_HZ * PI * 2.0))
			T.neckPitch += bang * 0.55 - 0.1
			T.waistPitch += bang * 0.12
			T.elbow[0] += sin(tt * C.BARD_HEADBANG_HZ * PI * 4.0) * 0.25 # 줄 긁기
	if refs.has("cannon") and not st.stunned and st.emote < 0:
		# 대포를 어깨에 멘 자세: 오른손은 대포를 받치고, 왼손은 허리에 척 (걸으면 왼팔만 흔들림)
		T.shFwd[0] = 0.25
		T.shOut[0] = 1.75
		T.elbow[0] = 1.7
		if not st.walking:
			T.shFwd[1] = -0.35
			T.shOut[1] = 0.75
			T.elbow[1] = 2.0
	if refs.has("gun") and st.loaded and not st.stunned and not st.air and st.emote < 0:
		# 장전된 권총을 든 오른손: 팔꿈치를 굽혀 총을 앞으로 (걸을 땐 흔들림 반만)
		T.elbow[0] = 1.5
		T.shFwd[0] = 0.2 + T.shFwd[0] * 0.3 if st.walking else 0.25
		T.shOut[0] = 0.15


# 옷·무기 보이기·흔들림 (figure.js figureAnim 끝부분: 총·활·방패 손에, 천 자락, 뿔, 바드 폼, 남은 포탄)
func _costume_parts(st: Dictionary, a, dt: float, tt: float) -> void:
	var move: Dictionary = Moves.MOVES.get(a.move, {}) if a != null else {}
	var acting: bool = a != null and a.phase != "broken"
	if refs.has("gun") and refs.gun is Dictionary:
		var in_hand: bool = (acting and move.get("gun", false)) or st.loaded
		_vis(refs.gun.get("inHand"), in_hand)
		_vis(refs.gun.get("holster"), not in_hand)
		_vis(refs.gun.get("spark"), st.loaded and int(Time.get_ticks_msec() / 90.0) % 3 != 0)
	if refs.has("bow") and refs.bow is Dictionary:
		var bow_in: bool = acting and move.get("bow", false)
		_vis(refs.bow.get("inHand"), bow_in)
		_vis(refs.bow.get("back"), not bow_in)
	if refs.has("shields") and refs.shields is Dictionary:
		var front: bool = acting and move.get("shield", false)
		_vis(refs.shields.get("front"), front)
		_vis(refs.shields.get("back"), not front)
	if refs.has("balls") and refs.balls is Array:
		for i in refs.balls.size():
			_vis(refs.balls[i], i < st.ammo)
	if refs.has("formParts"):
		var f: String = "metal" if st.form == "metal" else "bard"
		if f != form:
			form = f
			for k in refs.formParts:
				for r in refs.formParts[k]:
					_vis(r, k == f)
			var tm = refs.get("torsoMat", {}).get(f)
			if tm != null and torso is MeshInstance3D:
				(torso as MeshInstance3D).material_override = mats[int(tm)]
	# 천 자락: 빨리 움직이거나 날아가면 뒤로 날리고 살랑임. 멈추면 앞으로 한 번 넘어갔다 내려옴 (스프링)
	var flaps: Array = refs.get("flaps", [])
	if not flaps.is_empty() and dt > 0.0:
		var sp: float = 1.0 if st.stunned else (minf(1.0, st.hs / C.MOVE_SPEED) if (st.walking or st.air) else 0.0)
		var fw: float = C.FIGURE_FLAP_SPRING.w
		var steps := maxi(1, ceili(dt / C.FIGURE_SPRING_STEP))
		for j in steps:
			flap_s.v += (fw * fw * (sp - flap_s.x) - 2.0 * C.FIGURE_FLAP_SPRING.damp * fw * flap_s.v) * (dt / steps)
			flap_s.x += flap_s.v * (dt / steps)
		for i in flaps.size():
			var fl: Dictionary = flaps[i]
			var o := _n(fl.get("obj"))
			if o != null:
				o.rotation.y = float(fl.base) + flap_s.x * float(fl.lift) + sin(tt * 9.0 + i * 1.7) * float(fl.flutter) * (0.3 + maxf(0.0, flap_s.x))
	# 광전사 뿔: 마디마다 같은 각으로 위로 꺾여 매끈한 C 자
	if refs.has("horns") and refs.horns is Array:
		var bend: float = C.FIGURE_HORN_CURL / (C.FIGURE_HORN_SEGS - 1.0)
		for h in refs.horns:
			var segs: Array = h.get("segs", [])
			for k in segs.size():
				var sn := _n(segs[k])
				if sn != null:
					sn.rotation.x = float(h.side) * (0.15 if k == 0 else bend)


func _vis(r, on: bool) -> void:
	var n := _n(r)
	if n != null:
		n.visible = on


# ---------- 서버 이벤트 (main.js handleEvent → renderer 의 몸 부분) ----------
func on_event(e: Dictionary) -> void:
	if pid < 0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var who = e.get("who")
	var mine: bool = who != null and int(who) == pid
	var target = e.get("target")
	var hit_me: bool = target != null and int(target) == pid
	var ty: String = str(e.get("type", ""))
	match ty:
		"attack":
			if mine:
				_attack_start(e, now)
		"swing":
			if mine:
				if act != null and act.struck == null and act.broken == null:
					act.struck = now
				else:
					act = _new_act("punch", now, 0.0, now, 0.3)
		"interrupt":
			if mine:
				if act == null:
					act = _new_act("punch", now, 0.0, null, 0.3)
				seq += 1
				act.id = seq
				act.broken = now
		"combo":
			if hit_me and e.get("finish", false):
				finish_at = now
		"counter":
			if hit_me:
				counter_at = now
		"hit":
			if hit_me and e.get("ok", false):
				var heavy: bool = e.get("crit", false) or e.get("kind") == "blast" or e.get("kind") == "bigbomb"
				_hit_react(_dir_from(e.get("by")), heavy, e.get("crit", false), str(e.get("kind", "")), now)
		"hook":
			if hit_me:
				var dv = _dir_from(who)
				_hit_react(-dv if dv != null else null, false, false, "", now)
				_skill_move("hookDragged", 0.0, now)
			elif mine and e.get("block") != null and target == null:
				_skill_move("hookZip", 0.0, now)
		"airJump":
			if mine:
				flip = 0.0
		"form":
			if mine:
				_skill_move("bardRiff" if e.get("form") == "metal" else "bardHeal", 0.0, now)
		_:
			if mine and SKILL_START.has(ty):
				var s: Array = SKILL_START[ty]
				_skill_move(s[0], float(e.get("ms", 0.0)) if s[1] else 0.0, now)
			elif mine and SKILL_STRIKE.has(ty):
				var s: Array = SKILL_STRIKE[ty]
				if act != null and act.move == s[0] and act.broken == null:
					if act.struck == null:
						act.struck = now
				elif not s[1]:
					_skill_move(s[0], 0.0, now)


# 때린 사람 → 나 방향 (게임, 단위). 모르면 null
func _dir_from(by):
	if by == null:
		return null
	var store = _store()
	if store == null:
		return null
	var me: Dictionary = store.player(pid)
	var a: Dictionary = store.player(int(by))
	if me.is_empty() or a.is_empty():
		return null
	var v := Vector2(float(me.x) - float(a.x), float(me.y) - float(a.y))
	return v.normalized() if v.length() > 0.0 else Vector2(1, 0)


func _new_act(move: String, now: float, windup: float, struck, rec: float, air := false) -> Dictionary:
	seq += 1
	return {"id": seq, "move": move, "t0": now, "windup": windup, "struck": struck, "rec": rec, "broken": null, "air": air}


# attack 이벤트: 준비 시작. 동작 이름은 평타 표의 name (갈고리 주먹만 'hook:주먹'), 회복 시간은 평타 표의 rec (render.js attackStart)
func _attack_start(e: Dictionary, now: float) -> void:
	var ch := str(e.get("char", ""))
	var air: bool = e.get("air", false)
	var def = null
	var set_ = C.BASIC_ATTACKS.get(ch)
	var n := int(e.get("n", 1))
	if set_ != null:
		var list: Array = set_.air if air else set_.chain
		if n >= 1 and n <= list.size():
			def = list[n - 1]
	var nm := str(e.get("name", ""))
	var move := "punch"
	if ch == "hook" and nm == "주먹":
		move = "hook:주먹"
	elif air and nm == "표창":
		move = "공중 표창"
	elif Moves.MOVES.has(nm):
		move = nm
	var w = e.get("windup", 0.0)
	var windup: float = float(w) / 1000.0 if (w != null and float(w) >= 0.0) else 0.0
	var rec := 0.3
	if def != null and def.get("rec") != null and float(def.rec) >= 0.0:
		rec = float(def.rec) / 1000.0
	act = _new_act(move, now, windup, null, rec, air)


func _skill_move(move: String, windup_ms: float, now: float) -> void:
	var rec: float = Moves.MOVES.get(move, {}).get("rec", 0.4)
	act = _new_act(move, now, windup_ms / 1000.0, null if windup_ms > 0.0 else now, rec)


# 맞은 순간 (render.js hitReact). dir = 밀린 방향 (게임 Vector2, 없으면 null)
func _hit_react(dir, heavy: bool, crit: bool, kind: String, now: float) -> void:
	var finish := now - finish_at < 0.2
	var counter := now - counter_at < 0.2
	var base: float = C.FIGURE_HIT_FINISH if finish else (C.FIGURE_HIT_HEAVY if (heavy or crit or kind in HEAVY_HITS) else 1.0)
	var power := minf(3.0, base * (C.FIGURE_HIT_COUNTER if counter else 1.0))
	var stop := C.HITSTOP_MS * (C.CRIT_HITSTOP_MULT if crit else 1.0) / 1000.0
	seq += 1
	hit = {"id": seq, "t0": now, "stop": stop, "dir": dir, "pow": power}
	if act != null and act.broken == null:
		act = null


# figureAnim 에 넘길 맞은 것 (몸 기준 밀린 방향). 오래되면 버림
func _hit_for(p: Dictionary, _now_ms: float):
	if hit == null:
		return null
	var now := Time.get_ticks_msec() / 1000.0
	var age: float = now - hit.t0
	if age > 2.0:
		hit = null
		return null
	var dx := -1.0
	var dy := 0.0
	if hit.dir != null:
		var yaw: float = p.get("yaw", 0.0)
		dx = cos(yaw) * hit.dir.x + sin(yaw) * hit.dir.y
		dy = -sin(yaw) * hit.dir.x + cos(yaw) * hit.dir.y
	return {"id": hit.id, "age": age, "stop": hit.stop, "dx": dx, "dy": dy, "pow": hit.pow}


# figureAnim 에 넘길 지금 공격 단계 (render.js actFor). 끝났으면 지움
func _act_for(_now_ms: float):
	if act == null:
		return null
	var now := Time.get_ticks_msec() / 1000.0
	if act.rec <= 0.0 or now - act.t0 > C.FIGURE_ACT_MAX_S or not Moves.MOVES.has(act.move):
		act = null
		return null
	if act.broken != null:
		var ub: float = (now - act.broken) / C.FIGURE_BROKEN_S
		if ub >= 1.0:
			act = null
			return null
		return {"id": act.id, "move": act.move, "phase": "broken", "u": ub, "air": act.air}
	if act.struck == null:
		var age: float = now - act.t0
		if age > act.windup + C.FIGURE_SWING_WAIT_S:
			act = null
			return null
		return {"id": act.id, "move": act.move, "phase": "wind", "u": minf(1.0, age / act.windup) if act.windup > 0.0 else 1.0, "air": act.air}
	var s: float = now - act.struck
	if s < C.FIGURE_STRIKE_S:
		return {"id": act.id, "move": act.move, "phase": "strike", "u": s / C.FIGURE_STRIKE_S, "air": act.air}
	var r: float = (s - C.FIGURE_STRIKE_S) / act.rec
	if r >= 1.0:
		act = null
		return null
	return {"id": act.id, "move": act.move, "phase": "rec", "u": r, "air": act.air}

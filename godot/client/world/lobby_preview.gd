# 대기실 지형 미리보기 (render.js lobbyPreview·previewPick·previewSize·previewTop + shared/title.js lobbyTheme·lobbyFieldSize):
# 대기실에서 고른 맵의 시작 지형을 지금 인원으로 판을 시작하면 될 크기로 미리 깖. 사람은 화면만 큰 판 가운데·그 칸 위로.
# 지형 모양은 shared/maps.js mapColumns 를 판 크기마다 미리 뽑은 world/map_columns.json (tools/gen-map-columns.mjs). 정답 자료 tests/fixtures/lobby.json
extends RefCounted

const C := preload("res://core/config.gd")
const Cells := preload("res://world/cells.gd")
const COLUMNS := "res://world/map_columns.json"

static var _cols = null


# 대기실 배경 테마 (shared/title.js lobbyTheme): 대기실·연습 아님·맵 있음. 무작위면 fallback (이번 창 메뉴 테마)
static func lobby_theme(st: Dictionary, fallback = null):
	if st.is_empty() or str(st.get("phase", "")) != "lobby" or st.get("practice") != null or st.get("map") == null:
		return null
	var pick = st.map.get("choice")
	if pick == "random" and fallback != null and C.TITLE_THEMES.has(fallback):
		return fallback
	var m = pick if pick != null and pick != "random" else st.map.get("id")
	var id = C.WORLD_MAP_THEME.get(m)
	return id if id != null and C.TITLE_THEMES.has(id) else null


# 판 크기 표 (FIELD_SIZES): n 이하 가장 큰 칸, 없으면 가장 작은 칸
static func field_size_for(n: int) -> int:
	var keys := []
	for k in C.FIELD_SIZES:
		keys.append(int(k))
	keys.sort()
	var best: int = keys[0]
	for k in keys:
		if k <= n:
			best = k
	return int(C.FIELD_SIZES[str(best)])


# 지금 인원으로 판을 시작하면 될 크기 (관전 빼고, 블록 마스터는 마스터 빼고)
static func lobby_field_size(st: Dictionary) -> int:
	var n := 0
	for p in st.get("players", []):
		if not p.get("spectator", false):
			n += 1
	if str(st.get("mode", "")) == "master":
		n -= 1
	return field_size_for(n)


# 미리볼 맵 id (대기실·테마 있음·무작위 아님), 없으면 null
static func pick(st: Dictionary, fallback = null):
	if lobby_theme(st, fallback) == null:
		return null
	var c = st.map.get("choice")
	return c if c != null and c != "random" and C.MAPS.has(c) else null


static func columns(map_id: String, n: int) -> Array:
	if _cols == null:
		_cols = JSON.parse_string(FileAccess.get_file_as_string(COLUMNS))
	return _cols.get(map_id, {}).get(str(n), [])


# 미리보기 격자·기둥 높이 (render.js lobbyPreview): {grid, top, w, d, h}
static func build(map_id: String, n: int, h: int) -> Dictionary:
	var grid := PackedByteArray()
	grid.resize(n * n * h)
	var top := PackedFloat32Array()
	top.resize(n * n)
	for c in columns(map_id, n):
		var x := int(c[0])
		var y := int(c[1])
		var ch := int(c[2])
		if x < 0 or y < 0 or x >= n or y >= n:
			continue
		for z in mini(ch, h):
			grid[(z * n + y) * n + x] = Cells.TERRAIN
		top[y * n + x] = maxf(top[y * n + x], ch)
	return {"grid": grid, "top": top, "w": n, "d": n, "h": h}


# 미리보기 지형 높이: 몸 둘레 네 모서리 칸 중 가장 높은 윗면 (render.js previewTop)
static func top_at(P: Dictionary, x: float, y: float) -> float:
	var hh: float = C.PLAYER_HALF
	var t := 0.0
	for s in [[-hh, -hh], [hh, -hh], [-hh, hh], [hh, hh]]:
		var gx := floori(x + s[0])
		var gy := floori(y + s[1])
		if gx >= 0 and gy >= 0 and gx < P.w and gy < P.d:
			t = maxf(t, P.top[gy * P.w + gx])
	return t

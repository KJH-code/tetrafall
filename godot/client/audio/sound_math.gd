# 소리 순수 계산 (client/sound.js bus·falloff, hit-tier.js, music.js 분위기, shared/title.js lobbyTheme, bblock-look bigTicks).
# 노드 없음 → tests/test_audio.gd 가 JS 와 같은 값인지 봄
extends RefCounted

const C := preload("res://core/config.gd")


# 거리(칸)에 따라 작아지는 크기 (dist null = 1)
static func falloff(dist) -> float:
	if dist == null:
		return 1.0
	return maxf(0.2, 1.0 - float(dist) / C.SFX_HEAR_RANGE)


# 소리 하나의 크기·좌우 (sound.js bus): pos (게임 좌표 Vector3) 가 있고 내 소리(dist 0)가 아니면 내 귀(listener: Vector4 x,y,z,yaw) 기준
# 돌려줌 Vector2(크기, 좌우 -1~1, 오른쪽 +)
static func listen(dist, pos, listener) -> Vector2:
	var d = dist
	var pan := 0.0
	if pos != null and listener != null and not (dist != null and float(dist) == 0.0):
		var L: Vector4 = listener
		var dx: float = pos.x - L.x
		var dy: float = pos.y - L.y
		d = sqrt(dx * dx + dy * dy + (pos.z - L.z) * (pos.z - L.z))
		var len := sqrt(dx * dx + dy * dy)
		if len > 0.3:
			pan = clampf((dx * sin(L.w) - dy * cos(L.w)) / len * C.SFX_PAN, -1.0, 1.0)
	return Vector2(falloff(d), pan)


# 타격 소리 세기 (hit-tier.js): crit > heavy (마무리·묵직한 kind) > light (표창·투사체) > medium
static func hit_tier(e: Dictionary) -> String:
	if e.get("crit", false):
		return "crit"
	if e.get("finish", false) or C.SFX_HEAVY_KINDS.has(e.get("kind", "")):
		return "heavy"
	if e.get("star", false) or C.SFX_LIGHT_KINDS.has(e.get("kind", "")):
		return "light"
	return "medium"


static func hit_step(e: Dictionary) -> int:
	var n = e.get("n")
	if n == null or float(n) == 0:
		n = e.get("streak")
	if n == null or float(n) == 0:
		n = 1
	return mini(C.SFX_HIT_COMBO.size(), maxi(1, int(n)))


# 구운 타격 소리 이름 (bake-audio: hit.<무기>.<1|2|3|heavy|crit>), 크기 배율 (약타 SFX_HIT_LIGHT)
static func hit_key(chr, form, tier: String, step: int) -> String:
	var w := "none"
	if chr != null and C.SFX_WEAPONS.has(chr):
		w = "bardMetal" if chr == "bard" and form == "metal" else str(chr)
	var t := tier if tier == "heavy" or tier == "crit" else str(step)
	return "hit.%s.%s" % [w, t]


static func hit_vol(tier: String) -> float:
	return C.SFX_HIT_LIGHT if tier == "light" else 1.0


# 메뉴·대기실 앰비언트 테마 (shared/title.js lobbyTheme): 대기실(연습 아님)이면 고른 맵 테마, 무작위면 fallback, 그 밖 null
static func lobby_theme(state: Dictionary, fallback = null):
	if state.is_empty() or state.get("phase") != "lobby" or state.get("practice") != null or not state.has("map"):
		return null
	var pick = state.map.get("choice")
	if pick == "random" and fallback != null and C.TITLE_THEMES.has(fallback):
		return fallback
	var m = pick if pick != null and pick != "random" else state.map.id
	var id = C.WORLD_MAP_THEME.get(m)
	return id if id != null and C.TITLE_THEMES.has(id) else null


# 앰비언트를 틀 테마 (music.js ambientTheme): 메뉴(state 없음) = 메뉴 테마, 대기실 = 방 맵 테마, 그 밖 = 없음 (곡)
static func ambient_theme(state: Dictionary, menu_theme):
	if state.is_empty():
		return menu_theme
	return lobby_theme(state, menu_theme)


# 곡 분위기 (main.js): 판 중 (카운트다운 포함) 위험이 차오르면 lava, 아니면 battle, 그 밖 calm
static func mood(state: Dictionary) -> String:
	if state.is_empty():
		return "calm"
	var ph = state.get("phase")
	if ph == "playing" or ph == "countdown":
		return "lava" if state.get("lava", {}).get("active", false) else "battle"
	return "calm"


# 구운 곡 이름 (music.js songKey + 긴장): lobby | <테마> | <테마>.tense
static func song_key(state: Dictionary, md: String) -> String:
	if md == "calm":
		return "lobby"
	var theme = null
	if not state.is_empty() and state.has("map"):
		theme = C.WORLD_MAP_THEME.get(state.map.id)
	var key: String = theme if theme != null and C.MUSIC_THEMES.has(theme) else C.MUSIC_THEME_DEFAULT
	return key + (".tense" if md == "lava" else "")


# 위험 액체 종류 (sound.js update): 맵 테마의 hazard.style, 없으면 fallback
static func hazard_style(state: Dictionary) -> String:
	if not state.is_empty() and state.has("map"):
		var theme = C.WORLD_MAP_THEME.get(state.map.id)
		if theme != null and C.WORLD_THEMES.has(theme):
			var hz = C.WORLD_THEMES[theme].get("hazard", {})
			if hz is Dictionary and hz.has("style"):
				return hz.style
	return C.SFX_HAZARD.fallback


# 위험 액체 지속음 크기 (sound.js hazard): 표면까지 높이 dist (null = 멀리)
static func hazard_level(style: String, live: bool, dist) -> float:
	if not live or dist == null:
		return 0.0
	var H: Dictionary = C.SFX_HAZARD
	var near := maxf(H.min, 1.0 - float(dist) / H.range)
	return float(H.vol.get(style, 0.3)) * near


# 건축가 대폭발 째깍 시각들 ms (shared/bblock-look.js bigTicks)
static func big_ticks(ms: float) -> Array:
	var out := []
	for f in C.BB_BIG_TICKS:
		out.append(roundi(f * ms))
	return out

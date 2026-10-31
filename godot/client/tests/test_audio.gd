# 소리 계산이 JS (client/sound.js·hit-tier.js·music.js·shared/title.js·bblock-look.js) 와 같은지 + 구운 녹음 목록이 빠짐없는지
extends RefCounted

const C := preload("res://core/config.gd")
const SM := preload("res://audio/sound_math.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func fx():
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio.json"))


func test_listen_matches_js() -> void:
	var bad := 0
	for row in fx().listens:
		var L = null
		if row[0] != null:
			L = Vector4(row[0].x, row[0].y, row[0].z, row[0].yaw)
		var pos = null
		if row[2] != null:
			pos = Vector3(row[2].x, row[2].y, row[2].z)
		var got := SM.listen(row[1], pos, L)
		if absf(got.x - row[3]) > 1e-6 or absf(got.y - row[4]) > 1e-5:
			if bad < 3:
				errors.append("거리·좌우 %s / JS (%s, %s) — %s" % [got, row[3], row[4], str(row)])
			bad += 1
	check(bad == 0, "다른 것 %d개" % bad)


func test_hit_tier_matches_js() -> void:
	for row in fx().hits:
		check(SM.hit_tier(row[0]) == row[1], "세기 %s / JS %s (%s)" % [SM.hit_tier(row[0]), row[1], str(row[0])])
		check(SM.hit_step(row[0]) == int(row[2]), "콤보 순번 %d / JS %d (%s)" % [SM.hit_step(row[0]), int(row[2]), str(row[0])])


func test_themes_match_js() -> void:
	for row in fx().themes:
		var st: Dictionary = row[0] if row[0] != null else {}
		for a in row[1]:
			check(SM.ambient_theme(st, a[0]) == a[1], "앰비언트 %s / JS %s (메뉴 %s, %s)" % [SM.ambient_theme(st, a[0]), a[1], a[0], str(st)])
			check(SM.lobby_theme(st, a[0]) == a[2], "대기실 테마 %s / JS %s" % [SM.lobby_theme(st, a[0]), a[2]])
		check(SM.mood(st) == row[2], "분위기 %s / JS %s" % [SM.mood(st), row[2]])
		check(SM.song_key(st, SM.mood(st)) == row[3], "곡 %s / JS %s" % [SM.song_key(st, SM.mood(st)), row[3]])
		check(SM.hazard_style(st) == row[4], "위험 종류 %s / JS %s" % [SM.hazard_style(st), row[4]])


func test_hazard_level_and_ticks_match_js() -> void:
	var f = fx()
	for row in f.levels:
		var got := SM.hazard_level(row[0], true, row[1])
		check(absf(got - row[2]) < 1e-9, "지속음 크기 %s / JS %s (%s)" % [got, row[2], str(row)])
	for row in f.ticks:
		check(SM.big_ticks(row[0]) == row[1].map(func(v): return int(v)), "째깍 %s / JS %s" % [str(SM.big_ticks(row[0])), str(row[1])])


# 이벤트가 찾는 녹음이 manifest 에 다 있음 (무기 9 × 세기 5, 위험 5종, 곡, 앰비언트)
func test_baked_manifest_complete() -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://audio/baked/manifest.json"))
	check(m != null, "manifest.json")
	var keys := ["tick", "go", "win", "lose", "danger", "land", "crush", "fall", "boom", "pickup", "latch", "tap", "tear", "shatter", "airJump", "crit", "hurt", "clear", "sizzle", "bbRise", "bbRise.big", "bbBreak", "bbTick", "bbTick.strong", "bbBlast", "bbBlast.strong", "smash", "smash.strong", "koCrush", "koCrush.strong", "final", "glideRing", "glideRing.strong", "strum", "strum.metal", "fire.none", "fire.hunter", "mark.1", "mark.2", "mark.3"]
	for w in ["none"] + C.SFX_WEAPONS.keys():
		keys.append("swing." + w)
		for t in ["1", "2", "3", "heavy", "crit"]:
			keys.append("hit.%s.%s" % [w, t])
	for t in ["1", "2", "3", "heavy", "crit"]:
		keys.append("hit.bardMetal." + t)
	for st in C.SFX_HAZARD.vol:
		keys.append("lavaDeath." + st)
		keys.append("rise." + st)
		check(m.hazard.has(st), "위험 지속음 " + st)
	for k in keys:
		check(m.sfx.has(k) and m.sfx[k].size() > 0, "녹음 없음: " + k)
	for theme in C.MUSIC_THEMES:
		check(m.music.has(theme), "곡 " + theme)
		if theme != "lobby":
			check(m.music.has(theme + ".tense"), "긴장 곡 " + theme)
	for theme in C.TITLE_THEMES:
		check(m.ambient.has(theme), "앰비언트 " + theme)
	for k in m.sfx:
		for rec in m.sfx[k]:
			check(ResourceLoader.exists("res://audio/baked/" + rec.file), "파일 " + rec.file)
	# 곡 고리 길이 = 16마디 (music.js 한 바퀴)
	for k in m.music:
		var song: Dictionary = C.MUSIC_THEMES[k.split(".")[0]]
		var bpm: float = song.bpm * (C.MUSIC_TENSION.bpm if k.ends_with(".tense") else 1.0)
		check(absf(m.music[k].length - 16 * 16 * 60 / bpm / 4) < 1e-6, "곡 길이 " + k)


# 타이틀 효과 녹음: 테마 7개마다 착지 3·빛 터짐·빠져나가기 (tools/bake-audio.cjs --only title)
func test_title_fx_baked() -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://audio/baked/manifest.json"))
	for th in C.TITLE_THEMES:
		var t = m.get("title", {}).get(th)
		check(t != null and t.land.size() == 3 and t.burst != null and t.exit != null, "타이틀 소리 %s" % th)
		if t != null:
			for rec in t.land + [t.burst, t.exit]:
				check(ResourceLoader.exists("res://audio/baked/" + rec.file), "파일 %s" % rec.file)

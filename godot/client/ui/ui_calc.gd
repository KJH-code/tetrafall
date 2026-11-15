# G4 화면 계산 (DOM 없는 순수 계산) — JS 원본을 그대로 옮김:
#   shared/hud-layout.js (아래 판 배치·대기실 판 폭·이름표 크기) · shared/kills-hud.js (킬 점수전 세기·위 띠·Tab 표·부활 초·HP)
#   shared/wipe.js (화면 전환 슬래시) · shared/char-select.js (큰 캐릭터 방향·도발·랜덤 뽑기) · shared/leave.js (나가기 한 번 더)
# tests/test_ui.gd 가 JS 정답 (tests/fixtures/ui.json, tools/fixtures.mjs) 으로 고정. 숫자는 전부 float (config 처럼)
extends RefCounted

const C := preload("res://core/config.gd")


# JS Math.round (반은 위로: -0.5 → -0, 0.5 → 1). 고도 round() 는 반을 0 에서 먼 쪽으로라 음수에서 다름
static func js_round(x: float) -> float:
	return floor(x + 0.5)


# ---------- hud-layout.js ----------

# 아래 플레이어 판 n 장을 폭 view_w 화면에 한 줄로: 판 폭·간격·작은 판 여부·글자 배율
static func card_layout(n: int, view_w: float) -> Dictionary:
	var count: int = max(1, n)
	var gap: float = C.HUD_CARD_GAP
	var room: float = view_w - 2.0 * C.HUD_CARD_MARGIN
	var w: float = floor((room - gap * (count - 1)) / count)
	w = min(C.HUD_CARD_W, w)
	if w < C.HUD_CARD_MIN_W:
		# 최소 폭으로 두고 간격을 줄여 한 줄에 넣음 (그래도 모자라면 간격 0)
		w = C.HUD_CARD_MIN_W
		gap = max(0.0, floor((room - w * count) / (count - 1))) if count > 1 else 0.0
	var compact: bool = count >= C.HUD_CARD_COMPACT_FROM or w < C.HUD_CARD_W
	return {"w": w, "gap": gap, "compact": compact, "scale": w / C.HUD_CARD_W, "total": w * count + gap * (count - 1)}


# 대기실 판은 오른쪽에 붙임: 폭 = 화면 폭 × frac 을 [min, max] 로. 반환 판 폭·왼쪽 끝
static func lobby_dock(view_w: float) -> Dictionary:
	var L: Dictionary = C.HUD_LOBBY_W
	var w: float = js_round(min(L.max, max(L.min, view_w * L.frac)))
	return {"w": w, "left": view_w - C.HUD_CARD_MARGIN - w}


# ---------- 고도 판 전용 (JS 에 없음 — 정답 자료 대신 tests/test_ui.gd 가 값으로 고정) ----------
const LOBBY_TOP := 84.0 # 대기실 판 위쪽 (위 점수 띠 아래)
const LOBBY_SCALE_MIN := 0.1 # 대기실 판 줄임 배율 아래 끝 (0 으로 나누기·뒤집힘 막기)
const RESULTS_TOP := 40.0 # 결과 판 위쪽 끝 (이보다 위로는 안 올라감)
const RESULTS_DROP := 22.0 # 결과 판: 세로 가운데에서 이만큼 아래
# 방 옵션 표시: [키 (스냅샷·공개 목록 같음), 글, 켜도 안 먹는 모드]. 블록 마스터 판은 하늘 계단 (Game.Round.cs StartRound sky)·돌발 이벤트 (Game.Events.cs RoundEventsRun) 가 안 돎
const ROOM_OPTS := [["skyStairs", "하늘 계단", ["master"]], ["hpMode", "체력전", []], ["roundEvents", "돌발 이벤트", ["master"]]]


const STATUS_POS := Vector2(16, 12) # 접속 상태 글 (연결 중·끊김 — ui.gd status) 자리: 메뉴·대기실·결과는 왼쪽 위
const STATUS_POS_GAME := Vector2(16, 64) # 판 HUD 가 보일 때: 왼쪽 위 판 시간 (hud.gd timer_label (14, 12) 글자 26) 아래 — 겹치지 않게


# 접속 상태 글 자리: in_game = 판 HUD 가 보임 (ui.gd hud.visible)
static func status_pos(in_game: bool) -> Vector2:
	return STATUS_POS_GAME if in_game else STATUS_POS


# 대기실 판 자리: 오른쪽 끝·위 (LOBBY_TOP) 에 붙임. content = 줄이기 전 판 크기 (폭은 lobby_dock 폭, 높이는 내용만큼).
# 자리 (폭 lobby_dock · 높이 LOBBY_TOP ~ 화면 아래 여백) 보다 크면 통째로 줄임 (960×540 등), 들어가면 배율 1.
# 반환 {scale 배율, x·y 왼쪽 위}
static func lobby_place(view: Vector2, content: Vector2) -> Dictionary:
	var room := Vector2(lobby_dock(view.x).w, view.y - LOBBY_TOP - C.HUD_CARD_MARGIN)
	var s := 1.0
	if content.x > 0.0 and content.y > 0.0:
		s = clampf(minf(room.x / content.x, room.y / content.y), LOBBY_SCALE_MIN, 1.0)
	return {"scale": s, "x": view.x - C.HUD_CARD_MARGIN - content.x * s, "y": LOBBY_TOP}


# 결과 판 자리 (results.gd _place): 오른쪽 끝에 붙이고 세로 가운데에서 RESULTS_DROP 만큼 아래 (위 점수 띠를 비킴).
# content = 줄이기 전 판 크기. 위 (RESULTS_TOP)·아래 (HUD_CARD_MARGIN) 여백 안으로 y 를 넣고, 그 사이 높이·화면 폭보다 크면 통째로 줄임
# (960×540 에 8명 + 칭호 3줄), 들어가면 배율 1. 줄인 판은 줄인 폭 (content.x × 배율) 으로 오른쪽에 붙임. 반환 {scale 배율, x·y 왼쪽 위}
static func results_place(view: Vector2, content: Vector2) -> Dictionary:
	var m: float = C.HUD_CARD_MARGIN
	var room := Vector2(view.x - m * 2.0, view.y - RESULTS_TOP - m)
	var s := 1.0
	if content.x > 0.0 and content.y > 0.0:
		s = clampf(minf(room.x / content.x, room.y / content.y), LOBBY_SCALE_MIN, 1.0)
	var h := content.y * s
	var y := minf((view.y - h) / 2.0 + RESULTS_DROP, view.y - m - h) # 아래로 넘치면 올리고
	return {"scale": s, "x": view.x - m - content.x * s, "y": maxf(y, RESULTS_TOP)} # 위는 점수 띠 아래까지만


# 켠 방 옵션을 한 줄 꼬리로: " · 하늘 계단 · 체력전 · 돌발 이벤트" (손님 대기실 줄·공개 방 목록). d = 스냅샷 또는 공개 목록 한 줄.
# 방 모드 (d.mode) 에서 안 먹는 옵션은 켜져 있어도 뺌 (블록 마스터 방의 하늘 계단·돌발 이벤트). 모드가 없으면 켠 것 전부
static func room_opts(d: Dictionary) -> String:
	var mode := str(d.get("mode", ""))
	var out := ""
	for o in ROOM_OPTS:
		if d.get(o[0], false) and not (o[2] as Array).has(mode):
			out += " · %s" % o[1]
	return out


# 블록 마스터 반격 알림 한 줄 (서버 이벤트 masterStall {who, ms}): 보는 사람 자리마다 다른 글. n초 = ms 올림.
# me = 내 플레이어 (없으면 {}), eater_name = 반격 아이템을 먹은 사람 이름. 마스터 편 (마스터·좀비) 은 자기 블록이 멈추는 것
static func master_stall_text(e: Dictionary, me: Dictionary, eater_name: String) -> String:
	var n := int(ceil(float(e.get("ms", 0.0)) / 1000.0))
	if me.get("master", false) or me.get("zombie", false):
		return "반격! 블록 %d초 멈춤" % n
	if not me.is_empty() and e.get("who") != null and me.get("id") != null and int(e.get("who")) == int(me.get("id")):
		return "반격! 마스터 블록 %d초 멈춤" % n
	return "%s 반격! 마스터 블록 %d초 멈춤" % [eater_name, n]


# 아이템을 주웠을 때 (서버 이벤트 pickup {who, item}) 내 화면에 띄울 알림 글 — 안 띄우면 "". names = 아이템 이름 표 (hud_extra.gd ITEM_KO).
# 내가 주운 것만. 반격 (counter) 은 바로 뒤 masterStall 이 알리므로 넘김 (줍는 사람에게 같은 내용 두 줄 안 뜨게). 표에 없는 아이템은 id 그대로
static func pickup_toast(e: Dictionary, me_id, names: Dictionary) -> String:
	var who = e.get("who")
	if me_id == null or not (who is float or who is int) or int(who) != int(me_id):
		return ""
	var item := str(e.get("item", ""))
	if item == "counter":
		return ""
	return "%s!" % str(names.get(item, item))


# 내가 만든 방의 welcome 을 받았을 때 보낼 방 메시지 (menu.gd _on_created): 재접속이면 (rejoined) 없음, 아니면 create_defaults
static func created_msgs(rejoined: bool, pref, st: Dictionary) -> Array:
	return [] if rejoined else create_defaults(pref, st)


# 메뉴에서 방을 만든 직후 보낼 방 옵션 메시지 목록 (menu.gd _create): 돌발 이벤트는 기본 켬.
# pref = 기억해 둔 체크 (ui_prefs roundEvents: 없으면 null = 켬, false 면 끈 채로), st = 지금 스냅샷 (비었으면 꺼짐으로 봄 — 서버 기본값).
# 이미 켜져 있으면 안 보냄. 모드는 안 봄 (블록 마스터 방도 켜 둠 — 모드를 바꾸면 그때부터 돎)
static func create_defaults(pref, st: Dictionary) -> Array:
	if pref is bool and not pref:
		return []
	if st.get("roundEvents", false):
		return []
	return [{"type": "roundEvents", "on": true}]


# ---------- hud-layout.js (이어서) ----------

# 머리 위 이름·%: 카메라에서 가까운 LABEL_FULL_N 명만 원래 크기, 나머지는 작고 흐리게. dists[i] → {scale, opacity}
static func label_sizes(dists: Array) -> Array:
	var order := []
	for i in dists.size():
		order.append([dists[i], i])
	# JS sort 는 안정 정렬 → 같은 거리면 원래 순서
	order.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out := []
	for i in dists.size():
		out.append({"scale": 1.0, "opacity": 1.0})
	for rank in order.size():
		if rank >= C.LABEL_FULL_N:
			out[order[rank][1]] = {"scale": C.LABEL_FAR_SCALE, "opacity": C.LABEL_FAR_OPACITY}
	return out


# ---------- kills-hud.js ----------

# 'kill'('death') 이벤트로 판 동안 사람마다 킬·죽음·자멸·연속 킬을 셈. 서버 필드 (kills·deaths·selfKills·streak) 가 있으면 그것 먼저
class KillTally:
	var rows := {} # id → {kills, deaths, self, streak}

	func reset() -> void:
		rows = {}

	func row(id) -> Dictionary:
		if not rows.has(id):
			rows[id] = {"kills": 0, "deaths": 0, "self": 0, "streak": 0}
		return rows[id]

	# e = {who, by, streak?} (by 없음·자기 자신 = 자멸). 반환: 죽인 사람의 연속 킬 (자멸이면 0)
	func add(e: Dictionary) -> int:
		var v := row(e.who)
		v.deaths += 1
		v.streak = 0
		var by = e.get("by")
		if by == null or by == e.who:
			v.self += 1
			return 0
		var k := row(by)
		k.kills += 1
		var s = e.get("streak")
		k.streak = int(s) if (s is float or s is int) and float(s) == floor(float(s)) else k.streak + 1
		return k.streak

	func stats(p: Dictionary) -> Dictionary:
		var r: Dictionary = rows.get(p.id, {"kills": 0, "deaths": 0, "self": 0, "streak": 0})
		return {
			"kills": _int_or(p.get("kills"), r.kills),
			"deaths": _int_or(p.get("deaths"), r.deaths),
			"self": _int_or(p.get("selfKills"), r.self),
			"streak": _int_or(p.get("streak"), r.streak),
		}

	static func _int_or(v, fallback: int) -> int:
		if (v is float or v is int) and float(v) == floor(float(v)):
			return int(v)
		return fallback


# 연속 킬 글자 (KILLS_STREAK_MIN 아래면 '')
static func streak_text(n: int) -> String:
	if n < C.KILLS_STREAK_MIN:
		return ""
	return C.KILLS_STREAK_TEXT.get(str(n), "%d연속 킬" % n)


# 목표까지 진행 (0~1)
static func progress(score, target) -> float:
	var s: float = float(score) if score != null else 0.0
	return clampf(s / max(1.0, float(target)), 0.0, 1.0)


# 점수 순서 (같으면 자리 순서). 관전자·허수아비 뺌
static func ranked(players: Array) -> Array:
	var list := players.filter(func(p): return not p.get("spectator", false) and not p.get("dummy", false))
	list.sort_custom(func(a, b):
		var sa: float = a.get("score", 0.0) if a.get("score") != null else 0.0
		var sb: float = b.get("score", 0.0) if b.get("score") != null else 0.0
		return sa > sb or (sa == sb and a.slot < b.slot))
	return list


# 개인전 위 점수 띠: 1~KILLS_TOP_N 위 + (그 안에 없으면) 나. 같은 점수는 같은 등수
static func top_bar(players: Array, my_id) -> Array:
	var list := ranked(players)
	var score_of := func(p): return float(p.get("score")) if p.get("score") != null else 0.0
	var rank_of := func(i: int) -> int:
		for j in list.size():
			if score_of.call(list[j]) == score_of.call(list[i]):
				return j + 1
		return i + 1
	var out := []
	for i in min(int(C.KILLS_TOP_N), list.size()):
		out.append({"id": list[i].id, "score": score_of.call(list[i]), "rank": rank_of.call(i), "me": list[i].id == my_id})
	var mi := -1
	for i in list.size():
		if list[i].id == my_id:
			mi = i
	if mi >= C.KILLS_TOP_N:
		out.append({"id": my_id, "score": score_of.call(list[mi]), "rank": rank_of.call(mi), "me": true, "extra": true})
	return out


# Tab 점수표 줄 (개인전 점수 순, 팀전은 빨강 먼저 묶음)
static func score_rows(players: Array, tally: KillTally, team_mode: bool) -> Array:
	var list := ranked(players)
	if team_mode:
		list = list.filter(func(p): return p.get("team") == "red") + list.filter(func(p): return p.get("team") != "red")
	var out := []
	for p in list:
		var row := {"id": p.id, "team": p.get("team"), "score": float(p.get("score")) if p.get("score") != null else 0.0}
		row.merge(tally.stats(p))
		out.append(row)
	return out


# 부활까지 큰 숫자 (올림 초, 0 이하·없음이면 0)
static func respawn_secs(ms) -> int:
	if ms == null or float(ms) <= 0.0:
		return 0
	return int(ceil(float(ms) / 1000.0))


# 체력전 HP 비율: hp ÷ hpMax (스냅샷 맨 위 hpMax, 사람마다 있으면 그것). 없으면 null → 막대 안 그림
static func hp_frac(p, hp_max = null):
	if p == null:
		return null
	var mx = p.get("hpMax") if p.get("hpMax") != null and float(p.get("hpMax")) > 0.0 else hp_max
	var hp = p.get("hp")
	if hp == null or mx == null or float(mx) <= 0.0:
		return null
	return clampf(float(hp) / float(mx), 0.0, 1.0)


# 체력전 화면 (kills-hud.js hpView, 2026-10-31 재혁 '% 대신 피'): 켜면 {hp (남은 HP 올림), max, frac, low}, 끔·HP 모름이면 null (예전 %)
static func hp_view(p, st):
	if p == null or st == null or not bool(st.get("hpMode", false)):
		return null
	var frac = hp_frac(p, st.get("hpMax"))
	if frac == null:
		return null
	var mx = p.get("hpMax") if p.get("hpMax") != null and float(p.get("hpMax")) > 0.0 else st.get("hpMax")
	return {"hp": maxf(0.0, ceilf(float(p.hp))), "max": float(mx), "frac": frac, "low": float(frac) < C.HUD_HP_LOW}


# HP 글자색 [r, g, b] 0~255 (kills-hud.js hpColor): 가득 흰색 → 반 노랑 → 0 빨강
static func hp_rgb(frac: float) -> Array:
	var t := clampf(1.0 - frac, 0.0, 1.0)
	return [255.0, 255.0 if t < 0.5 else float(floor(255.0 - (t - 0.5) * 2.0 * 215.0 + 0.5)), float(floor(255.0 - t * 2.0 * 255.0 + 0.5)) if t < 0.5 else 0.0]


static func hp_color(frac: float) -> Color:
	var c := hp_rgb(frac)
	return Color8(int(c[0]), int(c[1]), int(c[2]))


# ---------- wipe.js ----------

# 화면: 'menu'(방 밖) · 'lobby' · 'game'(카운트다운·판 중·판 끝 클로즈업) · 'results'(판 끝 결과 연출)
static func screen_of(in_room: bool, phase: String, hero: bool, closeup := false) -> String:
	if not in_room:
		return "menu"
	if phase == "countdown" or phase == "playing":
		return "game"
	if phase == "over" and closeup:
		return "game"
	if phase == "over" and hero:
		return "results"
	return "lobby"


static func wipe_kind(prev, next):
	if prev == null or next == null or prev == next:
		return null
	if prev == "menu":
		return "short"
	if next == "menu":
		return "short"
	if next == "game" and (prev == "lobby" or prev == "results"):
		return "big"
	if prev == "game" and next == "results":
		return "big"
	if prev == "results" and next == "lobby":
		return "short"
	return null


# reduced: 그래픽 낮춤·움직임 줄이기 → 슬래시 대신 짧은 페이드
static func wipe_plan(kind, reduced := false):
	if kind == null or not C.UI_WIPE.has(kind):
		return null
	if reduced:
		return {"kind": kind, "fade": true, "ms": C.UI_WIPE_FADE_MS, "coverMs": C.UI_WIPE_FADE_MS * C.UI_WIPE_IN, "bands": []}
	var k: Dictionary = C.UI_WIPE[kind]
	var lag: float = k.ms * C.UI_WIPE_STAGGER
	var dur: float = k.ms - lag * (k.bands - 1)
	var X: Dictionary = C.UI_WIPE_X
	var reach: float = C.UI_WIPE_IN
	var leave: float = min(1.0, reach + k.hold)
	var bands := []
	for i in int(k.bands):
		bands.append({
			"delay": i * lag,
			"ms": dur,
			"frames": [
				{"offset": 0.0, "x": X.from},
				{"offset": reach, "x": X.cover},
				{"offset": leave, "x": X.cover},
				{"offset": 1.0, "x": X.to},
			],
		})
	var main: Dictionary = bands[bands.size() - 1]
	return {"kind": kind, "fade": false, "ms": k.ms, "coverMs": main.delay + reach * dur, "bands": bands}


# 띠 하나의 t(ms) 때 x (vw): 키프레임 사이 직선 (JS 는 WAAPI cubic-bezier(.6,0,.3,1) — 화면에선 ease 를 따로 씀)
static func band_x(band: Dictionary, t: float) -> float:
	var u: float = clampf((t - band.delay) / band.ms, 0.0, 1.0)
	var f: Array = band.frames
	for i in range(1, f.size()):
		if u <= f[i].offset:
			var a: Dictionary = f[i - 1]
			var b: Dictionary = f[i]
			var s: float = 0.0 if b.offset == a.offset else (u - a.offset) / (b.offset - a.offset)
			return lerpf(a.x, b.x, s)
	return f[f.size() - 1].x


# ---------- char-select.js ----------

# 큰 3D 캐릭터 방향 (0 = 정면): 고른 뒤 sec 초. 도발 EMOTE_MS 동안 정면, 그 뒤 천천히 돎
static func stage_yaw(sec: float) -> float:
	var hold: float = C.EMOTE_MS / 1000.0
	return 0.0 if sec <= hold else (sec - hold) * C.CHAR_STAGE_SPIN


# 도발 포즈 진행: 고른 뒤 age_ms → {on, t(초)}
static func taunt_at(age_ms: float) -> Dictionary:
	if not (age_ms >= 0.0) or age_ms > C.EMOTE_MS:
		return {"on": false, "t": 0.0}
	return {"on": true, "t": age_ms / 1000.0}


# '랜덤': 지금 캐릭터 말고 하나를 뽑고, 불이 옮겨 다닐 순서 (끝으로 갈수록 느려짐). rnd: Callable 0~1
static func random_reel(chars: Array, current, rnd: Callable) -> Dictionary:
	var pool := chars.filter(func(c): return c != current)
	var list := pool if not pool.is_empty() else chars
	var pick = list[min(list.size() - 1, int(floor(rnd.call() * list.size())))]
	var steps := []
	var at := 0.0
	var i := int(floor(rnd.call() * chars.size()))
	var gap: float = C.CHAR_RANDOM_STEP_MS
	while at + gap < C.CHAR_RANDOM_MS:
		at += gap
		i = (i + 1) % chars.size()
		if chars[i] == pick:
			i = (i + 1) % chars.size() # 끝 전에 미리 멈춰 보이지 않게
		steps.append({"char": chars[i], "at": at})
		gap = js_round(gap * 1.25)
	steps.append({"char": pick, "at": C.CHAR_RANDOM_MS})
	return {"pick": pick, "steps": steps}


# ---------- leave.js ----------

# 판 중(카운트다운·진행)이고 연습 방이 아니고 살아 있으면 한 번 더 묻는다 (나가면 그 판은 패배)
static func leave_needs_confirm(phase: String, practice: bool, alive = true) -> bool:
	if practice:
		return false
	if phase != "playing" and phase != "countdown":
		return false
	return alive != false

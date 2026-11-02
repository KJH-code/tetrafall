# G4 화면 계산 (DOM 없는 순수 계산) — JS 원본을 그대로 옮김:
#   shared/hud-layout.js (아래 판 배치·대기실 판 폭·이름표 크기) · shared/kills-hud.js (킬 점수전 세기·위 띠·Tab 표·부활 초·HP)
#   shared/wipe.js (화면 전환 슬래시) · shared/char-select.js (큰 캐릭터 방향·도발·랜덤 뽑기) · shared/leave.js (나가기 한 번 더)
# tests/test_ui.gd 가 JS 정답 (tests/fixtures/ui.json, tools/fixtures.mjs) 으로 고정. 숫자는 전부 float (config 처럼)
extends RefCounted

const C := preload("res://core/config.gd")


# JS Math.round (반은 위로: -0.5 → -0, 0.5 → 1). 고도 round() 는 반을 0 에서 먼 쪽으로라 음수에서 다름
static func js_round(x: float) -> float:
	return floor(x + 0.5)


# ---------- 화면 공통 (W4 JS 대조) ----------

# JS index.html '작은 창' @media (max-height: 620px), (max-width: 1100px): 글씨·판을 줄여 화면을 덜 가림 (960×540 은 작은 창, 1280×720 은 아님)
static func small(vp: Vector2) -> bool:
	return vp.y <= 620.0 or vp.x <= 1100.0


# 피해 % 글자색 (render.js damageColor): 0% 흰색 → 50% 노랑 → 100% 이상 빨강 [r, g, b] 0~255
static func damage_rgb(d: float) -> Array:
	var t := minf(1.0, d / 100.0)
	var g := 255.0 if t < 0.5 else js_round(255.0 - (t - 0.5) * 2.0 * 215.0)
	var b := js_round(255.0 - t * 2.0 * 255.0) if t < 0.5 else 0.0
	return [255.0, g, b]


static func damage_color(d: float) -> Color:
	var c := damage_rgb(d)
	return Color8(int(c[0]), int(c[1]), int(c[2]))


# 시간 글자 (main.js fmt): 초는 버림
static func fmt_time(ms: float) -> String:
	var s := int(floor(ms / 1000.0))
	return "%d:%02d" % [s / 60, s % 60]


# 죽음 원인·무기 이름 (main.js CAUSE_KO·WEAPON_KO) — 킬 피드 '낙사 (망치)'·부활 대기·관전 안내
const CAUSE_KO := {"crush": "압사", "fall": "낙사", "lava": "용암", "hp": "체력"}
const WEAPON_KO := {"push": "밀치기", "projectile": "투사체", "shock": "충격파", "bomb": "폭탄", "control": "조종 블록", "thrown": "설치 블록", "charge": "돌진", "slam": "내려찍기", "slash": "순간 베기", "wall": "솟는 벽", "hook": "갈고리", "blockslam": "블록내려찍기", "blast": "블록 폭발", "bigbomb": "대폭발", "wallkick": "벽차기", "quake": "솟는 땅", "ghost": "유령블록", "glide": "낙하 음파", "shell": "포탄", "bigshell": "대형 포탄", "groundshot": "발밑 포격", "pounce": "추적 도약", "execute": "처형 사격", "leapwave": "광폭 도약", "spin": "분노 소용돌이", "note": "음파", "riff": "리프", "amp": "앰프 음파"}


static func weapon_ko(w) -> String:
	return "" if w == null or str(w) == "" else str(WEAPON_KO.get(str(w), str(w)))


# 킬 피드 원인 칸 (main.js killFeed how): '낙사 (망치)'
static func cause_text(cause, weapon) -> String:
	var c := str(CAUSE_KO.get(str(cause), str(cause)))
	var w := weapon_ko(weapon)
	return c + (" (%s)" % w if w != "" else "")


# 핑 칸 색 (index.html #netPing[data-level]): 보통 = 흐린 글 + 어두운 칸, warn = 검정 글 + 노랑 (#ffe98a→#ffb400), bad = 흰 글 + 빨강 (#ff4426→#a81405).
# 고도 칸은 한 색이라 그라데이션 가운데 색
static func net_look(level: String) -> Dictionary:
	match level:
		"warn":
			return {"fg": Color("1a1300"), "bg": Color("ffe98a").lerp(Color("ffb400"), 0.5)}
		"bad":
			return {"fg": Color.WHITE, "bg": Color("ff4426").lerp(Color("a81405"), 0.5)}
	return {"fg": Color("9fabcd"), "bg": Color8(8, 12, 26, 153)}


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


# CSS cubic-bezier(x1, y1, x2, y2) 시간 곡선: 진행 u (0~1) → 바뀐 진행. x(s) = u 를 뉴턴 + 이분법으로 풀고 y(s)
static func cubic_bezier(u: float, x1: float, y1: float, x2: float, y2: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return clampf(u, 0.0, 1.0)
	var bx := func(s: float) -> float: return ((1.0 - 3.0 * x2 + 3.0 * x1) * s + (3.0 * x2 - 6.0 * x1)) * s * s + 3.0 * x1 * s
	var s := u
	for i in 8:
		var dx: float = bx.call(s) - u
		var d: float = (3.0 * (1.0 - 3.0 * x2 + 3.0 * x1) * s + 2.0 * (3.0 * x2 - 6.0 * x1)) * s + 3.0 * x1
		if absf(dx) < 1e-7:
			break
		if absf(d) < 1e-6:
			break
		s = clampf(s - dx / d, 0.0, 1.0)
	if absf(bx.call(s) - u) > 1e-5: # 뉴턴이 안 모이면 이분법
		var lo := 0.0
		var hi := 1.0
		for i in 40:
			s = (lo + hi) / 2.0
			if bx.call(s) < u:
				lo = s
			else:
				hi = s
	return ((1.0 - 3.0 * y2 + 3.0 * y1) * s + (3.0 * y2 - 6.0 * y1)) * s * s + 3.0 * y1 * s


# 띠 하나의 화면 x (vw): JS 는 띠마다 WAAPI { easing: 'cubic-bezier(.6,0,.3,1)' } — 효과 전체 진행에 곡선을 씌운 뒤 키프레임 사이 직선
static func band_x_eased(band: Dictionary, t: float) -> float:
	var u: float = clampf((t - band.delay) / band.ms, 0.0, 1.0)
	return band_x(band, band.delay + cubic_bezier(u, 0.6, 0.0, 0.3, 1.0) * band.ms)


# 페이드 (그래픽 낮춤·움직임 줄이기): 0 → 1 (UI_WIPE_IN) → 0, 전체 진행에 ease-out (cubic-bezier(0,0,.58,1))
static func fade_alpha(t: float, ms: float) -> float:
	var u := cubic_bezier(clampf(t / ms, 0.0, 1.0), 0.0, 0.0, 0.58, 1.0)
	var a: float = u / C.UI_WIPE_IN if u < C.UI_WIPE_IN else 1.0 - (u - C.UI_WIPE_IN) / (1.0 - C.UI_WIPE_IN)
	return clampf(a, 0.0, 1.0)


# 띠 하나의 t(ms) 때 x (vw): 키프레임 사이 직선 (곡선 전 — 정답 자료 shared/wipe.js 와 비교용, 화면은 band_x_eased)
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

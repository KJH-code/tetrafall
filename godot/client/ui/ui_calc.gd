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


# ---------- 고도 판 전용 (JS 에 없음 — 정답 자료 대신 tests/test_ui.gd 가 값으로 고정) ----------
# 접속 표시 (ui.gd net_box — JS #net: 오른쪽 12 · 위 52): 핑 칸이 맨 위 (글자 12 + 위아래 여백 2 — 화면에서 잰 높이 19, 자동 조종 --dump), 그 아래 렉·끊김 알림 칸
const NET_RIGHT := 12.0
const NET_TOP := 52.0
const NET_PING_H := 19.0
const NET_GAP := 3.0 # 핑 칸과 그 아래 판 (결과 판) 사이 띄움
# 대기실 판 (lobby.gd _place, JS #center): 세로 가운데 + LOBBY_DROP, 판 최대 높이 = 화면 − LOBBY_VPAD (넘치면 판 안에서 스크롤),
# 위 끝은 LOBBY_TOP_MIN 아래·아래 끝은 화면 − LOBBY_BOTTOM 위. 가장 긴 판의 위 끝 = LOBBY_VPAD / 2 + LOBBY_DROP = 74 → 핑 칸 (52~71) 아래
const LOBBY_DROP := 28.0
const LOBBY_VPAD := 92.0
const LOBBY_TOP_MIN := 46.0
const LOBBY_BOTTOM := 18.0
const RESULTS_SCALE_MIN := 0.1 # 결과 판 줄임 배율 아래 끝 (0 으로 나누기·뒤집힘 막기)
# 결과 판 위쪽 끝 (이보다 위로는 안 올라감) = 핑 칸 아래 끝 + 띄움 (74 — 대기실 판의 가장 높은 위 끝과 같음).
# 예전 40 (위 점수 띠 아래) 은 칭호 줄로 길어진 판이 올라와 오른쪽 위 핑 칸을 판 모서리 안에 넣었음 (사이클 6 병합 리뷰 F3)
const RESULTS_TOP := NET_TOP + NET_PING_H + NET_GAP
const RESULTS_DROP := 22.0 # 결과 판: 세로 가운데에서 이만큼 아래
# 방 옵션 표시: [키 (스냅샷·공개 목록 같음), 글, 켜도 안 먹는 모드]. 블록 마스터 판은 하늘 계단 (Game.Round.cs StartRound sky)·돌발 이벤트 (Game.Events.cs RoundEventsRun) 가 안 돎
const ROOM_OPTS := [["skyStairs", "하늘 계단", ["master"]], ["hpMode", "체력전", []], ["roundEvents", "돌발 이벤트", ["master"]]]


const STATUS_POS := Vector2(16, 12) # 접속 상태 글 (연결 중·끊김 — ui.gd status) 자리: 메뉴·대기실·결과는 왼쪽 위
# 판 HUD 가 보일 때: 왼쪽, 판 시간 (hud.gd timer_label (14, 12) 글자 26 — 아래 끝 약 52) 아래. 예전 (16, 64) 은 위 가운데 튜토리얼 진행 띠
# (tutorial_ui.gd band_top y 58)·블록 마스터 생존자 배너 (hud_extra top_box y 62) 와 겹쳤음 — 띠 폭이 글 길이 따라 화면 대부분까지 늘어 x 만 옮겨서는 못 피함 (사이클 5 리뷰 F3).
# 한 줄 띠 (아래 끝 약 97) 는 이 자리가 그 아래지만, 문구가 두 줄로 접히면 (아래 끝 약 120) 여기까지 내려옴 → 띠도 피할 칸 (status_box_pos avoid) 으로 받아 그 아래로 내림
const STATUS_POS_GAME := Vector2(16, 108)
# 판 중 받침 (상태 글 뒤 어두운 반투명 판): top_box 는 배너·경고·토스트가 쌓이며 아래로 자라 드물게 겹칠 수 있음 — 겹쳐도 글이 읽히게.
# 메뉴·대기실·결과는 받침 없음 (예전 모양)
const STATUS_BACK := Color(0.03, 0.04, 0.09, 0.72)
const STATUS_PAD := Vector2(8, 4) # 받침 안쪽 여백 (좌우, 위아래). 글은 그대로 status_pos 에 — 받침이 여백만큼 바깥으로
const STATUS_RADIUS := 4 # 받침 모서리 둥글기
# 가운데 위 알림 칸 (hud_extra top_box) 과 받침 사이 띄움: 칸 사각형을 이만큼 키워 (평행사변형 기울기로 삐져나온 몫 포함) 겹치면 그 아래로 이만큼 띄워 내림
const STATUS_GAP := 6.0


# 접속 상태 글 자리 (글 왼쪽 위): in_game = 판 HUD 가 보임 (ui.gd hud.visible)
static func status_pos(in_game: bool) -> Vector2:
	return STATUS_POS_GAME if in_game else STATUS_POS


# 받침 (글을 담은 판, ui.gd status_box) 왼쪽 위: 글 자리에서 여백만큼 바깥.
# 판 중엔 피할 칸들 (avoid: Rect2 배열, 같은 캔버스 좌표 — ui.gd _avoid_rects: 가운데 위 알림 칸 + 연습 방 왼쪽 위 힌트·연습 창 + 튜토리얼 진행 띠) 과 겹치면
# (칸을 STATUS_GAP 만큼 키워 봄) 그 칸 아래로 STATUS_GAP 띄워 내림.
# 배너는 글 길이·줄 수 따라 왼쪽·아래로 늘어 고정 자리로는 못 피함 (사이클 5 테스트: 960 폭 블록 마스터 본인의 두 줄 배너가 x 약 218 까지 와 받침이 둘째 줄을 가림).
# 연습 힌트 '연습 창 Tab'·연습 창 (practice.gd, 둘 다 (14, 70)) 은 연습 화면이 위 층 (CanvasLayer 15) 이라, 튜토리얼 진행 띠 (tutorial_ui.gd, 줄 수 따라
# 아래 끝이 달라짐) 는 튜토리얼 화면이 위 층 (20) 이라 겹치면 상태 글이 가려짐 (사이클 5 수정 리뷰 1 · 사이클 6 병합 리뷰 F1).
# room = 받침이 들어가야 하는 칸 (status_room: 화면에서 아래 사람 판·스킬 칸 위까지, 넓이 0 이면 제한 없음). 내린 자리가 room 을 벗어나면
# (작은 화면에서 긴 연습 창 아래) 대신 막은 칸 오른쪽 옆 (그 칸 오른쪽 끝 + 띄움, 처음 높이에서 다시 내려 봄) 중 왼쪽부터 room 에 드는 첫 자리. 없으면 내린 자리 그대로.
# size = 받침 크기 (0 이면 안 내림)
static func status_box_pos(in_game: bool, size := Vector2.ZERO, avoid: Array = [], room := Rect2()) -> Vector2:
	var start := status_pos(in_game) - STATUS_PAD
	if not in_game:
		return start
	var pos := _drop_below(start, size, avoid)
	if not room.has_area() or room.encloses(Rect2(pos, size)):
		return pos
	var xs: Array = []
	for r in avoid:
		var x: float = (r as Rect2).grow(STATUS_GAP).end.x
		if x > start.x and not xs.has(x):
			xs.append(x)
	xs.sort()
	for x in xs:
		var q := _drop_below(Vector2(x, start.y), size, avoid)
		if room.encloses(Rect2(q, size)):
			return q
	return pos


# 받침이 들어갈 칸: 화면 위 왼쪽부터, 아래 HUD 칸들 (bottom: Rect2 배열 — 사람 판 줄·F·R 칸·내 %·관전 안내) 중 가장 높은 위 끝 - STATUS_GAP 까지
static func status_room(view: Vector2, bottom: Array = []) -> Rect2:
	var floor_y := view.y
	for r in bottom:
		floor_y = minf(floor_y, (r as Rect2).position.y - STATUS_GAP)
	return Rect2(Vector2.ZERO, Vector2(view.x, maxf(0.0, floor_y)))


# pos 에서 겹치는 칸 아래로 내리기를 더 안 겹칠 때까지. 내려가기만 하니 칸마다 많아야 한 번 → avoid 수 + 1 번 돌면 끝
static func _drop_below(pos: Vector2, size: Vector2, avoid: Array) -> Vector2:
	for _i in avoid.size() + 1:
		var moved := false
		for r in avoid:
			var near: Rect2 = (r as Rect2).grow(STATUS_GAP)
			if Rect2(pos, size).intersects(near):
				pos.y = near.end.y
				moved = true
		if not moved:
			break
	return pos


# 받침 색: 판 중엔 STATUS_BACK, 그 밖엔 투명
static func status_back(in_game: bool) -> Color:
	return STATUS_BACK if in_game else Color(0, 0, 0, 0)


# 접속 표시 (ui.gd net_box) 왼쪽 위: 오른쪽 끝에서 NET_RIGHT, 위 NET_TOP. box_w = 표시 폭 (핑 칸·알림 칸 중 넓은 쪽)
static func net_pos(view: Vector2, box_w: float) -> Vector2:
	return Vector2(view.x - NET_RIGHT - box_w, NET_TOP)


# 핑 칸 (접속 표시 맨 위 칸, 오른쪽 맞춤) 의 화면 사각형. ping_w = 핑 칸 폭
static func net_ping_rect(view: Vector2, ping_w: float) -> Rect2:
	return Rect2(view.x - NET_RIGHT - ping_w, NET_TOP, ping_w, NET_PING_H)


# 대기실 판 안 스크롤 칸 높이 (lobby.gd _place): 내용 높이 그대로, 판 (스크롤 칸 + 판 위아래 여백 pad) 이 화면 − LOBBY_VPAD 를 넘으면 거기까지 (나머지는 판 안에서 스크롤)
static func lobby_scroll_h(view_h: float, content_h: float, pad: float) -> float:
	return minf(content_h, view_h - LOBBY_VPAD - pad)


# 대기실 판 위 끝 y (lobby.gd _place): 세로 가운데 + LOBBY_DROP, [LOBBY_TOP_MIN, 화면 − 판 높이 − LOBBY_BOTTOM] 안. panel_h = 판 높이 (스크롤 칸 + 여백)
static func lobby_y(view_h: float, panel_h: float) -> float:
	var y := (view_h - panel_h) / 2.0 + LOBBY_DROP
	return clampf(y, LOBBY_TOP_MIN, maxf(LOBBY_TOP_MIN, view_h - panel_h - LOBBY_BOTTOM))


# 결과 판 자리 (results.gd _place): 오른쪽 끝에 붙이고 세로 가운데에서 RESULTS_DROP 만큼 아래 (위 점수 띠를 비킴).
# content = 줄이기 전 판 크기. 위 (RESULTS_TOP — 오른쪽 위 핑 칸 아래)·아래 (HUD_CARD_MARGIN) 여백 안으로 y 를 넣고, 그 사이 높이·화면 폭보다 크면 통째로 줄임
# (960×540 에 8명 + 칭호 3줄), 들어가면 배율 1. 줄인 판은 줄인 폭 (content.x × 배율) 으로 오른쪽에 붙임. 반환 {scale 배율, x·y 왼쪽 위}
static func results_place(view: Vector2, content: Vector2) -> Dictionary:
	var m: float = C.HUD_CARD_MARGIN
	var room := Vector2(view.x - m * 2.0, view.y - RESULTS_TOP - m)
	var s := 1.0
	if content.x > 0.0 and content.y > 0.0:
		s = clampf(minf(room.x / content.x, room.y / content.y), RESULTS_SCALE_MIN, 1.0)
	var h := content.y * s
	var y := minf((view.y - h) / 2.0 + RESULTS_DROP, view.y - m - h) # 아래로 넘치면 올리고
	return {"scale": s, "x": view.x - m - content.x * s, "y": maxf(y, RESULTS_TOP)} # 위는 핑 칸 아래까지만


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

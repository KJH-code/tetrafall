# 손 아이템 조준 미리보기 · 놓인 폭탄 범위 고리 · '폭탄!' 화면 신호의 순수 계산 (c11-u1, 그리는 쪽은 world/hand_aim.gd · ui/bomb_alert.gd).
# 서버가 이미 보내는 값만 씀 (서버는 그대로): 스냅샷 players[].aim {kind, cells [[x, y, z]…], ok} · bombs[] {id, x, y, z, left} · 이벤트 bombPlace {who, x, y, z}.
# 노드 없음 → tests/test_round_events.gd test_c11_* 가 고정. 수치는 전부 여기 (고도 판 전용 — core/config.gd 는 JS 에서 만든 파일이라 안 고침)
extends RefCounted

const C := preload("res://core/config.gd")
const BM := preload("res://world/bolt_fx_math.gd")

# 조준 미리보기 (내가 든 설치 블록·폭탄이 어디에 놓이는지 — JS 판 client/render.js updateAim 과 같은 뜻)
const HAND_AIM := {
	"views": ["first", "third"], # 보이는 시점 (View.mode) — 하늘 시점·관전은 끔
	"box_color": 0xffffff, "box_alpha": 0.28, # 설치 블록: 칸마다 반투명 상자 (알파 = 상자를 지나 보이는 값 — 면 하나의 알파는 face_alpha)
	"box_inset": 0.01, # 상자를 칸보다 이만큼 (칸) 안으로 — 바닥·옆 블록 면과 겹쳐 깜빡이지 않게
	"edge_color": 0xf0d060, "edge_w": 0.04, "edge_alpha": 1.0, # 상자 모서리 테 (떨어지는 설치 블록과 같은 노랑), 굵기 (칸)
	"pad_color": 0xff5030, "pad_alpha": 0.35, # 폭탄: 부서질 칸마다 납작 판
	"pad_h": 0.02, # 판 높이 (칸). JS 판은 0.12 인데 여기는 양면을 그려서 두꺼우면 비스듬히 볼 때 이웃 판과 겹친 띠가 진한 줄무늬로 보임 → 얇게
	"pad_inset": 0.03, # 판을 칸보다 이만큼 안으로 (칸 사이 틈이 보여 9칸으로 읽힘)
	"pad_lift": 0.01, # 판 밑면을 바닥에서 띄움
	"bad_color": 0xff2020, # 못 쓰는 자리 (ok = false): 상자·테·판 모두 빨강
	"ring_alpha": 0.9, "ring_lift": 0.05, # 폭탄: 사람이 맞는 범위 고리 (반지름 C.BOMB_BLAST_RANGE, 내 색 이어진 고리)
	# 고리 꼴 (world/ring_look.gd LOOKS 의 이름) — 시점마다. c11-fix F1: 3인칭은 가는 선 고리 ("aim") — 예전 windup (띠 폭 0.48칸) 은 바로 옆에 보이는 내 발밑 고리와 같은 꼴이었음.
	# 1인칭은 내 발밑 고리가 안 보여 헷갈릴 것이 없고 눈높이에서 가는 선은 얇게 누워 안 읽힘 → 예전 그대로
	"ring_look": {"first": "windup", "third": "aim"},
	# c11-fix F1 몸 너머로 비침: 3인칭에서 폭탄 조준 판·고리는 카메라와 조준 칸 사이의 내 몸에 거의 다 가렸음 (주황 화소가 1인칭의 4%) → 같은 판·고리를 깊이 검사 없이 한 벌 더, 옅게.
	#   xray_views 그 한 벌을 그리는 시점 · xray 그 한 벌의 알파 배율 (몸 뒤 부분 = 원래 알파 × 이 값 — 몸을 지우는 것처럼 안 보이게 원래의 절반 이하, 화풍 기준서: 몸 너머로 비치는 것은 옅게)
	"xray_views": ["third"], "xray": 0.45,
	"priority": 7, # 그리는 순서: 상자·판 7 · 테·고리 8 (이름표 외곽선 10·이름표 11 아래)
	"max_cells": 16, # 상자·판 인스턴스 수 (설치 블록 2칸 · 폭탄 9칸)
}
# 놓인 폭탄 둘레 고리 (모든 시점): 번개 예고와 같은 끊긴 고리 메시 (bolt_fx_math.warn_mesh) + 안에서 차오르는 주황 원 (번개는 연노랑 — 색으로 갈림)
const BOMB_RING := {
	"fill": 0xff8a30, "fill_alpha": 0.4, # 채운 원 색·알파
	"ring_alpha": 0.9,
	"lift": 0.04, # 폭탄 칸 바닥에서 띄움 (칸)
	"spin": 0.9, # 끊긴 고리가 도는 빠르기 (rad/초 — 번개 예고와 같음)
	"priority": 9, # 번개 예고 고리와 같은 순서
	"max": 8, # 한 번에 그리는 폭탄 수
}
# 내가 남의 폭탄 범위 안일 때 화면 신호 (ui/bomb_alert.gd): 판 모양·자리·깜빡임은 번개 판 (bolt_fx_math.ALERT) 그대로, 글·색만 다름
const BOMB_ALERT := {
	"text": "폭탄! 고리 밖으로",
	"glow": 0xff8a30, # 주황 (놓인 폭탄 채운 원과 같은 색)
	"pending_max": 16, # 아직 짝 못 지은 bombPlace 기억 수
	# c11-fix F8 빠질 방향 화살표 (판 안, 글과 남은 초 사이): 1인칭에서 폭탄이 옆·뒤면 고리·폭탄이 화면 밖이라 어느 쪽으로 빠져야 할지 몰랐음 → 폭탄 가운데 → 나 방향 (고리 밖으로 가장 짧은 쪽) 을 화면 기준으로.
	#   arrow_px 화살표 칸 한 변 (px) · arrow_min 나와 폭탄 가운데의 수평 거리가 이보다 가까우면 (칸) 방향이 안 정해져 안 그림 (어느 쪽으로 가도 같음)
	#   arrow 오른쪽 (+x) 을 가리키는 화살표 꼴 (칸 한 변 = 1, 가운데 0 — 글자가 아니라 도형으로 그림: 본문 글꼴에 화살표 글자가 없음)
	"arrow_px": 30.0, "arrow_min": 0.2,
	"arrow": [[-0.42, -0.15], [0.02, -0.15], [0.02, -0.42], [0.48, 0.0], [0.02, 0.42], [0.02, 0.15], [-0.42, 0.15]],
}


# ---------- 조준 미리보기 ----------
# 보이는가: 내가 살아 있고, 조준 값이 있고 (넉백 글러브·빈손은 null), 1·3인칭이고, 관전이 아니고, 판 중일 때
static func aim_on(me: Dictionary, view_mode: String, spectating: bool, playing := true) -> bool:
	if not playing or spectating or me.is_empty() or not bool(me.get("alive", false)) or not (view_mode in HAND_AIM.views):
		return false
	var aim = me.get("aim")
	return aim is Dictionary and aim.get("cells") is Array and not (aim.cells as Array).is_empty()


# c11-fix F1: 이 시점에서 폭탄 조준 판·고리를 몸 너머로 한 벌 더 그리나 (설치 블록 상자는 몸 위로 솟아 안 가림 → 폭탄만)
static func aim_xray(view_mode: String, kind: String) -> bool:
	return kind == "bomb" and (HAND_AIM.xray_views as Array).has(view_mode)


# 몸 너머로 비치는 한 벌의 알파 (원래 알파 a 의 xray 배)
static func xray_alpha(a: float) -> float:
	return a * float(HAND_AIM.xray)


# 이 시점의 조준 고리 꼴 (ring_look.LOOKS 이름)
static func ring_look(view_mode: String) -> String:
	return str((HAND_AIM.ring_look as Dictionary).get(view_mode, "windup"))


# 그릴 줄들. 한 줄 = {kind, at (게임 좌표 가운데 Vector3), color (0xRRGGBB), alpha} + 상자·판·테는 size (게임 좌표 x·y·z 길이), 고리는 r (반지름 칸)·look (고리 꼴).
#   설치 블록: 칸마다 "box" 하나 + "edge" 12개 (모서리 막대) · 폭탄: 칸마다 "pad" 하나 + 첫 칸 (폭탄 자리) 가운데에 "ring" 하나 (my_color)
static func aim_rows(me: Dictionary, view_mode: String, spectating: bool, my_color: int, playing := true) -> Array:
	var out := []
	if not aim_on(me, view_mode, spectating, playing):
		return out
	var aim: Dictionary = me.aim
	var ok := bool(aim.get("ok", false))
	var bad := int(HAND_AIM.bad_color)
	var cells: Array = aim.cells
	var n := mini(cells.size(), int(HAND_AIM.max_cells))
	if str(aim.get("kind", "")) == "bomb":
		var h := float(HAND_AIM.pad_h)
		var side := 1.0 - 2.0 * float(HAND_AIM.pad_inset)
		for i in n:
			var c: Array = cells[i]
			out.append({"kind": "pad", "at": Vector3(float(c[0]) + 0.5, float(c[1]) + 0.5, float(c[2]) + float(HAND_AIM.pad_lift) + h / 2.0), "size": Vector3(side, side, h),
				"color": int(HAND_AIM.pad_color) if ok else bad, "alpha": float(HAND_AIM.pad_alpha)})
		var c0: Array = cells[0]
		out.append({"kind": "ring", "at": Vector3(float(c0[0]) + 0.5, float(c0[1]) + 0.5, float(c0[2]) + float(HAND_AIM.ring_lift)), "r": float(C.BOMB_BLAST_RANGE),
			"color": my_color, "alpha": float(HAND_AIM.ring_alpha), "look": ring_look(view_mode)})
		return out
	var s := 1.0 - 2.0 * float(HAND_AIM.box_inset)
	for i in n:
		var c: Array = cells[i]
		var mid := Vector3(float(c[0]) + 0.5, float(c[1]) + 0.5, float(c[2]) + 0.5)
		out.append({"kind": "box", "at": mid, "size": Vector3(s, s, s), "color": int(HAND_AIM.box_color) if ok else bad, "alpha": float(HAND_AIM.box_alpha)})
		for e in edge_bars(mid):
			out.append({"kind": "edge", "at": e[0], "size": e[1], "color": int(HAND_AIM.edge_color) if ok else bad, "alpha": float(HAND_AIM.edge_alpha)})
	return out


# 한 칸 (가운데 mid) 의 모서리 막대 12개: [[가운데, 길이 (x, y, z)], …]. 막대는 칸 안쪽에 붙음 (바깥 면 = 칸 면), 굵기 HAND_AIM.edge_w
static func edge_bars(mid: Vector3) -> Array:
	var w := float(HAND_AIM.edge_w)
	var off := 0.5 - w / 2.0
	var out := []
	for axis in 3:
		var b := (axis + 1) % 3
		var c := (axis + 2) % 3
		for sb in [-1.0, 1.0]:
			for sc in [-1.0, 1.0]:
				var at := mid
				at[b] += sb * off
				at[c] += sc * off
				var size := Vector3(w, w, w)
				size[axis] = 1.0
				out.append([at, size])
	return out


# 반투명 상자는 양면을 다 그려서 (고리 재질과 같은 셰이더 — 새 셰이더 없음) 어느 쪽에서 봐도 면 둘을 지남 → 면 하나의 알파: 둘이 겹쳐 total 이 되는 값
static func face_alpha(total: float) -> float:
	return 1.0 - sqrt(1.0 - clampf(total, 0.0, 1.0))


# ---------- 놓인 폭탄 고리 ----------
# 채운 원이 찬 비율: 놓은 순간 0 → 터지는 순간 1 (left = 스냅샷 bombs[].left, 남은 ms)
static func bomb_fill(left: float) -> float:
	return clampf(1.0 - left / float(C.BOMB_FUSE_MS), 0.0, 1.0)


# 폭탄마다 한 줄: {at (게임 좌표: 칸 가운데, 칸 바닥 + lift), r (고리 바깥 반지름 = 사람이 맞는 수평 범위), fill_r (채운 원 반지름: 다 차면 고리 안쪽 끝), spin (rad)}
static func bomb_ring_rows(bombs: Array, now: float, playing := true) -> Array:
	var out := []
	if not playing:
		return out
	var r := float(C.BOMB_BLAST_RANGE)
	var inner := float(BM.WARN.bands[0][0])
	for b in bombs:
		if out.size() >= int(BOMB_RING.max):
			break
		if not (b is Dictionary) or b.get("x") == null or b.get("y") == null:
			continue
		out.append({"at": Vector3(float(b.x) + 0.5, float(b.y) + 0.5, float(b.get("z", 0.0)) + float(BOMB_RING.lift)), "r": r,
			"fill_r": r * inner * bomb_fill(float(b.get("left", 0.0))), "spin": float(BOMB_RING.spin) * now / 1000.0})
	return out


# ---------- '폭탄!' 화면 신호 ----------
# 나 (스냅샷 players[] 한 명) 가 이 폭탄에 맞는 자리인가 — 서버 Game.ExplodeBomb 과 같은 식:
# 폭탄 칸 가운데 (x + 0.5, y + 0.5, z + 0.5) 에서 수평 거리 ≤ BOMB_BLAST_RANGE, 몸 가운데 높이 (z + PLAYER_HEIGHT / 2) 차 ≤ BOMB_BLAST_RANGE. 살아서 필드에 있을 때만
static func bomb_in_range(me: Dictionary, b: Dictionary) -> bool:
	if me.is_empty() or not bool(me.get("alive", false)) or bool(me.get("master", false)) or me.get("x") == null or me.get("y") == null or b.get("x") == null or b.get("y") == null:
		return false
	var r := float(C.BOMB_BLAST_RANGE)
	var flat := Vector2(float(me.x) - (float(b.x) + 0.5), float(me.y) - (float(b.y) + 0.5)).length()
	return flat <= r and absf(float(me.get("z", 0.0)) + float(C.PLAYER_HEIGHT) / 2.0 - (float(b.get("z", 0.0)) + 0.5)) <= r


# 놓인 자리 → 주인을 짝짓는 열쇠 (이벤트 bombPlace 와 스냅샷 bombs[] 가 같은 x·y 칸).
# c11-fix F2: 높이 z 는 안 넣음 — 서버는 이벤트를 낸 뒤 같은 틱에 폭탄 높이를 기둥 꼭대기로 다시 맞춤 (Game.Items.cs UpdateBombs) → 그 사이 기둥이 바뀌면 (앞 폭탄이 터짐·블록이 쌓임)
# 이벤트 z 와 첫 스냅샷 z 가 달라 내 폭탄을 남의 것으로 봤음
static func owner_key(x, y) -> String:
	return "%d,%d" % [int(x), int(y)]


# 이벤트 bombPlace {who, x, y, z} 를 기억 (pending 한 항목 = {key, who, at}). now = 판 시계 (ms, Net.now_ms) — 오래된 기억을 버리는 데 씀. 값이 빠졌으면 무시
static func owner_note(pending: Array, e: Dictionary, now: float) -> void:
	if e.get("who") == null or e.get("x") == null or e.get("y") == null:
		return
	pending.append({"key": owner_key(e.x, e.y), "who": int(e.who), "at": now})
	while pending.size() > int(BOMB_ALERT.pending_max):
		pending.pop_front()


# 도화선 시간 (C.BOMB_FUSE_MS) 이 지난 기억을 버림: 폭탄은 도화선보다 오래 남지 않음 → 그때까지 짝 못 지은 기억은 이미 터진 폭탄의 것.
# 남겨 두면 나중에 같은 칸에 놓인 남의 폭탄에 붙어 그 폭탄의 경고가 빠짐
static func owner_expire(pending: Array, now: float) -> void:
	var i := 0
	while i < pending.size():
		if now - float(pending[i].get("at", now)) > float(C.BOMB_FUSE_MS):
			pending.remove_at(i)
		else:
			i += 1


# 스냅샷의 폭탄에 주인을 붙임 (owners: 폭탄 id → 주인 id). 새 폭탄은 같은 x·y 칸의 기억 (먼저 온 것부터) 과 짝짓고, 없어진 폭탄은 지움. now = 판 시계 (ms) — 오래된 기억부터 버림.
# id 로 붙여 두는 까닭: 한번 붙이면 그 뒤 자리 값과 상관없이 그 폭탄의 주인 (열쇠는 처음 짝지을 때만 씀)
static func owner_bind(owners: Dictionary, pending: Array, bombs: Array, now: float) -> void:
	owner_expire(pending, now)
	var live := {}
	for b in bombs:
		if not (b is Dictionary) or b.get("id") == null:
			continue
		var id := int(b.id)
		live[id] = true
		if owners.has(id):
			continue
		var key := owner_key(b.get("x", 0), b.get("y", 0))
		for i in pending.size():
			if str(pending[i].key) == key:
				owners[id] = int(pending[i].who)
				pending.remove_at(i)
				break
	for id in owners.keys():
		if not live.has(id):
			owners.erase(id)


# 이 주인의 폭탄에 나는 안 맞는가: 내 폭탄이거나 팀전에서 같은 팀 (서버: 던진 사람·같은 팀 면제). 주인을 모르면 (owner null) false = 위험으로 침
static func bomb_safe(owner, me: Dictionary, st: Dictionary) -> bool:
	if owner == null or me.get("id") == null:
		return false
	if int(owner) == int(me.id):
		return true
	if not bool(st.get("teamMode", false)) or me.get("team") == null:
		return false
	for p in st.get("players", []):
		if int(p.id) == int(owner):
			return p.get("team") == me.get("team")
	return false


# 내가 맞을 폭탄 가운데 가장 먼저 터질 것: {left (남은 ms), ms (도화선 시간), x·y (폭탄 칸 가운데 — 빠질 방향 화살표)}. 없으면 {}
static func bomb_pick(bombs: Array, owners: Dictionary, me: Dictionary, st: Dictionary) -> Dictionary:
	var out := {}
	for b in bombs:
		if not (b is Dictionary) or not bomb_in_range(me, b):
			continue
		if bomb_safe(owners.get(int(b.id)) if b.get("id") != null else null, me, st):
			continue
		var left := maxf(0.0, float(b.get("left", 0.0)))
		if out.is_empty() or left < float(out.left):
			out = {"left": left, "ms": float(C.BOMB_FUSE_MS), "x": float(b.x) + 0.5, "y": float(b.y) + 0.5}
	return out


# c11-fix F8: 빠질 방향 (화면 기준 단위 벡터 — x 오른쪽 +, y 아래 +, 곧 카메라 앞쪽 = (0, −1)). 폭탄 가운데 (bx, by) → 나 = 고리 밖으로 가장 짧게 나가는 쪽.
# cam_yaw = 카메라가 보는 쪽 (게임 yaw: 0 = +x, 반시계 — 앞 (cos, sin) · 오른쪽 (sin, −cos)). 나와 폭탄이 수평으로 arrow_min 보다 가까우면 null (방향이 안 정해짐 → 화살표 숨김)
static func escape_dir(me: Dictionary, bx: float, by: float, cam_yaw: float):
	if me.get("x") == null or me.get("y") == null:
		return null
	var d := Vector2(float(me.x) - bx, float(me.y) - by)
	if d.length() < float(BOMB_ALERT.arrow_min):
		return null
	d = d.normalized()
	return Vector2(d.dot(Vector2(sin(cam_yaw), -cos(cam_yaw))), -d.dot(Vector2(cos(cam_yaw), sin(cam_yaw))))


# 화살표 도형의 꼭짓점 (화면 px): dir 쪽을 가리키게 돌리고 size (한 변 px) 로 키워 center 에
static func arrow_points(dir: Vector2, size: float, center: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var a := dir.angle()
	for p in BOMB_ALERT.arrow:
		out.append(center + Vector2(float(p[0]), float(p[1])).rotated(a) * size)
	return out


# 폭탄 판을 띄우는가: 번개 판이 떠 있으면 숨김 (같은 자리 — 번개가 더 빨리 떨어지고 범위가 좁아 먼저 알림)
static func bomb_alert_show(bolt_on: bool, pick: Dictionary) -> bool:
	return not bolt_on and not pick.is_empty()

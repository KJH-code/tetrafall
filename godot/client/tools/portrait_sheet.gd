# 초상 견본 (c8): 서버 없이 캐릭터 8명의 얼굴 초상을 실제 ui/portrait.gd 로 그려 한 장에 — 위 줄 192 (결과 승자), 아래 줄 96 (아래 사람 판).
#   xvfb-run -a godot --path godot/client --resolution 1280x720 --rendering-driver opengl3 -s res://tools/portrait_sheet.gd -- --out <png> [--no-ext]
# --no-ext = 외부 모델 끔 (웹 기본 — 8명 모두 구운·코드 몸). 색은 팔레트 순서 (캐릭터마다 다른 색).
# 192 칸마다 한 줄씩 출력 (얼굴이 칸 가운데에 같은 크기로 들어갔는지 숫자로 — 수치는 ui/portrait_config.gd FACE·json "portrait" 로 맞춤):
#   fill = 몸 화소 (알파 > SOLID) ÷ 칸 화소 · cx = 몸 화소의 가로 무게중심 (0 왼쪽 ~ 1 오른쪽) · top = 몸 화소가 처음 나오는 행 ÷ 칸 높이
# 종료 코드 0 (못 그린 초상이 있으면 1, 그릴 수 없는 환경 (--headless) 이면 2)
extends SceneTree

const C := preload("res://core/config.gd")
const Body := preload("res://chars/body.gd")
const PATH := "res://ui/portrait.gd"
const SIZES := [192, 96] # 위 줄 · 아래 줄 (UI 좌표 크기)
const BG := Color(0.08, 0.1, 0.2) # 견본 바탕 (어두운 남색 — HUD 판 바탕과 비슷)
const SOLID := 0.5 # 몸 화소로 세는 알파
const WARM_FRAMES := 3 # 자동 로드 (View·Store) 가 자리 잡을 때까지
const MAX_FRAMES := 3000 # 이만큼 돌고도 못 그리면 그만둠

var P = null # 초상 노드 (ui/portrait.gd)
var PS = null # 그 스크립트
var frames := 0
var out := ""
var want := [] # [캐릭터, 색]
var started := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out = a[i + 1]
	if a.has("--no-ext"):
		Body.use_ext = false


func _process(_d: float) -> bool:
	if DisplayServer.get_name() == "headless":
		printerr("초상: 그릴 수 없는 환경 (--headless)")
		quit(2)
		return true
	frames += 1
	if frames < WARM_FRAMES:
		return false
	if not started:
		started = true
		PS = load(PATH)
		P = PS.new()
		root.add_child(P)
		var i := 0
		for c in C.CHARACTERS:
			want.append([str(c), Color.hex((int(C.PLAYER_PALETTE[i % C.PLAYER_PALETTE.size()]) << 8) | 0xff)])
			i += 1
		for w in want:
			for s in SIZES:
				PS.tex(w[0], w[1], s)
		return false
	var done := 0
	for w in want:
		if SIZES.all(func(s): return P.cache.get(_key(w, s)) != null):
			done += 1
	if done < want.size() and frames < MAX_FRAMES:
		return false
	var big: int = SIZES[0]
	var sheet := Image.create(big * want.size(), big + int(SIZES[1]), false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	var x := 0
	var y := 0
	print("초상 (%s): 캐릭터 fill cx top — %d 칸" % ["외부 끔" if not Body.use_ext else "외부", big]) # 글자는 본문 글꼴 부분 집합 안에서 (tests/test_ui_nodes.gd 가 스크립트 문자열을 훑음)
	for w in want:
		y = 0
		for s in SIZES:
			var t = P.cache.get(_key(w, s))
			if t != null:
				var im: Image = t.get_image()
				im.convert(Image.FORMAT_RGBA8)
				if s == big:
					var m := measure(im)
					print("%-10s fill %.3f cx %.3f top %.3f" % [w[0], m.fill, m.cx, m.top])
				if im.get_width() != s: # UI 배율이 1 보다 크면 더 크게 그려짐 → 견본 칸 크기로
					im.resize(s, s, Image.INTERPOLATE_LANCZOS)
				sheet.blend_rect(im, Rect2i(0, 0, s, s), Vector2i(x, y))
			y += s
		x += big
	if out != "":
		sheet.save_png(out)
	print("초상 저장 %s (%d/%d 명, %d 프레임)" % [out, done, want.size(), frames])
	quit(0 if done == want.size() else 1)
	return true


func _key(w: Array, s: int) -> String:
	return PS.key_of(w[0], w[1], PS.render_px(s, float(root.get_node("View").ui_scale)), false)


# 한 칸의 몸 화소 통계: {fill, cx, top} (몸 화소가 없으면 fill 0 · cx 0.5 · top 1)
static func measure(im: Image) -> Dictionary:
	var w := im.get_width()
	var h := im.get_height()
	var n := 0
	var sx := 0.0
	var top := h
	for iy in h:
		for ix in w:
			if im.get_pixel(ix, iy).a > SOLID:
				n += 1
				sx += ix + 0.5
				top = mini(top, iy)
	return {"fill": float(n) / float(w * h), "cx": (sx / n / w) if n > 0 else 0.5, "top": float(top) / float(h)}

# 착지한 설치 블록 칸 (c11-u2): 던져서 내려앉은 설치 블록 (격자 값 Cells.THROWN) 을 설치 블록 아이템 (world/item_look.gd PARTS.brick) 과 같은 나무 상자로 — 예전엔 단색 칸.
# 코드 메시 하나 (world/item_models.gd build — 정점 색), 재질은 툰 (정점 색·외곽선 없음·위험 액체에 잠기면 물듦). world/grid_view.gd 가 MultiMesh 하나로 그림 (모양 칸이 테마 재질로 갈 때만)
extends RefCounted

const IL := preload("res://world/item_look.gd")
const IM := preload("res://world/item_models.gd")

const SIZE := 1.0 # 긴 변 (칸) — 쇠 기둥 바깥이 칸 경계
const MAX_TRIS := 160
const WOOD := 0xc08a50 # 몸통 = 설치 블록 아이템 주색 (IL.MAIN.brick)
const BAND := 0x8a5a30 # 어두운 나무 띠 (아이템의 띠 색)
const STEEL := 0x70788c # 쇠 모서리 (아이템의 쇠 띠 색)
const POST := 0.07 # 쇠 기둥 굵기
const POST_AT := 0.465 # 쇠 기둥 가운데 (칸 가운데에서 — 바깥 면이 0.5)

# 한 줄 = item_look.gd PARTS 와 같은 꼴 [도형, 치수, 자리, 돌림, 배율, 색]: 몸통 상자 + 가운데 두른 어두운 나무 띠 + 세로 모서리 쇠 기둥 넷
const PARTS := [
	["box", [0.96, 0.96, 0.96], IL.O, IL.O, IL.I, WOOD],
	["box", [0.975, 0.14, 0.975], IL.O, IL.O, IL.I, BAND],
	["box", [POST, 1.0, POST], [POST_AT, 0.0, POST_AT], IL.O, IL.I, STEEL],
	["box", [POST, 1.0, POST], [-POST_AT, 0.0, POST_AT], IL.O, IL.I, STEEL],
	["box", [POST, 1.0, POST], [POST_AT, 0.0, -POST_AT], IL.O, IL.I, STEEL],
	["box", [POST, 1.0, POST], [-POST_AT, 0.0, -POST_AT], IL.O, IL.I, STEEL],
]

static var _mesh: ArrayMesh = null


# 상자 메시 (한 번 만들어 나눠 씀)
static func mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = IM.build(PARTS, SIZE)
	return _mesh


# 상자 재질: 툰 + 정점 색, 외곽선 없음 (쌓인 칸은 외곽선 없음 — 모양 칸과 같음), 스스로 빛나지 않음, 위험 액체에 잠기면 물듦 (블록 재질)
static func material() -> ShaderMaterial:
	var m := IM.material({"outline": false, "hz_tint": true})
	m.set_shader_parameter("color_glow", 0.0) # (IM.material 은 제 빛남 값을 안 덮어씀 — 아이템은 빛나고 쌓인 칸은 안 빛남)
	return m

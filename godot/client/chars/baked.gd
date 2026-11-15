# W7 구운 몸 불러오기: tools/bake-bodies.mjs 가 JS 몸 (client/figure.js buildFigure) 을 구운 assets/models/<캐릭터>.glb + <캐릭터>.json (manifest)
# body.gd build 가 먼저 여기를 봄 — 파일이 있으면 PackedScene 을 꺼내 관절 노드를 이름으로 찾고, 없으면 예전 조립 (chars/data/bodies.bin)
# manifest: nodes [{name, parent, hidden?, noShadow?, dagger?, mat?, batch?}] (부모 번호 < 자식 번호) · mats (gen-bodies 재질 표) · refs · bones · leafStart·batchStart · stats
# (.glb 안 모양·이름 규칙은 tools/bake-bodies.mjs 머리, 계획·남은 일은 chars/BAKE.md)
extends RefCounted

const DIR := "res://assets/models/"

static var _cache := {} # 캐릭터 → {manifest, scene} 또는 null (없음)


# 캐릭터의 구운 몸 (없으면 null). 한 번 읽어 둠 — PackedScene·메시는 몸끼리 같이 씀
static func load_char(char_id: String):
	if _cache.has(char_id):
		return _cache[char_id]
	var out = null
	var mp := DIR + char_id + ".json"
	var gp := DIR + char_id + ".glb"
	if FileAccess.file_exists(mp) and ResourceLoader.exists(gp):
		var m = JSON.parse_string(FileAccess.get_file_as_string(mp))
		var s = load(gp)
		if m is Dictionary and m.get("char") == char_id and s is PackedScene:
			out = {"manifest": m, "scene": s}
	_cache[char_id] = out
	return out


# 구운 몸이 있는 캐릭터
static func has_char(char_id: String) -> bool:
	return load_char(char_id) != null

# G6 건축가 블록: 모습 계산이 JS (shared/bblock-look.js) 와 같은지 (tools/fixtures-fx.mjs → bblocks.json) + 칸이 늘어도 MultiMesh 수 그대로·빠질 칸·터짐 조각
extends RefCounted

const C := preload("res://core/config.gd")
const BL := preload("res://world/bblock_look.gd")
const BB := preload("res://world/bblocks.gd")

var errors: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func near(a: float, b: float, eps := 1e-6) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))


func js():
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/bblocks.json"))


func test_parts_match_js() -> void:
	var d = js()
	for k in BL.KINDS:
		var got := BL.parts(k)
		var want: Array = d.parts[k]
		check(got.size() == want.size(), "%s 부품 수 %d vs JS %d" % [k, got.size(), want.size()])
		for i in mini(got.size(), want.size()):
			var g: Dictionary = got[i]
			var w: Dictionary = want[i]
			var same: bool = g.part == w.part and g.get("mat") == w.get("mat")
			for j in 3:
				same = same and near(g.at[j], w.at[j]) and near(g.size[j], w.size[j])
			check(same, "%s 부품 %d: %s vs JS %s" % [k, i, g, w])


func test_curves_match_js() -> void:
	var d = js()
	for r in d.rise:
		check(near(BL.rise_scale(r[0]), r[1]), "솟기 %s: %s vs JS %s" % [r[0], BL.rise_scale(r[0]), r[1]])
	for r in d.crack:
		check(near(BL.crack_of(r[0]), r[1]), "금 %s: %s vs JS %s" % [r[0], BL.crack_of(r[0]), r[1]])
	for r in d.flash:
		check(near(BL.flash_of(r[0], r[1]), r[2]), "깜빡 %s: %s vs JS %s" % [r, BL.flash_of(r[0], r[1]), r[2]])
	for r in d.big:
		var g := BL.big_prep(r[0], r[1])
		check(near(g.k, r[2].k) and near(g.swell, r[2].swell) and near(g.glow, r[2].glow), "R 준비 %s: %s vs JS %s" % [[r[0], r[1]], g, r[2]])
	for r in d.collapse:
		var g := BL.collapse_at(r[0])
		check(near(g.sz, r[1].sz) and near(g.sink, r[1].sink) and near(g.tilt, r[1].tilt), "무너짐 %s: %s vs JS %s" % [r[0], g, r[1]])
	for r in d.shards:
		check(BL.shard_count(r[0], r[1]) == int(r[2]), "조각 수 %s: %d vs JS %s" % [r, BL.shard_count(r[0], r[1]), r[2]])


func _state(n: int) -> Dictionary:
	var list := []
	var kinds := ["wall", "pad", "third", "big"]
	for i in n:
		list.append({"x": i % 19, "y": (i / 19) % 19, "z": i / 361, "owner": null, "kind": kinds[i % 4], "group": i / 2, "left": 2000 if i % 3 == 0 else 9000})
	return {"field": {"w": 19, "d": 19, "h": 32}, "players": [], "bblocks": list}


# 칸 50개·150개여도 그리는 MultiMesh 수는 같음 (render.js 묶음 그리기와 같은 약속)
func test_mesh_count_constant() -> void:
	var bb := BB.new()
	bb.update(_state(50))
	var m50: int = bb.mesh_count()
	check(bb.skip().size() == 50, "빠질 칸 %d" % bb.skip().size())
	bb.update(_state(150))
	check(bb.mesh_count() == m50, "MultiMesh 수 50칸 %d · 150칸 %d" % [m50, bb.mesh_count()])
	check(bb.pools.wood.n > 0 and bb.pools.plate.n > 0 and bb.pools.strap.n > 0, "판자·빛 판·쇠 띠 있음")
	check(m50 == 7, "부품 묶음 7개 (판자 3·쇠·띠·빛 판·쇠 띠): %d" % m50)
	bb.update(_state(0))
	check(bb.mesh_count() == 0 and bb.skip().is_empty(), "다 사라지면 안 그림")
	bb.free()


# 터짐·무너짐: 차례로 터질 칸이 대기했다가 시각이 오면 조각, 수명 끝은 무너지는 칸으로 남음
func test_blast_and_collapse() -> void:
	var bb := BB.new()
	bb.update(_state(4))
	bb.on_event({"type": "blast", "who": null, "cells": [[0, 0, 0], [1, 0, 0]], "dir": {"x": 1, "y": 0}})
	check(bb.ghosts.size() == 2, "연쇄 대기 %d" % bb.ghosts.size())
	for g in bb.ghosts:
		g.at = 0.0
	bb.update(_state(0))
	check(bb.ghosts.is_empty() and bb.shards.size() == BL.shard_count("wall") + BL.shard_count("pad"), "터진 조각 %d" % bb.shards.size())
	bb.on_event({"type": "bblockGone", "cells": [[2, 0, 0]]})
	bb.update(_state(0))
	check(bb.collapses.size() == 1 and bb.pools.wood.n == 1, "무너지는 칸 %d, 그린 판자 %d" % [bb.collapses.size(), bb.pools.wood.n])
	bb.free()


func test_colors_linear_like_three() -> void:
	# W3: three Color.lerp 는 선형 값끼리 (r152+) — 띠 주인 색 BB_TINT 0.08 이면 0x30 → 0x5c (sRGB 로 섞으면 0x40)
	var c := BL.lerp_lin(Color8(0x30, 0x30, 0x30), Color.WHITE, C.BB_TINT)
	check(absi(c.r8 - 0x5c) <= 1, "띠 주인 색 섞기 선형 (0x30 → 0x%x)" % c.r8)
	check(BL.plate_color(0.0).is_equal_approx(Color.hex((int(C.BB_LOOK.plateCold) << 8) | 0xff)) and BL.plate_color(1.0).is_equal_approx(Color.hex((int(C.BB_LOOK.plateWhite) << 8) | 0xff)), "빛 판 양 끝 색")
	var mid := BL.plate_color(0.5 / 1.4)
	var want := BL.lerp_lin(Color.hex((int(C.BB_LOOK.plateCold) << 8) | 0xff), Color.hex((int(C.BB_LOOK.plateHot) << 8) | 0xff), 0.5)
	check(mid.is_equal_approx(want), "빛 판 가운데 = 선형 섞기")
	var sh := FileAccess.get_file_as_string("res://world/bblock.gdshader")
	check(sh.find("base *= 0.22") > sh.find("vec3 base = g3_lin(c.rgb);"), "금 0.22 는 선형 색에 (three diffuseColor)")
	var src := FileAccess.get_file_as_string("res://world/bblocks.gd")
	check(not src.contains("\"_no_outline\": true"), "쇠 띠도 외곽선 (bblocks.js strap = toon)")
	check(src.contains("mk.block_pulse(mk.neighbors([c])"), "터지면 이웃 블록 들썩 (render.js bbPop)")


func test_stripes_phase_like_canvas() -> void:
	# bblocks.js stripesTexture: x0 = -64 + 20k 평행사변형, 줄 y 의 왼쪽 끝 = x0 + (64 - (y + 0.5)) → 맨 아래 줄 (y 63) 은 x0 + 0.5 ≡ 16.5 (mod 20) 부터 10 칸: x 0..5·16..19
	var img: Image = preload("res://world/bblock_tex.gd").stripes().get_image()
	var row := []
	for x in 20:
		row.append(1 if img.get_pixel(x, 63).r < 0.5 else 0)
	check(row == [1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1], "줄무늬 위상 (아래 줄) %s" % [row])

# 타이틀 무대를 다른 곳에서 쓰는 손잡이 (JS new TitleStage(theme, {...})): B4 대기실 어두운 무대 (world/lobby_dark.gd) 가 ring 모드로 씀.
# S.new(theme, {low, logoW, logoH, camDist, ring, clear, floorZ}) → Node3D (무대 뿌리, 아래는 게임 좌표 — 놓을 자리는 고도 좌표 position 으로)
# .lights [[빛, 원래 에너지]] · .back_light · .light(l, base) · .update(t 초, lit 0~1, px) · 치울 땐 queue_free. 내용은 title_world.gd
extends "res://title/title_world.gd"


func _init(theme := "", opts := {}) -> void:
	if theme != "":
		setup(theme, opts)

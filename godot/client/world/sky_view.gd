# 하늘 시점 (블록 마스터·블록 조종) 순수 계산 (shared/sky-view.js 그대로). 게임 좌표, 수치 C.SKY_VIEW
# 정답 자료: tests/fixtures/sky.json
extends RefCounted

const C := preload("res://core/config.gd")


# 필드 가운데를 비스듬히 (화면 위쪽 = yaw 방향), 판·화면 비율에 맞춰 필드 전체가 들어오는 거리. {pos: [x,y,z], look: [x,y,z], fov (세로, 도), dist}
static func sky_pose(w: float, d: float, yaw: float, aspect := 16.0 / 9.0, v: Dictionary = C.SKY_VIEW) -> Dictionary:
	var look := [w / 2.0, d / 2.0, float(v.lookZ)]
	var r := sqrt(w * w + d * d) / 2.0 + float(v.margin)
	var vf := deg_to_rad(float(v.fov))
	var hf := 2.0 * atan(tan(vf / 2.0) * aspect)
	var dist := (r / sin(minf(vf, hf) / 2.0)) * float(v.fit)
	var el := deg_to_rad(float(v.pitch))
	var ux := cos(yaw)
	var uy := sin(yaw)
	var pos := [look[0] - ux * dist * cos(el), look[1] - uy * dist * cos(el), look[2] + dist * sin(el)]
	return {"pos": pos, "look": look, "fov": float(v.fov), "dist": dist}


# 회전 키: 90도씩 (dir +1 반시계, -1 시계), 0..2π
static func turn_yaw(yaw: float, dir: int) -> float:
	return fposmod(yaw + dir * PI / 2.0, TAU)


# 보이는 yaw 를 목표로 짧은 쪽으로 (k = 이번 프레임 비율)
static func ease_yaw(shown: float, target: float, k: float) -> float:
	var d := target - shown
	d = atan2(sin(d), cos(d))
	return shown + d * k


# 착지 미리보기: 블록 칸을 서버 착지 높이 landZ 로 내림 + 칸마다 기둥 [x, y, 아래 z, 위 z]. piece = 스냅샷 pieces[] 하나
static func landing_preview(piece: Dictionary) -> Dictionary:
	var min_z := INF
	for c in piece.cells:
		min_z = minf(min_z, c[2])
	var cells := []
	var pillars := []
	for c in piece.cells:
		var lz: float = float(piece.landZ) + (c[2] - min_z)
		cells.append([c[0], c[1], lz])
		if c[2] > lz + 1:
			pillars.append([c[0], c[1], lz + 1, c[2]])
	return {"cells": cells, "pillars": pillars, "ok": bool(piece.get("fits", false))}

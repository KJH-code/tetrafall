# 겉모습 갤러리 (tools/gallery.gd) 수치·배치. 게임 수치는 core/config.gd, 여기는 사진 찍는 자리·카메라만
extends RefCounted

const SEED := 20261115 # 전역 난수 (판 코드가 randf 를 쓰는 곳이 있으면 늘 같게)
const WARM_FRAMES := 8 # 장면을 깐 뒤 이만큼 그린 다음 찍음 (재질·셰이더·그림자가 준비될 때까지)
const FIRST_WARM_FRAMES := 20 # 첫 장면·테마가 바뀐 장면은 더 (셰이더 만들기)
const PLAYERS := 8 # 판 크기 기준 인원 (FIELD_SIZES)
# 설정 (user://settings.json 과 상관없이 늘 같게). lowGfx 는 --low 가 정함
const SETTINGS := {"shadows": true, "outline": true, "third": false, "reducedMotion": false, "perf": false}

# ---- 캐릭터 ----
const CHAR_MAP := "flat" # 초원 낮 빛, 지형 없는 빈 바닥 위에 세움
const CHAR_TURNS := [0.0, 40.0, 90.0, 180.0] # 한 장에 나란히: 앞 · 비스듬히 앞 · 옆 · 뒤 (도, 반시계 = 오른쪽 몸이 보임)
const CHAR_FOV := 18.0 # 좁은 시야각으로 멀리서 (원근 왜곡 적게). 외곽선은 화면 굵기라 판과 같음
const CHAR_CAM_PITCH := 5.0 # 카메라가 몸 가운데 높이보다 이만큼 위에서 (도)
const CHAR_SUN_OFF := -35.0 # 카메라 자리 = 해 방위각 + 이만큼 (도): 앞면이 빛을 받되 옆 그늘도 보이게
const CHAR_GAP := 0.2 # 몸과 몸 사이 빈 틈 (칸)
const CHAR_FIT_PASSES := 3 # 몸 방향 ↔ 카메라 거리 맞추기 되풀이
const CHAR_MARGIN := 0.9 # 화면 채움 (1 = 꽉, 작을수록 여백)
const CHAR_POSE_STEPS := 50 # 가만히 선 자세로 이만큼 자세를 돌림 (16ms 씩 — 숨쉬기 위상, portrait.gd 와 같게)
const CHAR_POSE_MS := 16.0

# ---- 맵 ----
# 위에서: 필드 가운데 (높이 look_z) 를 yaw 쪽으로 pitch 만큼 내려다봄. pitch 가 시야각 절반보다 작아 위쪽에 하늘·먼 배경이 들어옴
const MAP_OVER := {"yaw": 62.0, "pitch": 25.0, "fov": 60.0, "margin": 0.93, "look_z": 0.0}
# 눈높이: 가장자리 칸에 선 사람 눈 (EYE_HEIGHT, 시야각 FOV_DEFAULT) 에서 가운데 기둥 위 look_z 를 봄. 앞 clear 칸 안에 눈높이를 넘는 벽이 있는 자리는 건너뜀
const MAP_EYE := {"look_z": 1.0, "clear": 4}
# 설 자리 후보 (0..1 필드 비율, 차례대로 살핌): 변 가운데 넷 → 모서리 넷
const MAP_EYE_SPOTS := [[0.5, 0.0], [0.0, 0.5], [0.5, 1.0], [1.0, 0.5], [0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]

# ---- 블록 ----
# 배치 칸 (u 화면 왼→오, v 카메라에서 멀어지는 쪽, z 위). 카메라는 해가 있는 쪽 변에서 봄 (보이는 면이 빛을 받게)
const PIECES_CAM := {"pitch": 27.0, "fov": 40.0, "margin": 0.92}
const PIECES_LEDGE := {"u": [1, 17], "v": [10, 11], "h": 2} # 뒤 지형 단 (지형 블록 재질과 나란히 보이게)
# 쌓인 칸: [모양, u, v, z, 세운 칸 [[du, dz], ...]]
const PIECES_LANDED := [
	["I", 2, 10, 2, [[0, 0], [1, 0], [2, 0], [3, 0]]],
	["O", 7, 10, 2, [[0, 0], [1, 0], [0, 1], [1, 1]]],
	["T", 10, 10, 2, [[0, 0], [1, 0], [2, 0], [1, 1]]],
	["L", 14, 10, 2, [[0, 0], [1, 0], [0, 1], [0, 2]]],
	["S", 3, 6, 0, [[0, 0], [1, 0], [1, 1], [2, 1]]],
	["Z", 7, 6, 0, [[1, 0], [2, 0], [0, 1], [1, 1]]],
	["J", 11, 6, 0, [[0, 0], [1, 0], [1, 1], [1, 2]]],
]
# 떨어지는 블록 (눕힌 칸 [[du, dv], ...]) 과 그 그림자 (바닥 z 0): 모양, u, v, z, 착지까지 ms (그림자 진하기)
const PIECES_FALL := {"shape": "T", "u": 14, "v": 3, "z": 3, "cells": [[0, 0], [1, 0], [2, 0], [1, 1]], "eta": 900.0}

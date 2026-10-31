# G3 (툰·셰이더·테마) 고도 전용 수치 — JS 값이 있는 건 core/config.gd (C.*) 를 쓰고, 여기는 three 에만 있던 값·고도 변환 값.
extends RefCounted

# three MeshToonMaterial 3단 명암 (client/toon.js TOON_GRADIENT [110, 175, 255] / 255)
const TOON_STEPS := Vector3(110.0 / 255.0, 175.0 / 255.0, 1.0)
# 외곽선 색 (render.js OutlineEffect defaultColor, 선형 값)
const OUTLINE_COLOR := Color(0.08, 0.05, 0.1, 1.0)
# 테마 없는 화면 (예전 노을, render.js 생성자): 하늘빛 위·아래·세기, 해 세기 (색·방향은 C.SUN_COLOR·C.SUN_DIR)
const SUNSET_HEMI := [0xffe2d2, 0x8a90b8, 1.15]
const SUNSET_SUN := 1.25
# 해 그림자: three (render.js bias -0.0008) 와 단위가 달라 고도 값으로 맞춤 — 빛을 비스듬히 받는 옆면이 제 그림자로 어두워지지 않게 (JS 와 나란히 재서 정함)
const SUN_SHADOW_BIAS := 0.1
const SUN_SHADOW_NORMAL_BIAS := 2.0

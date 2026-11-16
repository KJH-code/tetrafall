// 빛 안 받는 몸 조각 (반투명: 유령화·무적 — 예전 표준 반투명과 같이 깊이는 안 씀, 깊이 선은 chars/ghost_depth.gd 가 먼저). 내용은 basic_common.gdshaderinc
shader_type spatial;
render_mode unshaded;
#define BASIC_ALPHA
#include "res://shaders/basic_common.gdshaderinc"

// 툰 재질 (불투명·양면, c7-u1): 천 (망토·코트 자락) 처럼 한 겹인 면의 안쪽도 그림 — toon.gdshader 는 뒷면을 버려서 그 자리에 외곽선 껍질 (보라) 만 보였음.
// 내용은 toon_common.gdshaderinc (TOON_DOUBLE: 뒷면이면 하늘빛 법선을 뒤집음). 쓰는 곳 chars/external.gd double_toon (cfg double)
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;
#define TOON_DOUBLE
#include "res://shaders/toon_common.gdshaderinc"

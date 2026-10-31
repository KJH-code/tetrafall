// 툰 재질 (투명: opacity < 1). 내용은 toon_common.gdshaderinc
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, depth_draw_always; // three 투명 재질 기본 depthWrite = true 와 같게
#define TOON_ALPHA
#include "res://shaders/toon_common.gdshaderinc"

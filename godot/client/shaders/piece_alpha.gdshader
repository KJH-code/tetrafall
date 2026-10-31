shader_type spatial;
render_mode depth_draw_always; // three 투명 재질처럼 깊이를 씀 (안 쓰면 뒤에 그리는 판 빛 무리가 칸 면 위로 칠해져 칸 전체가 조각 색으로 빛남)
#define TOON_ALPHA
#include "res://shaders/piece_common.gdshaderinc"

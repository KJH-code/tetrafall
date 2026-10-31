// 글자 빛 테두리: 뒤집은 껍데기 (앞면을 버림), 테마 테두리 색 × 세기, 안개 안 받음
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;

uniform vec3 col : source_color = vec3(0.0);
uniform float k = 1.0;

void fragment() {
	ALBEDO = col * k;
}

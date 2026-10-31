// 판 빛 무리·빛 터짐 (JS game-light.js VERT/FRAG): 화면을 보는 사각형, 가운데서 바깥으로 pow(1-d, 2.2) × 알파, 더하기.
// 인스턴스 색 = 선형 값 그대로 (three 처럼 색 공간 변환 없이 내보냄 → unshaded ALBEDO 가 되돌아 같은 값), 알파 = 색 a
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float s = length(MODEL_MATRIX[0].xyz);
	c.xy += VERTEX.xy * s;
	POSITION = PROJECTION_MATRIX * c;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(max(0.0, 1.0 - d), 2.2) * COLOR.a;
	if (a < 0.003) discard;
	ALBEDO = COLOR.rgb;
	ALPHA = a;
}

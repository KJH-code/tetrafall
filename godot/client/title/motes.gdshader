// 떠다니는 빛 가루·별 (client/title-world.js motes·stars 셰이더): MultiMesh 판마다 INSTANCE_CUSTOM = (위상, x, y, z). 카메라를 보는 판, 더하기 섞기.
// 위치는 무대 (게임 좌표, z 위) 안: 흔들고 rise 만큼 위로 올라가 맨 위에서 아래로. 크기: three gl_PointSize = size·(화면 높이/2)/-z 와 같은 세상 크기 = size·tan(fov/2)
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0);
uniform float size = 0.1;
uniform float rise = 0.0;
uniform vec2 zr = vec2(0.0, 1.0);
uniform float blink = 0.0;
uniform float move = 1.0;
uniform float star = 0.0;
uniform float lit = 1.0;
uniform float time = 0.0;
uniform float tan_half = 0.466;

varying float v_a;

void vertex() {
	float ph = INSTANCE_CUSTOM.r;
	vec3 q = INSTANCE_CUSTOM.gba; // 무대 로컬 자리 (게임 좌표)
	if (move > 0.5) {
		float t = time;
		q.x += sin(t * 0.45 + ph * 37.0) * 0.9;
		q.y += cos(t * 0.38 + ph * 21.0) * 0.9;
		float h = zr.y - zr.x;
		q.z = zr.x + mod(q.z - zr.x + t * rise * (0.6 + ph) + sin(t * 0.8 + ph * 13.0) * 0.4, h);
		float tw = 0.55 + 0.45 * sin(t * (1.5 + ph * 2.5) + ph * 40.0);
		if (blink > 0.0) tw = pow(max(0.0, sin(t * (0.7 + ph * 0.9) + ph * 30.0)), 3.0);
		float edge = smoothstep(0.0, 1.2, q.z - zr.x) * smoothstep(0.0, 1.2, zr.y - q.z);
		v_a = tw * edge;
	} else {
		v_a = 1.0;
	}
	// 모델 (무대 뿌리) 변환 뒤 뷰 공간에서 판을 펼침
	vec4 mv = MODELVIEW_MATRIX * vec4(q, 1.0);
	float w = size * tan_half * (star > 0.5 ? 1.0 : (0.6 + 0.8 * ph));
	mv.xy += VERTEX.xy * w;
	POSITION = PROJECTION_MATRIX * mv;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0, 0.0, d);
	if (star > 0.5) {
		ALBEDO = vec3(1.0);
		ALPHA = clamp(a * 1.4, 0.0, 1.0);
	} else {
		a = a * a;
		ALBEDO = color * (1.0 + 1.5 * a);
		ALPHA = clamp(a * v_a * lit, 0.0, 1.0);
	}
}

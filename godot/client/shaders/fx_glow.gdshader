// W18 빛 효과 (fx/effects.gd glow MultiMesh 하나): 가산 사각형. 모양은 칸마다 INSTANCE_CUSTOM.x —
// 0 둥근 빛 (불덩이·몸 빛) · 1 십자 별 번쩍 (타격) · 2 빛 고리 (충격파) · 3 불꽃 줄 (길쭉, 머리가 밝음).
// CUSTOM.y = 돌림 (라디안), CUSTOM.z = 가운데 하얗게 (0~1), CUSTOM.w = 가림 (0 = 순수 가산 · 1 = 뒤를 덮음 — 밝은 하늘·잔디 위에서도 보이게).
// 색·세기 = 칸 색 (a 곱). 카메라 바로 앞이면 흐려짐 (fx_math FX_NEAR_FADE 와 같은 거리). 섞기 = 미리 곱한 알파 (가산 + 가림을 한 번에)
// 화면을 보는 자리·길이는 CPU 가 정함 (렌더러와 무관: Compatibility·Forward+·Mobile 같음)
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec2 near_fade = vec2(0.4, 1.6);

varying vec4 cust;
varying float vdist;

void vertex() {
	cust = INSTANCE_CUSTOM;
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float kind = cust.x;
	float a = 0.0;
	float core = pow(clamp(1.0 - r, 0.0, 1.0), 2.2);
	if (kind < 0.5) {
		a = core;
	} else if (kind < 1.5) {
		float ang = atan(p.y, p.x) + cust.y;
		float spike = pow(abs(cos(ang * 2.0)), 14.0) * pow(clamp(1.0 - r, 0.0, 1.0), 0.8);
		float spike2 = pow(abs(cos(ang * 2.0 + 0.785398)), 30.0) * clamp(1.0 - r * 1.5, 0.0, 1.0) * 0.7;
		a = max(core, max(spike, spike2));
	} else if (kind < 2.5) {
		float w = 0.16;
		a = clamp(1.0 - abs(r - (1.0 - w)) / w, 0.0, 1.0);
		a = a * a;
	} else {
		// 길쭉한 줄: p.x 가 길이 (+1 = 머리), p.y 가 폭
		float along = (p.x + 1.0) * 0.5;
		float side = clamp(1.0 - abs(p.y), 0.0, 1.0);
		a = side * side * along * along;
		core = side * along * along * along;
	}
	float fade = clamp((vdist - near_fade.x) / max(near_fade.y - near_fade.x, 1e-4), 0.0, 1.0);
	vec3 col = mix(COLOR.rgb, vec3(1.0), clamp(core * cust.z, 0.0, 1.0));
	float k = clamp(a * COLOR.a * fade, 0.0, 1.0);
	ALBEDO = col * k;
	ALPHA = k * cust.w;
}

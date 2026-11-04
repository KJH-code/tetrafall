// W18 연기·먼지 (fx/effects.gd smoke MultiMesh 하나): 반투명 둥근 뭉치, 가장자리가 울퉁불퉁 (각도별 사인 합 — 텍스처 없음),
// 아래쪽이 어둡게 (빛 없이 입체감). CUSTOM.x = 돌림, CUSTOM.y = 모양 씨앗. 색·투명도 = 칸 색. 카메라 바로 앞이면 흐려짐
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

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
	float ang = atan(p.y, p.x) + cust.x;
	float s = cust.y * 6.2831;
	float edge = 0.78 + 0.08 * sin(ang * 3.0 + s) + 0.06 * sin(ang * 5.0 - s * 1.7) + 0.04 * sin(ang * 7.0 + s * 2.3);
	float a = smoothstep(edge, edge * 0.45, r);
	float shade = mix(0.72, 1.12, clamp(UV.y * -1.0 + 1.0, 0.0, 1.0)); // UV.y 0 = 위
	float fade = clamp((vdist - near_fade.x) / max(near_fade.y - near_fade.x, 1e-4), 0.0, 1.0);
	ALBEDO = COLOR.rgb * shade;
	ALPHA = clamp(a * COLOR.a * fade, 0.0, 1.0);
}

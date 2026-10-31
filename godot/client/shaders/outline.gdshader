// 툰 외곽선 (JS render.js OutlineEffect: 뒤집은 면을 화면 기준 일정 굵기로 밀어냄, 색 [0.08,0.05,0.1]).
// three OutlineEffect calculateOutline 그대로: 클립 좌표에서 (점 - (점 - 법선) 끝 점) 방향으로 thickness × w
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never;

global uniform vec3 g3_fog_color;
global uniform float g3_fog_near;
global uniform float g3_fog_far;

uniform float thickness = 0.0065; // config OUTLINE_THICKNESS
uniform vec4 line_color = vec4(0.08, 0.05, 0.1, 1.0); // three 와 같이 선형 값 (source_color 아님)

uniform bool no_fog = false;

void vertex() {
	vec4 pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 pos2 = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX - NORMAL, 1.0); // three 는 뒤 면이라 법선을 뒤집어 씀 (outlineNormal = -objectNormal)
	vec4 n = normalize(pos - pos2);
	POSITION = pos + n * thickness * pos.w;
}

void fragment() {
	// 고도 Compatibility 는 결과를 sRGB 로 안 바꿈 (toon_common 주석) → 선형 색을 직접 sRGB 로
	vec3 c = max(line_color.rgb, vec3(0.0));
	ALBEDO = mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
	ALPHA = line_color.a;
	if (g3_fog_far > 0.0 && !no_fog) FOG = vec4(g3_fog_color, smoothstep(g3_fog_near, g3_fog_far, -VERTEX.z)); // three 외곽선도 안개
}

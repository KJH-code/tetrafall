// 툰 외곽선 (JS render.js OutlineEffect: 뒤집은 면을 화면 기준 일정 굵기로 밀어냄, 색 [0.08,0.05,0.1]).
// three OutlineEffect calculateOutline 그대로: 클립 좌표에서 (점 - (점 - 법선) 끝 점) 방향으로 thickness × w
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never;

global uniform vec3 g3_fog_color;
global uniform float g3_fog_near;
global uniform float g3_fog_far;
global uniform vec3 g3_outline_far; // W31: x = 굵기가 줄기 시작하는 거리, y = 0 이 되는 (껍질을 떼는) 거리, z = 그 거리에서의 굵기 배율 (시야각 70° 기준 거리, y = 0 이면 끔)

uniform float thickness = 0.0065; // config OUTLINE_THICKNESS
uniform vec4 line_color = vec4(0.08, 0.05, 0.1, 1.0); // three 와 같이 선형 값 (source_color 아님)

uniform bool no_fog = false;
uniform float far_taper = 0.0; // W31: 1 이면 (몸 외곽선) 먼 거리에서 굵기를 줄임 — g3_outline_far. 블록·아이템 외곽선은 0 (그대로)

void vertex() {
	// 해 그림자 지도 (직교 투영) 엔 껍질을 안 그림 (W15): 고도는 next_pass 도 그림자 패스에 그려서 몸·블록 그림자가 껍질 두께만큼 (직교라 그림자 범위의 0.65%) 커지고
	// 그림자 지도에 삼각형이 한 벌 더 들어가던 것. JS OutlineEffect 는 그림자와 따로라 그림자에 외곽선이 없음. 게임 카메라는 다 원근 (직교 카메라 없음)
	vec4 pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 pos2 = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX - NORMAL, 1.0); // three 는 뒤 면이라 법선을 뒤집어 씀 (outlineNormal = -objectNormal)
	vec4 n = normalize(pos - pos2);
	float k = 1.0;
	if (far_taper > 0.5 && g3_outline_far.y > 0.0) {
		float nd = pos.w * PROJECTION_MATRIX[1][1] * 0.70021; // 시야각 70° 로 환산한 거리 (tan 35°)
		k = mix(1.0, g3_outline_far.z, smoothstep(g3_outline_far.x, g3_outline_far.y, nd));
	}
	POSITION = pos + n * thickness * k * pos.w;
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0); // 클립 밖 한 점 → 삼각형이 다 납작해져 안 그려짐
	}
}

void fragment() {
	// 고도 Compatibility 는 결과를 sRGB 로 안 바꿈 (toon_common 주석) → 선형 색을 직접 sRGB 로
	vec3 c = max(line_color.rgb, vec3(0.0));
	ALBEDO = mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
	ALPHA = line_color.a;
	if (g3_fog_far > 0.0 && !no_fog) FOG = vec4(g3_fog_color, smoothstep(g3_fog_near, g3_fog_far, -VERTEX.z)); // three 외곽선도 안개
}

// 바닥 판 (JS world.js floorTexture: 2×2 칸 체크무늬 + 칸 경계 선 + 테마 무늬, 빛나는 금은 발광). 윗면만 무늬, 옆면은 rim 색.
// 캔버스 그림 대신 칸 자리 난수로 같은 무늬를 그림 (자리는 JS 와 다름, 모양·색·밀도는 같게). 칸 = 게임 x·y 1칸 (JS 텍스처 128px 이 2×2 칸)
shader_type spatial;
#define TOON_CUSTOM
#include "res://shaders/toon_common.gdshaderinc"

uniform vec3 f_a; uniform vec3 f_b; uniform vec3 f_rim; // 선형
uniform vec4 f_line; // 선형 색 + 알파
uniform vec3 f_glow; // 선형 (cracks)
uniform int f_paint; // 0 grass · 1 sand · 2 stone · 3 moss · 4 cracks · 5 marble

varying vec3 v_wp;

float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float n21(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 g = vec2(v_wp.x, -v_wp.z); // 게임 x, y
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float chk = mod(cell.x + cell.y, 2.0);
	vec3 base = chk > 0.5 ? f_b : f_a;
	vec3 c = base;
	float glow = 0.0;
	float px = 1.0 / 64.0; // 텍스처 한 칸 = 64px
	if (f_paint == 1) { // sand: 물결 세 줄
		for (int k = 0; k < 3; k++) {
			float y0 = 0.25 + float(k) * 0.25 + (h21(cell + float(k)) - 0.5) * 4.0 * px;
			float y = y0 - 4.0 * px * 4.0 * f.x * (1.0 - f.x) * (1.0 + 0.6 * h21(cell + float(k) + 7.0));
			if (abs(f.y - y) < 0.75 * px && f.x > 4.0 * px && f.x < 1.0 - 4.0 * px) c = base * 0.9;
		}
	} else if (f_paint == 2 || f_paint == 3) { // stone 자갈 점 · moss 이끼 얼룩
		for (int k = 0; k < 14; k++) {
			vec2 q = vec2(h21(cell + float(k) * 1.7), h21(cell + float(k) * 3.1 + 9.0)) * (1.0 - 8.0 * px) + 4.0 * px;
			float r = (f_paint == 3 ? 5.0 + h21(cell + float(k)) * 9.0 : 2.0 + h21(cell + float(k)) * 4.0) * 0.5 * px;
			if (length(f - q) < r) c = base * (f_paint == 3 ? 0.8 + h21(cell - float(k)) * 0.35 : 0.85 + h21(cell - float(k)) * 0.25);
		}
	} else if (f_paint == 4) { // cracks: 꺾인 빛 금 (발광)
		float v = abs(n21(g * 1.6 + 11.0) - 0.5);
		float m = 1.0 - smoothstep(0.006, 0.014, v);
		m *= smoothstep(0.5, 0.62, n21(g * 0.9 + 3.0)); // 칸마다 한 갈래쯤 (JS 1 갈래·1.5px)
		c = mix(c, f_glow, m);
		glow = m;
	} else if (f_paint == 5) { // marble 결
		for (int k = 0; k < 2; k++) {
			float y = mix(h21(cell + float(k)), h21(cell + float(k) + 5.0), f.x) + (n21(vec2(f.x * 3.0, float(k)) + cell) - 0.5) * 0.4;
			if (abs(f.y - y) < 0.5 * px) c = base * 0.86;
		}
	} else { // grass: 풀 자국 (작은 세모, 밝게)
		vec3 lite = mix(base, vec3(1.0), 0.18);
		for (int k = 0; k < 10; k++) {
			vec2 q = vec2(4.0 * px + h21(cell + float(k) * 2.3) * (1.0 - 8.0 * px), 6.0 * px + h21(cell + float(k) * 5.9 + 3.0) * (1.0 - 10.0 * px));
			vec2 d = (f - q) / px; // 세모 (x 0..4, y 0..-5 위로)
			if (d.x > 0.0 && d.x < 4.0 && -d.y > 0.0 && -d.y < 5.0 * (1.0 - abs(d.x - 2.0) / 2.0)) c = lite;
		}
	}
	// 칸 경계 선 (2px, 알파 섞음)
	vec2 e = min(f, 1.0 - f);
	if (min(e.x, e.y) < px) c = mix(c, f_line.rgb, f_line.a);
	vec3 wn = normalize(world_n);
	if (wn.y < 0.5) { c = f_rim; glow = 0.0; }
	v_base = c;
	v_amb = c * toon_hemi(wn) / PI + f_glow * glow;
	g3_hz_apply((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y, v_base, v_amb); // 잠긴 블록 물들임
	ALBEDO = vec3(1.0);
	if (g3_fog_far > 0.0 && !no_fog) FOG = vec4(g3_fog_color, smoothstep(g3_fog_near, g3_fog_far, -VERTEX.z));
	EMISSION = g3_sun_on > 0.5 ? vec3(0.0) : g3_srgb(v_amb);
}

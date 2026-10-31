// 테마 지형 블록 (JS client/blocks.js terrainMaterial 그대로: 주상절리·테마 결). G3 가 가짐.
// MultiMesh 칸마다 INSTANCE_CUSTOM = (이웃 빈 방향 비트, 그늘 비트, 윗면 높낮이, 0) — block_style.gd cell_looks. 메시 = 1×1×1 상자 (g3.gd terrain_mesh)
// 계산은 게임 좌표 (x, y, z위) 로 (JS 와 같은 식): 고도 → 게임 g(), 게임 → 고도 gd() (core/coords.gd 와 같음). 색 값은 전부 선형 (g3.gd 가 바꿔 넣음)
shader_type spatial;
render_mode cull_back;
#define TOON_CUSTOM
#include "res://shaders/toon_common.gdshaderinc"

uniform vec3 tf_top; uniform vec3 tf_side; uniform vec3 tf_rim;
uniform vec3 tf_tint0; uniform vec3 tf_tint1; uniform vec3 tf_tint2; uniform vec3 tf_glow;
uniform float tf_disp; uniform vec2 tf_chamfer; uniform float tf_step;
uniform vec2 tf_blotch; uniform float tf_edge; uniform vec2 tf_height; uniform float tf_vein; uniform float tf_vein_scale;
uniform float tf_mottle; uniform float tf_wear; uniform float tf_top_lift = 1.0;
uniform vec2 tf_grid; uniform float tf_lip; uniform vec2 tf_strata; uniform vec4 tf_brick; uniform float tf_sheen;
uniform float tf_side_shade = 1.0; uniform float tf_ao; uniform float tf_hi; uniform float tf_self;

varying vec3 v_w; varying vec3 v_cell; varying float v_open; varying float v_ao; varying float v_lift;

vec3 g(vec3 v) { return vec3(v.x, -v.z, v.y); }
vec3 gd(vec3 v) { return vec3(v.x, v.z, -v.y); }

float tf_hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float tf_noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(tf_hash(i), tf_hash(i + vec3(1,0,0)), f.x), mix(tf_hash(i + vec3(0,1,0)), tf_hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(tf_hash(i + vec3(0,0,1)), tf_hash(i + vec3(1,0,1)), f.x), mix(tf_hash(i + vec3(0,1,1)), tf_hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float tf_fbm(vec3 p) { return 0.5 * tf_noise(p) + 0.3 * tf_noise(p * 2.03 + 7.1) + 0.2 * tf_noise(p * 4.1 + 3.7); }
float tf_bit(float m, float b) { return mod(floor(m / b + 0.001), 2.0); }

void vertex() {
	vec3 cell = g((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	vec3 position = g(VERTEX);
	vec3 tr = position;
	float open = INSTANCE_CUSTOM.r;
	v_cell = cell; v_open = open; v_ao = INSTANCE_CUSTOM.g; v_lift = INSTANCE_CUSTOM.b * tf_step;
	vec3 w0 = cell + position;
	vec3 ex = vec3(0.0);
	if (position.x > 0.49) ex.x = tf_bit(open, 1.0); else if (position.x < -0.49) ex.x = -tf_bit(open, 2.0);
	if (position.y > 0.49) ex.y = tf_bit(open, 4.0); else if (position.y < -0.49) ex.y = -tf_bit(open, 8.0);
	if (position.z > 0.49) ex.z = tf_bit(open, 16.0); else if (position.z < -0.49) ex.z = -tf_bit(open, 32.0);
	float n_ex = abs(ex.x) + abs(ex.y) + abs(ex.z);
	float open_n = tf_bit(open, 1.0) + tf_bit(open, 2.0) + tf_bit(open, 4.0) + tf_bit(open, 8.0);
	float ch = mix(tf_chamfer.x, tf_chamfer.y, tf_hash(floor(w0 * 2.0 + 0.5) + 3.1)) * (1.0 + 0.25 * open_n);
	if (n_ex > 1.5) tr -= ex * ch;
	if (position.z > 0.49 && tf_bit(open, 16.0) > 0.5) tr.z += v_lift;
	vec3 q = w0 * 1.9;
	tr += (vec3(tf_noise(q), tf_noise(q + 19.7), tf_noise(q + 41.3)) - 0.5) * tf_disp * vec3(1.0, 1.0, 0.6);
	v_w = cell + tr;
	VERTEX = gd(tr);
}

void fragment() {
	vec3 n = normalize(cross(dFdx(v_w), dFdy(v_w)));
	if (dot(n, g(CAMERA_POSITION_WORLD) - v_w) < 0.0) n = -n; // 화면 미분 방향과 상관없이 카메라 쪽
	float up = smoothstep(0.55, 0.85, n.z);
	bool side_face = up < 0.5 && n.z > -0.5;
	vec3 l = v_w - v_cell;
	vec3 an = abs(n);
	vec3 top = tf_top * tf_top_lift;
	float lip_d = tf_lip * (0.55 + 0.9 * tf_noise(vec3(v_w.xy * 3.1, 0.0)));
	bool lip_here = side_face && tf_lip > 0.0 && tf_bit(v_open, 16.0) > 0.5 && l.z > 0.5 + v_lift - lip_d;
	vec3 base = mix(tf_side, top, up);
	if (lip_here) base = top * 0.92;
	if (n.z < -0.5) base = tf_side * 0.6;
	float b1 = tf_fbm(v_w * tf_blotch.x + 5.0);
	float b2 = tf_fbm(v_w * tf_blotch.x * 0.6 + 31.0);
	vec3 tint = mix(mix(tf_tint0, tf_tint1, smoothstep(0.35, 0.65, b1)), tf_tint2, smoothstep(0.55, 0.75, b2));
	base *= mix(vec3(1.0), tint, tf_blotch.y);
	base *= mix(tf_height.x, 1.0, clamp(v_w.z / tf_height.y, 0.0, 1.0));
	if (side_face && !lip_here) {
		if (tf_strata.y > 0.0) {
			float t = v_w.z * tf_strata.x + (tf_noise(v_w * 0.9) - 0.5) * 0.7;
			base *= 1.0 + (tf_hash(vec3(floor(t), 3.7, 1.3)) - 0.5) * 2.0 * tf_strata.y;
			base *= 1.0 - tf_strata.y * 1.6 * (1.0 - smoothstep(0.0, 0.07, fract(t)));
		}
		if (tf_brick.z > 0.0) {
			float u = an.x > an.y ? v_w.y : v_w.x;
			float row = floor(v_w.z / tf_brick.y);
			float uu = u / tf_brick.x + row * 0.5;
			float fu = fract(uu); float fv = fract(v_w.z / tf_brick.y);
			float mortar = min(min(fu, 1.0 - fu) * tf_brick.x, min(fv, 1.0 - fv) * tf_brick.y);
			base *= 1.0 + (tf_hash(vec3(floor(uu), row, an.x > an.y ? 1.0 : 2.0)) - 0.5) * tf_brick.w;
			base *= mix(0.62, 1.0, smoothstep(tf_brick.z * 0.6, tf_brick.z, mortar));
		}
	}
	float dv = 1.0, dt = 1.0, db = 1.0;
	if (an.x < 0.7) { if (tf_bit(v_open, 1.0) > 0.5) dv = min(dv, 0.5 - l.x); if (tf_bit(v_open, 2.0) > 0.5) dv = min(dv, 0.5 + l.x); }
	if (an.y < 0.7) { if (tf_bit(v_open, 4.0) > 0.5) dv = min(dv, 0.5 - l.y); if (tf_bit(v_open, 8.0) > 0.5) dv = min(dv, 0.5 + l.y); }
	if (an.z < 0.7) { if (tf_bit(v_open, 16.0) > 0.5) dt = 0.5 + v_lift - l.z; if (tf_bit(v_open, 32.0) > 0.5) db = 0.5 + l.z; }
	if (up > 0.5) {
		base = mix(base, base * 1.35 + 0.04, tf_wear * (1.0 - smoothstep(0.0, 0.16, dv)));
		vec2 gg = abs(v_w.xy - floor(v_w.xy + 0.5));
		float gw = min(gg.x, gg.y); float aa = fwidth(gw) + 1e-4;
		base *= 1.0 - tf_grid.x * clamp(1.5 - 0.5 * aa / tf_grid.y, 0.0, 1.0) * (1.0 - smoothstep(tf_grid.y - aa, tf_grid.y + aa, gw));
		float da = 1.0;
		if (tf_bit(v_ao, 1.0) > 0.5) da = min(da, 0.5 - l.x);
		if (tf_bit(v_ao, 2.0) > 0.5) da = min(da, 0.5 + l.x);
		if (tf_bit(v_ao, 4.0) > 0.5) da = min(da, 0.5 - l.y);
		if (tf_bit(v_ao, 8.0) > 0.5) da = min(da, 0.5 + l.y);
		float ka = 1.0 - smoothstep(0.0, 0.45, da);
		base *= 1.0 - tf_ao * ka * ka;
	} else if (n.z > -0.5) {
		base *= tf_side_shade;
		base = mix(base, base * 1.25 + 0.03, tf_hi * 0.5 * (1.0 - smoothstep(0.0, 0.1, dv)));
		base = mix(base, base * 1.6 + 0.07, tf_hi * (1.0 - smoothstep(0.0, 0.07, dt)));
		base = mix(base, tf_rim, tf_edge * (1.0 - smoothstep(0.0, 0.16, db)));
		float bit = an.x > an.y ? (n.x > 0.0 ? 16.0 : 32.0) : (n.y > 0.0 ? 64.0 : 128.0);
		if (tf_bit(v_ao, bit) > 0.5) { float ka = 1.0 - smoothstep(0.0, 0.55, l.z + 0.5); base *= 1.0 - tf_ao * ka * ka; }
	}
	base *= 1.0 + (tf_noise(floor(v_w * 3.0) + 0.5) - 0.5) * tf_mottle + (tf_noise(v_w * 0.7 + 2.0) - 0.5) * tf_mottle;
	float glow_amt = 0.0;
	if (tf_vein > 0.0) {
		float v = tf_noise(v_w * vec3(0.9, 0.9, 1.3) * tf_vein_scale) - 0.5;
		float w = tf_noise(v_w * 2.3 * tf_vein_scale + 13.0) - 0.5;
		glow_amt = (1.0 - smoothstep(0.0, 0.035, abs(v))) * smoothstep(-0.1, 0.15, w) * (1.0 - up * 0.6);
		base = mix(base, tf_glow, glow_amt * tf_vein);
	}
	float sheen = tf_sheen > 0.0 ? pow(1.0 - abs(dot(n, normalize(g(CAMERA_POSITION_WORLD) - v_w))), 3.0) * tf_sheen : 0.0;
	vec3 wn = gd(n);
	world_n = wn;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	v_base = base;
	v_amb = base * toon_hemi(wn) / PI + tf_glow * (glow_amt * tf_vein + sheen) + base * tf_self;
	ALBEDO = vec3(1.0);
	if (g3_fog_far > 0.0) FOG = vec4(g3_fog_color, smoothstep(g3_fog_near, g3_fog_far, -VERTEX.z));
	EMISSION = g3_sun_on > 0.5 ? vec3(0.0) : g3_srgb(v_amb);
}

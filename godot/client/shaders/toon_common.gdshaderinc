// 툰 재질 공통 (toon.gdshader 불투명 · toon_alpha.gdshader 투명 이 include). JS client/toon.js = three MeshToonMaterial + 3단 명암 TOON_GRADIENT.
// G3 가 가짐 (godot/PLAN.md 7절).
//
// 색 공간 (고도 4.7 Compatibility, drivers/gles3/shaders/scene.glsl 읽음): 셰이더가 내는 ALBEDO·EMISSION 은 sRGB 로 보고 선형으로 바꾼 뒤 빛을 셈하고
// 끝에 sRGB 로 바꿈 (source_color 값은 그대로 sRGB). 그런데 그림자 있는 해는 '더하기 패스' 라 바탕 패스 (EMISSION·환경빛) 와 따로 sRGB 로 바꿔 더함
// → three (선형으로 다 더하고 한 번 sRGB) 와 다름. 그래서 해가 있으면 하늘빛·발광까지 light() 안에서 선형으로 다 더하고 (ALBEDO = 1, EMISSION = 0)
// 고도가 한 번만 sRGB 로 바꾸게 함. 판 장면의 빛은 해 하나 + 하늘빛 (render.js) — 빛이 여럿이면 하늘빛이 겹쳐 더해짐 (해 없음이면 EMISSION 쪽)
// 직접 빛: 면 방향·빛 방향 내적을 3단으로 끊음 (three getGradientIrradiance: u = NdotL*0.5+0.5 → [110,175,255]/255, 가장 가까운 점), 그림자는 ATTENUATION
// 하늘빛 (three HemisphereLight): 위·아래 색을 법선 높이로 섞음. 해·하늘빛 색·세기는 전역 값 g3_* (선형, g3.gd set_sun·set_hemi)
// three 확산은 색 × 빛 / PI (BRDF_Lambert, 빛 세기는 three 값 그대로)

global uniform vec3 g3_hemi_sky;
global uniform vec3 g3_hemi_ground;
global uniform float g3_hemi_energy;
global uniform vec3 g3_sun; // 해 색 × 세기 (선형)
global uniform float g3_sun_on; // 1 = 해 있음 (light() 가 다 그림), 0 = EMISSION 이 하늘빛만
// 안개 (three Fog: 카메라 깊이로 smoothstep(near, far) 만큼 안개 색과 선형으로 섞음). far <= 0 이면 없음
global uniform vec3 g3_fog_color;
global uniform float g3_fog_near;
global uniform float g3_fog_far;

// 위험에 잠긴 블록 물들임 (JS hazard.js tint: 블록·바닥 재질만, hz_tint 켠 재질). g3_hz = (표면 z, 깊이당 섞기, 닿는 선 띠 세기, 켬)
global uniform vec4 g3_hz;
global uniform vec3 g3_hz_tint; // 선형
global uniform vec3 g3_hz_band; // 선형
global uniform float g3_hz_mode; // 1 = 띠가 빛남 (용암·에너지), 0 = 띠가 어두워짐 (젖음)
uniform bool hz_tint = false;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform vec3 emissive : source_color = vec3(0.0);
uniform float emissive_energy = 1.0;
uniform vec3 toon_steps = vec3(0.43137, 0.68627, 1.0); // g3_config.TOON_STEPS
uniform bool use_vertex_color = false;
uniform bool vertex_color_linear = false; // COLOR 가 이미 선형 (world/scenery.gd 꼭짓점 색)
uniform bool no_fog = false;
// 피부 조각 (batch.gd: UV2.x = 1 인 정점, 정점 색 재질만): 색을 skin_tint 로 섞고 (a = 섞는 양), 발광은 emissive 대신 skin_emissive (JS render.js bodyMat 효과: 경직 깜빡·발광)
uniform vec3 skin_emissive : source_color = vec3(0.0);
uniform vec4 skin_tint : source_color = vec4(0.0); // JS fog: false (먼 배경)
uniform float color_glow = 0.0; // 제 색으로 빛남 (JS 결정·버섯 갓: 발광 += 색 × glow, 인스턴스 색 포함)

varying vec3 world_n;
varying vec3 v_base; // 선형 바탕색
varying vec3 v_amb; // 선형: 하늘빛 + 발광 (빛 방향 없는 몫)

vec3 g3_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 g3_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

// 잠긴 부분은 위험 색으로 섞고 (최종 색 = (1-k) 빛 + k 색 → 바탕·하늘빛 몫을 줄이고 그만큼 더함), 닿는 선 바로 위는 띠. gz = 게임 높이 (고도 월드 y)
void g3_hz_apply(float gz, inout vec3 base, inout vec3 amb) {
	if (g3_hz.w < 0.5) return;
	float d = g3_hz.x - gz;
	if (d > 0.0) {
		float k = clamp(0.35 + d * g3_hz.y, 0.0, 0.85);
		base *= 1.0 - k;
		amb = amb * (1.0 - k) + g3_hz_tint * k;
	} else {
		float hb = (1.0 - smoothstep(0.0, 0.5, -d)) * g3_hz.z;
		if (g3_hz_mode > 0.5) amb += g3_hz_band * hb;
		else { vec3 m = mix(vec3(1.0), g3_hz_band, hb); base *= m; amb *= m; }
	}
}

// 하늘빛 (선형): 월드 법선 wn (고도 좌표)
vec3 toon_hemi(vec3 wn) {
	float up = dot(normalize(wn), vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5;
	return mix(g3_hemi_ground, g3_hemi_sky, up) * g3_hemi_energy;
}

// TOON_CUSTOM: 셰이더가 vertex()·fragment() 를 직접 씀 (terrain.gdshader) — v_base·v_amb·world_n·ALBEDO·FOG·EMISSION 을 아래처럼 채우고 light() 는 이것
#ifndef TOON_CUSTOM
void vertex() {
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 c = albedo;
	if (use_tex) c *= texture(albedo_tex, UV);
	bool skin = use_vertex_color && UV2.x > 0.5;
	if (use_vertex_color && !vertex_color_linear) c *= COLOR;
	if (skin) c.rgb = mix(c.rgb, skin_tint.rgb, skin_tint.a);
	vec3 base = g3_lin(c.rgb);
	if (use_vertex_color && vertex_color_linear) base *= COLOR.rgb;
	vec3 hemi = toon_hemi(world_n);
	v_base = base;
	v_amb = base * hemi / PI + g3_lin(skin ? skin_emissive : emissive) * emissive_energy + base * color_glow;
	if (hz_tint) g3_hz_apply((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y, v_base, v_amb);
	ALBEDO = vec3(1.0);
	if (g3_fog_far > 0.0 && !no_fog) FOG = vec4(g3_fog_color, smoothstep(g3_fog_near, g3_fog_far, -VERTEX.z)); // 고도가 선형으로 섞음 (더하기 패스는 1 - a 를 곱함)
	EMISSION = g3_sun_on > 0.5 ? vec3(0.0) : g3_srgb(v_amb);
#ifdef TOON_ALPHA
	ALPHA = c.a; // 투명 재질만 (ALPHA 를 쓰면 고도는 투명으로 보고 그림자를 안 드리움)
#endif
}
#endif

void light() {
	float u = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float g = u < 1.0 / 3.0 ? toon_steps.x : (u < 2.0 / 3.0 ? toon_steps.y : toon_steps.z);
	// three 는 그림자 지도에 뒷면을 그려서 (shadowSide) 해 반대쪽 면은 제 그림자를 안 받고 3단 중 어두운 단만 — 고도는 그 면도 그림자라 어두워짐 → 그 면은 그림자 무시
	float att = dot(NORMAL, LIGHT) > 0.0 ? ATTENUATION : 1.0;
	DIFFUSE_LIGHT += v_base * g * att * g3_sun / PI + v_amb; // 선형 (고도가 sRGB 로)
}

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

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform vec3 emissive : source_color = vec3(0.0);
uniform float emissive_energy = 1.0;
uniform vec3 toon_steps = vec3(0.43137, 0.68627, 1.0); // g3_config.TOON_STEPS
uniform bool use_vertex_color = false;
uniform bool vertex_color_linear = false; // COLOR 가 이미 선형 (world/scenery.gd 꼭짓점 색)
uniform bool no_fog = false; // JS fog: false (먼 배경)
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
	if (use_vertex_color && !vertex_color_linear) c *= COLOR;
	vec3 base = g3_lin(c.rgb);
	if (use_vertex_color && vertex_color_linear) base *= COLOR.rgb;
	vec3 hemi = toon_hemi(world_n);
	v_base = base;
	v_amb = base * hemi / PI + g3_lin(emissive) * emissive_energy + base * color_glow;
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

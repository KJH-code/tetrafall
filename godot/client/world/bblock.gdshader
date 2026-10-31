// 건축가 블록 판자·쇠 (client/bblocks.js patchCrack 자리): G3 툰 (shaders/toon_common.gdshaderinc 와 같은 빛 계산) + 칸마다 금·하얀 번쩍.
// MultiMesh INSTANCE_CUSTOM.x = 금 0~1 (금 무늬 가리개에서 밝기 < 금 인 곳을 어둡게), .y = 번쩍 (발광으로 더함). 띠·빛 판은 인스턴스 색 (COLOR)
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

global uniform vec3 g3_hemi_sky;
global uniform vec3 g3_hemi_ground;
global uniform float g3_hemi_energy;
global uniform vec3 g3_sun;
global uniform float g3_sun_on;
global uniform vec3 g3_fog_color;
global uniform float g3_fog_near;
global uniform float g3_fog_far;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform vec2 uv_scale = vec2(3.0, 2.0); // 고도 BoxMesh 는 면 6개가 3×2 로 나눠 가짐 → 면마다 텍스처 한 장 (three BoxGeometry 처럼)
uniform sampler2D crack_tex : filter_linear, repeat_enable;
uniform bool use_crack = false;
uniform bool use_vertex_color = false;
uniform bool unlit = false; // 빛 판 (MeshBasicMaterial)
uniform vec3 toon_steps = vec3(0.43137, 0.68627, 1.0);

varying vec3 world_n;
varying vec3 v_base;
varying vec3 v_amb;
varying vec2 v_cf;

vec3 g3_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 g3_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void vertex() {
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_cf = INSTANCE_CUSTOM.xy;
}

void fragment() {
	vec4 c = albedo;
	if (use_tex) c *= texture(albedo_tex, UV * uv_scale);
	if (use_vertex_color) c *= COLOR;
	if (use_crack && texture(crack_tex, UV * vec2(3.0, 2.0)).r < v_cf.x * 0.97) c.rgb *= 0.22; // 0.97: 바탕 (흰 1.0) 은 금이 다 퍼져도 안 어두워짐
	vec3 base = g3_lin(c.rgb);
	float up = dot(normalize(world_n), vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5;
	vec3 hemi = mix(g3_hemi_ground, g3_hemi_sky, up) * g3_hemi_energy;
	v_base = base;
	v_amb = base * hemi / PI + vec3(v_cf.y);
	ALBEDO = unlit ? vec3(0.0) : vec3(1.0);
	if (g3_fog_far > 0.0) FOG = vec4(g3_fog_color, smoothstep(g3_fog_near, g3_fog_far, -VERTEX.z));
	EMISSION = unlit ? c.rgb : (g3_sun_on > 0.5 ? vec3(0.0) : g3_srgb(v_amb));
}

void light() {
	if (unlit) {
		DIFFUSE_LIGHT += vec3(0.0);
	} else {
		float u = dot(NORMAL, LIGHT) * 0.5 + 0.5;
		float g = u < 1.0 / 3.0 ? toon_steps.x : (u < 2.0 / 3.0 ? toon_steps.y : toon_steps.z);
		float att = dot(NORMAL, LIGHT) > 0.0 ? ATTENUATION : 1.0;
		DIFFUSE_LIGHT += v_base * g * att * g3_sun / PI + v_amb;
	}
}

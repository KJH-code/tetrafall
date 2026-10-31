// 빛 안 받는 색 (JS MeshBasicMaterial): 꼭짓점 색 (선형) × 색, 안개 (g3 전역, no_fog 면 끔). G3 가 가짐
shader_type spatial;
render_mode unshaded, shadows_disabled;

global uniform vec3 g3_fog_color;
global uniform float g3_fog_near;
global uniform float g3_fog_far;

uniform vec3 color = vec3(1.0); // 선형
uniform bool use_vertex_color = true; // COLOR 는 선형
uniform bool no_fog = false;

vec3 srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void fragment() {
	vec3 c = color * (use_vertex_color ? COLOR.rgb : vec3(1.0));
	ALBEDO = srgb(c); // 고도가 선형으로 되돌림
	if (g3_fog_far > 0.0 && !no_fog) FOG = vec4(g3_fog_color, smoothstep(g3_fog_near, g3_fog_far, -VERTEX.z));
}

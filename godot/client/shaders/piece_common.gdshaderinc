// 테트리미노 칸 (JS client/piece-look.js PieceLook 그대로): 면 그림 × 조각 색 (인스턴스 COLOR, sRGB) · accent 부품 (UV2.x 1·2 = accent[0]·[1], 그림은 조금만)
// 빛남: glow 제 색 · crack 그림 밝은 금 · fresnel 비스듬한 면 빛 테 · rim 판 빛 테두리. 모양은 assets/pieces/shapes.json (JS pieceGeometry 그대로, g3.gd piece_mesh)
#define TOON_CUSTOM
#include "res://shaders/toon_common.gdshaderinc"

uniform sampler2D face_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 accent0 : source_color = vec3(1.0);
uniform vec3 accent1 : source_color = vec3(1.0);
uniform float glow = 0.0;
uniform float crack = 0.0;
uniform float fresnel = 0.0;
uniform float rim = 0.0;
uniform float opacity = 1.0;

varying float v_acc;

void vertex() {
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_acc = UV2.x;
}

void fragment() {
	vec3 tex = g3_lin(texture(face_tex, UV).rgb);
	vec3 d = g3_lin(albedo.rgb) * tex * g3_lin(COLOR.rgb);
	vec3 tt = mix(vec3(1.0), tex, 0.35);
	d = mix(d, g3_lin(accent0) * tt, 1.0 - step(0.5, abs(v_acc - 1.0)));
	d = mix(d, g3_lin(accent1) * tt, step(1.5, v_acc));
	float nv = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	vec3 e = d * glow + d * crack * smoothstep(0.6, 0.95, tex.r)
		+ mix(d, vec3(1.0), 0.4) * fresnel * pow(nv, 2.5)
		+ mix(d, vec3(1.0), 0.6) * rim * pow(nv, 3.0);
	v_base = d;
	v_amb = d * toon_hemi(world_n) / PI + e + g3_lin(emissive) * emissive_energy;
	g3_hz_apply((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y, v_base, v_amb); // 잠긴 블록 물들임
	ALBEDO = vec3(1.0);
	if (g3_fog_far > 0.0 && !no_fog) FOG = vec4(g3_fog_color, smoothstep(g3_fog_near, g3_fog_far, -VERTEX.z));
	EMISSION = g3_sun_on > 0.5 ? vec3(0.0) : g3_srgb(v_amb);
#ifdef TOON_ALPHA
	ALPHA = opacity * COLOR.a;
#endif
}

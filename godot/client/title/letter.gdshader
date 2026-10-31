// 타이틀 글자 블록 (title-scene.js 글자 재질): 테마 칸 색 (인스턴스 색) + 스스로 빛남 (테마 빛 색) + 닿을 때 번쩍 (INSTANCE_CUSTOM.r) + 지나가는 빛 띠 (무대 x)
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform float base_glow = 0.2; // TITLE_PIECE_GLOW + 테마 pieceGlow
uniform float glow = 0.0;
uniform vec3 glow_col : source_color = vec3(1.0);
uniform float sweep_x = -10000.0;
uniform float sweep_w = 3.0;
// B3 PieceLook (테마 칸 모양·면 그림): use_face 면 면 그림 × 색, accent 부품 (UV2.x 1·2), 금 빛·비스듬한 면 빛 테. 아니면 상자 + 칸 테두리 홈
uniform bool use_face = false;
uniform sampler2D face_tex : filter_linear_mipmap, repeat_enable; // (sRGB 그대로 곱함 — 인스턴스 색과 같은 공간)
uniform vec3 accent0 = vec3(1.0);
uniform vec3 accent1 = vec3(1.0);
uniform float crack = 0.0;
uniform float fresnel = 0.0;

varying float v_flash;
varying float v_wx;
varying vec3 v_loc;
varying float v_acc;

void vertex() {
	v_flash = INSTANCE_CUSTOM.r;
	v_wx = INSTANCE_CUSTOM.g + VERTEX.x * INSTANCE_CUSTOM.b; // 무대 x (칸 가운데 + 칸 안 자리)
	v_loc = VERTEX;
	v_acc = UV2.x;
}

void fragment() {
	// 칸 테두리 홈 (테마 칸 모양 대신 — 칸마다 블록으로 읽히게): 면 위 두 축 중 큰 쪽이 가장자리면 어둡게
	vec3 a = abs(v_loc) * 2.0;
	float hi = max(a.x, max(a.y, a.z));
	float lo = min(a.x, min(a.y, a.z));
	float mid = a.x + a.y + a.z - hi - lo;
	float seam = use_face ? 0.0 : smoothstep(0.72, 0.97, mid);
	vec3 c = COLOR.rgb * (1.0 - 0.6 * seam);
	vec3 extra = vec3(0.0);
	if (use_face) {
		vec3 tex = texture(face_tex, UV).rgb;
		vec3 tt = mix(vec3(1.0), tex, 0.35);
		c = COLOR.rgb * tex;
		c = mix(c, accent0 * tt, 1.0 - step(0.5, abs(v_acc - 1.0)));
		c = mix(c, accent1 * tt, step(1.5, v_acc));
		float nv = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
		extra = c * crack * smoothstep(0.6, 0.95, tex.r) + mix(c, vec3(1.0), 0.4) * fresnel * pow(nv, 2.5);
	}
	ALBEDO = c;
	ROUGHNESS = 0.45;
	float sw = exp(-pow((v_wx - sweep_x) / sweep_w, 2.0));
	EMISSION = extra + (c * base_glow + mix(c, glow_col, 0.6) * glow + vec3(1.0) * (v_flash * 1.6 + sw * 0.55 * glow)) * (1.0 - 0.5 * seam);
}

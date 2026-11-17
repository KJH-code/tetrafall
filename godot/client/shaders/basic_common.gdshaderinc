// 빛 안 받는 몸 조각 공통 (구운·코드 몸의 눈 흰자·눈동자·빛나는 조각 — chars/body.gd 재질 kind "basic", G3.basic_material).
// 예전엔 빛 안 받는 표준 재질 (StandardMaterial3D) 이었음 — 색은 그때와 같음 (albedo = sRGB 색, 정점 색도 sRGB 로 읽음).
// c8-fix F2: 표준 재질은 가까운 몸 깎기 (toon_common near_cut) 를 못 받아, 눈앞에서 몸은 점점이 빠지는데 눈알 둘만 불투명하게 떠 있었음
// → 툰 몸과 같은 조건·같은 식·같은 화소 난수 (FRAGCOORD) 로 버림 = 같은 화소에서 몸과 같이 빠짐
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false; // 합친 메시 (body._merge): 색은 정점 색 (sRGB)
uniform bool local_light = false; // 툰 재질과 같은 이름 (G3.toon_local_light 가 켬): 제 빛을 가진 몸 (1인칭 팔·초상·대기실 큰 캐릭터) 은 안 깎음. 빛 계산엔 안 씀 (빛 안 받는 재질)
uniform vec2 near_cut = vec2(0.0); // toon_common near_cut 과 같은 값 — x m 안은 다 버리고 y m 까지 점점 덜 (y = 0 이면 끔, 기본)
uniform float near_keep = 1.0; // toon_common near_keep 과 같은 값 (c10-fix F1 몸 옅게: 남길 화소 비율 상한, 1 = 끔)

// toon_common near_ign 과 같은 식
float near_ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	if (use_vertex_color) {
		// 표준 재질 vertex_color_is_srgb 와 같은 변환 (sRGB → 선형)
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
}

void fragment() {
	if (near_cut.y > 0.0 && !local_light && PROJECTION_MATRIX[3][3] < 0.5) {
		float nk = clamp((length(VERTEX) - near_cut.x) / (near_cut.y - near_cut.x), 0.0, 1.0);
		if (near_ign(FRAGCOORD.xy) >= nk) discard;
	}
	// c10-fix F1 몸 옅게 (near_keep): 같은 화소 난수 — 위 깎기와 합치면 남는 화소 = 난수 < min(nk, near_keep). 같은 조건 (원근 투영 · 제 빛 가진 몸 아님)
	if (near_keep < 1.0 && !local_light && PROJECTION_MATRIX[3][3] < 0.5 && near_ign(FRAGCOORD.xy) >= near_keep) discard;
	vec4 c = albedo;
	if (use_vertex_color) c *= COLOR;
	ALBEDO = c.rgb;
#ifdef BASIC_ALPHA
	ALPHA = c.a;
#endif
}

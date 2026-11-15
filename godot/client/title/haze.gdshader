// 넓은 빛 안개 (W8, JS UnrealBloomPass 의 가장 넓은 단계 흉내): 고도 Compatibility 글로는 단계 세기 (glow_levels) 를 무시해 화면 1/32 보다 넓게 번지지 않음
// → 3D 만 그려진 화면을 밉맵 (lod) 으로 읽어 두 고리 17곳 (반지름 rad, 2·rad — 화면 높이 비율) 평균을 더함: 밉 단계 수가 모자라도 화면 전체로 고르게 번짐.
// 메뉴 판 (UI) 아래 층이라 글자는 안 흐림
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.5;
uniform float lod = 5.0;
uniform float rad = 0.12;
uniform float thr = 0.0;

void fragment() {
	vec2 asp = vec2(SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y, 1.0); // 고리를 화면에서 둥글게 (x 는 화면 높이 기준)
	vec3 acc = textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.2;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398 + 0.3927;
		vec2 d = vec2(cos(a), sin(a)) * asp * rad;
		acc += textureLod(screen_tex, SCREEN_UV + d, lod).rgb * 0.06;
		acc += textureLod(screen_tex, SCREEN_UV + d * 2.0, lod).rgb * 0.04;
	}
	// 스크린 섞기 (밝은 곳은 덜 더함: 결과 = 바탕 + 안개 × (1 − 바탕)) — 가까운 버섯 갓처럼 이미 밝은 곳이 하얗게 타지 않게
	vec3 src = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 hz = max(acc - vec3(thr), vec3(0.0)) * strength;
	COLOR = vec4(hz * clamp(vec3(1.0) - src, 0.0, 1.0), 1.0);
}

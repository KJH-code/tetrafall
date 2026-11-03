// 넓은 빛 안개 (W8, JS UnrealBloomPass 의 가장 넓은 단계 흉내): 고도 Compatibility 글로는 단계 세기 (glow_levels) 를 무시해 화면 1/32 보다 넓게 번지지 않음
// → 3D 만 그려진 화면을 밉맵 높은 단계 (아주 흐림) 로 읽어 문턱 넘는 빛만 더함. 메뉴 판 (UI) 아래 층이라 글자는 안 흐림
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.5;
uniform float lod = 6.0;
uniform float thr = 0.0;

void fragment() {
	vec3 a = textureLod(screen_tex, SCREEN_UV, lod).rgb;
	vec3 b = textureLod(screen_tex, SCREEN_UV, lod - 1.5).rgb;
	vec3 c = max(a * 0.6 + b * 0.4 - vec3(thr), vec3(0.0));
	COLOR = vec4(c * strength, 1.0);
}

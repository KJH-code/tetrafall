// 거울 바닥 (three Reflector 자리): 반사 카메라 (좌우를 뒤집어 그린 판) 화면을 그대로, 테마 바닥 색을 곱함
shader_type spatial;
render_mode unshaded, fog_disabled;

uniform sampler2D refl : source_color, filter_linear;
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	ALBEDO = texture(refl, vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y)).rgb * tint;
}

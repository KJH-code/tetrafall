// 판 가장자리 어둠 (JS game-light.js: CSS radial-gradient(ellipse at center, 투명 inner%, color 100%) — 크기 farthest-corner)
shader_type canvas_item;

uniform vec4 color = vec4(0.0, 0.0, 0.0, 0.5); // rgb + 끝 알파
uniform float inner = 0.5;

void fragment() {
	float t = length((UV - 0.5) * 2.0) / sqrt(2.0); // 모서리 = 1
	COLOR = vec4(color.rgb, color.a * clamp((t - inner) / (1.0 - inner), 0.0, 1.0));
}

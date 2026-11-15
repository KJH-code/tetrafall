// 위험 화면 가장자리 경고 (JS client/hazard.js overlay 그대로): 가로 1.25 늘린 타원 가장자리 + 아래쪽 (발 쪽) 조금 더, 맥동
shader_type canvas_item;

uniform vec3 color = vec3(1.0, 0.3, 0.1); // 테마 hazard.vignette (sRGB 그대로 — three 는 선형으로 들고 colorspace_fragment 로 되돌려 같은 값)
uniform float k = 0.0; // 세기 (vignetteStrength 를 부드럽게 따라감)
uniform float time = 0.0; // 초 (hazard.js this.t)

void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.25, 1.0);
	float e = smoothstep(0.42, 0.8, length(d));
	float beat = 0.8 + 0.2 * sin(time * (4.0 + k * 6.0));
	float bottom = smoothstep(0.3, 0.0, 1.0 - UV.y) * 0.35; // three vUv.y 0 = 아래 (고도 UV.y 0 = 위)
	COLOR = vec4(color, clamp((e + bottom) * k * beat, 0.0, 1.0));
}

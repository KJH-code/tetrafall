// 하늘 구 (JS render.js skyDome, 맵 테마는 world.js apply 가 값을 바꿈): 지평선 → 중간 → 꼭대기 색, 지평선 아래, 해 둘레 번짐·원반, 별 (밤 테마).
// three 셰이더는 색을 sRGB 로 안 바꾸고 선형 값을 그대로 내보냄 (colorspace_fragment 없음) → 여기도 선형 값을 그대로 (고도는 ALBEDO 를 sRGB 로 보고
// 선형 → sRGB 로 되돌려서 숫자가 그대로 나옴). 방향은 게임 좌표 (x, y, z위) 로 바꿔 셈 (별 자리까지 JS 와 같게)
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec3 top;
uniform vec3 mid;
uniform vec3 horizon;
uniform vec3 below;
uniform vec3 sun_dir = vec3(-0.55, 0.62, 0.32); // 게임 좌표, 정규화
uniform vec3 glow = vec3(1.0, 0.65, 0.35);
uniform vec3 disc = vec3(1.0, 0.93, 0.75);
uniform float disc_size = 0.0005;
uniform float stars = 0.0;

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(vec3(v_dir.x, -v_dir.z, v_dir.y)); // 고도 → 게임 (core/coords.gd game())
	float h = clamp(d.z, -1.0, 1.0);
	vec3 c = h < 0.25 ? mix(horizon, mid, smoothstep(0.0, 0.25, h)) : mix(mid, top, smoothstep(0.25, 0.85, h));
	if (h < 0.0) c = mix(horizon, below, smoothstep(0.0, -0.4, h));
	float s = max(dot(d, sun_dir), 0.0);
	if (stars > 0.0) {
		vec3 g = floor(d * 220.0);
		float hs = fract(sin(dot(g, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		c += vec3(step(0.9972, hs) * stars * smoothstep(0.04, 0.35, h) * (0.5 + 0.5 * fract(hs * 91.0)));
	}
	c += glow * pow(s, 8.0) * 0.45;
	c = mix(c, disc, smoothstep(1.0 - disc_size - 0.001, 1.0 - disc_size, s));
	ALBEDO = c;
}

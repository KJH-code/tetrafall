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
// C6 지평선 띠: 고도각 h 0~0.35 에 잡음으로 물결치는 부드러운 띠 2단 (텍스처 없음 — 해시 값 잡음 2옥타브). 색은 horizon·mid 로만 만듦 →
// 판 빛 (game_light.gd _paint_sky) 이 그 둘을 낮추면 띠도 같이 어두워짐. 값은 world/theme_tune.gd (sky_band), 그래픽 낮춤이면 band_k = 0 (잡음도 안 셈)
uniform float band_k = 0.0; // 띠 세기 (0 = 없음)
uniform float band_glow = 0.0; // 아랫단에 glow 빛깔 섞기 (밤 테마. 밝기는 horizon 밝기로 맞춤)
// 띠 색 대비 (c6 리뷰 F4): 지평선·중간 색이 이미 부드럽게 이어지는 테마 (하늘 성) 는 기본 띠 색이 바탕 기울기에 묻힘 → 테마마다 (theme_tune.gd SKY_BAND_THEME).
uniform float band_mix = 0.4; // 윗단 색 = mix(horizon, mid, 이 값). 작을수록 지평선 색 쪽 (중간 색 바탕과 더 갈림)
uniform float band_lift = 0.0; // 아랫단 색을 이만큼 밝게 (× (1 + 값))

const vec2 BAND_H = vec2(0.09, 0.22); // 아랫단·윗단 위 끝 높이 (h)
const float BAND_WAVE = 0.11; // 끝이 물결치는 폭 (h)
const float BAND_SOFT = 0.03; // 끝 부드러움 (h)
const vec2 BAND_FREQ = vec2(2.6, 6.2); // 잡음 두 옥타브 (방위 원 위 주파수)
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

varying vec3 v_dir;

float band_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float band_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(band_hash(i), band_hash(i + vec2(1.0, 0.0)), f.x), mix(band_hash(i + vec2(0.0, 1.0)), band_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(vec3(v_dir.x, -v_dir.z, v_dir.y)); // 고도 → 게임 (core/coords.gd game())
	float h = clamp(d.z, -1.0, 1.0);
	vec3 c = h < 0.25 ? mix(horizon, mid, smoothstep(0.0, 0.25, h)) : mix(mid, top, smoothstep(0.25, 0.85, h));
	if (h < 0.0) c = mix(horizon, below, smoothstep(0.0, -0.4, h));
	if (band_k > 0.0 && h > -0.1 && h < 0.4) { // h > 0.4 는 예전 식 그대로
		vec2 q = normalize(d.xy); // 방위 (원 위를 돌아 이음매 없음)
		float n = band_noise(q * BAND_FREQ.x + 3.7) * 0.65 + band_noise(q * BAND_FREQ.y + 11.3) * 0.35 - 0.5;
		float fade = smoothstep(-0.1, 0.0, h) * (1.0 - smoothstep(0.35, 0.4, h)) * band_k;
		float e2 = BAND_H.y + n * BAND_WAVE;
		float e1 = BAND_H.x + n * BAND_WAVE * 0.5;
		vec3 lowc = mix(horizon, glow * (dot(horizon, LUMA) / max(dot(glow, LUMA), 0.001)), band_glow);
		c = mix(c, mix(horizon, mid, band_mix), (1.0 - smoothstep(e2 - BAND_SOFT, e2 + BAND_SOFT, h)) * fade); // 윗단: 지평선과 중간 사이 색
		c = mix(c, lowc * (1.0 + band_lift), (1.0 - smoothstep(e1 - BAND_SOFT, e1 + BAND_SOFT, h)) * fade); // 아랫단: 지평선 색 (+ glow 빛깔)
	}
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

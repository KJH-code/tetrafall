// 위험 액체 빛 — toon_common.gdshaderinc·world/bblock.gdshader 가 include (그 앞에 uniform toon_steps 가 있어야 함)
// 위험 액체 빛 (JS hazard.js PointLight(색, 세기, LAVA_LIGHT_RANGE, 1.4)): g3_hz_lp = (고도 자리 xyz, three 세기), g3_hz_lc = (선형 색, 거리), g3_hz_ld = 감쇠 지수.
// 고도 OmniLight 는 안 씀 — 툰 light() 가 빛마다 해·하늘빛을 겹쳐 더해 (대기실 무대 빛은 그걸 전제로 맞춤) 위험 근처가 위험 색 없이 밝아지기만 했음 (W3)
global uniform vec4 g3_hz_lp;
global uniform vec4 g3_hz_lc;
global uniform float g3_hz_ld;
// 재질마다 끄기: 1인칭 팔·초상·대기실 큰 캐릭터는 자기 SubViewport 장면인데 전역 값은 모든 장면에 같이 걸림 → 끔 (JS viewmodel·portrait 는 따로 된 scene 이라 위험 빛을 안 받음)
uniform bool hz_light = true;

// 위험 빛 (선형, 바탕색을 곱하기 전): three getDistanceAttenuation (1 / max(d^decay, 0.01) × (1 - (d/거리)^4)^2) × 툰 3단 (법선·빛 방향) × 색 × 세기 / π
vec3 g3_hz_light(vec3 wp, vec3 wn) {
	if (!hz_light || g3_hz_lp.w <= 0.0) return vec3(0.0);
	vec3 d = g3_hz_lp.xyz - wp;
	float dist = length(d);
	float w = dist / g3_hz_lc.w;
	w = clamp(1.0 - w * w * w * w, 0.0, 1.0);
	float fall = w * w / max(pow(dist, g3_hz_ld), 0.01);
	float u = dot(normalize(wn), d / max(dist, 1e-4)) * 0.5 + 0.5;
	float g = u < 1.0 / 3.0 ? toon_steps.x : (u < 2.0 / 3.0 ? toon_steps.y : toon_steps.z);
	return g3_hz_lc.rgb * (g3_hz_lp.w * fall * g / PI);
}

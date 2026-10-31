// 인스턴스 색 그대로 빛나는 재질 (three MeshStandardMaterial emissive 흰색 × diffuseColor: 수정 결정·버섯 갓)
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform float glow = 0.5;
uniform float rough = 0.5;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = rough;
	EMISSION = COLOR.rgb * glow;
}

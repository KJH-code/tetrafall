// 반투명 몸 깊이 선 (W35): 반투명 (유령화·무적) 몸은 한 메시 안 삼각형이 정렬 없이 그려져 안쪽 (먼 쪽) 부분이 앞 부분과 섞여 보였음.
// 이 재질을 먼저 그려 (색 없이 깊이만 씀) 몸의 가장 앞 면만 깊이를 남기고, next_pass 의 반투명 툰 재질이 그 앞 면만 칠함 (깊이 같음 통과).
// 색·그림자·외곽선 영향 없음: ALPHA 0 + shadows_disabled, 반투명 몸은 원래 그림자·외곽선이 없음
shader_type spatial;
render_mode unshaded, depth_draw_always, shadows_disabled, fog_disabled, cull_back;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.004; // 0 이면 일부 렌더러가 깊이도 안 씀 (버림) — 거의 안 보이는 값
}

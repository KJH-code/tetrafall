# 반투명 몸 깊이 선 묶음 (W35, shaders/ghost_depth.gdshader): 반투명 재질 하나를 받아 [깊이만 쓰는 재질 → 그 재질] 로 이어 붙인 재질을 돌려줌.
# 이어 붙인 재질은 반투명 재질마다 하나 (칸 쪽 dict 에 기억). 몸 색·발광 값은 원래 (안쪽) 재질에 그대로 줌 — with_prepass 는 그리는 자리 (material_override) 에만 씀
extends RefCounted

const SHADER := preload("res://shaders/ghost_depth.gdshader")


static func with_prepass(alpha: Material) -> Material:
	if alpha == null:
		return null
	var pre := ShaderMaterial.new()
	pre.shader = SHADER
	pre.render_priority = alpha.render_priority # 같은 순서 안에서 먼저 (next_pass 가 뒤)
	pre.next_pass = alpha
	return pre


# 부위 칸 (holder = body.drawn 한 칸·external parts 한 칸, "alpha" 에 반투명 재질) 마다 한 번만 만들어 기억 — 매 프레임 새로 만들지 않음.
# 재질 안에 기억하면 (meta) 서로 가리켜 (순환) 지워지지 않으므로 칸 쪽에 둠
static func wrap_in(holder: Dictionary) -> Material:
	if not holder.has("ghost_w") or holder.ghost_w.next_pass != holder.alpha:
		holder["ghost_w"] = with_prepass(holder.alpha)
	return holder.ghost_w


# 그리는 재질 → 안쪽 반투명 재질 (깊이 선으로 감싼 것이면 next_pass, 아니면 그대로). 재질 값을 읽고 쓰는 코드·테스트가 씀
static func inner(m: Material) -> Material:
	if m is ShaderMaterial and (m as ShaderMaterial).shader == SHADER:
		return m.next_pass
	return m

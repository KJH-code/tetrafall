# G2 캐릭터 몸 (PLAN 7절): World (world/bodies.gd) 가 사람마다 make_body(char, color) 로 몸을 만들고
# 몸 노드의 pose(p, now_ms) (매 프레임) · on_event(e) (서버 이벤트) 를 부름. 원본 client/figure.js·render.js (몸 부분)
extends RefCounted

const Body := preload("res://chars/body.gd")


# char_id = 캐릭터 id (tank·ninja…, 없으면 보통 몸), color = 피부 (플레이어·팀 색)
static func make_body(char_id: String, color: Color) -> Node3D:
	var b := Body.new()
	b.build(char_id, color)
	return b

# 테트리미노 7종 (shared/pieces.js 그대로). xy 평면에 눕힌 1칸 두께, 수직축 회전만
extends RefCounted

const SHAPES := {
	"I": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	"O": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"T": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
	"S": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"Z": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
	"J": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	"L": [Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
}
const SHAPE_NAMES := ["I", "O", "T", "S", "Z", "J", "L"]
const CELL_TERRAIN := 1
const CELL_SHAPE_BASE := 10


static func cell_of_shape(shape: String) -> int:
	var i := SHAPE_NAMES.find(shape)
	return CELL_SHAPE_BASE + i if i >= 0 else 3


static func _normalize(cells: Array) -> Array:
	var mn := Vector2i(1 << 30, 1 << 30)
	for c in cells:
		mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
	var out := []
	for c in cells:
		out.append(c - mn)
	return out


# 시계방향 90도 회전을 rot 번
static func rotated_cells(shape: String, rot: int) -> Array:
	var cells: Array = SHAPES[shape].duplicate()
	var r := ((rot % 4) + 4) % 4
	for i in r:
		var next := []
		for c in cells:
			next.append(Vector2i(c.y, -c.x))
		cells = _normalize(next)
	return cells


# 조각의 폭/깊이
static func footprint(cells: Array) -> Vector2i:
	var f := Vector2i.ZERO
	for c in cells:
		f = Vector2i(maxi(f.x, c.x + 1), maxi(f.y, c.y + 1))
	return f

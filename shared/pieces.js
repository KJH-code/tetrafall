// 테트리미노 7종. xy 평면에 눕힌 1칸 두께 조각. 수직축 회전만 한다.
// 각 모양은 [dx, dy] 셀 목록. 회전 결과는 항상 min dx = min dy = 0 으로 정규화한다.

export const SHAPES = {
  I: [[0, 0], [1, 0], [2, 0], [3, 0]],
  O: [[0, 0], [1, 0], [0, 1], [1, 1]],
  T: [[0, 0], [1, 0], [2, 0], [1, 1]],
  S: [[1, 0], [2, 0], [0, 1], [1, 1]],
  Z: [[0, 0], [1, 0], [1, 1], [2, 1]],
  J: [[0, 0], [0, 1], [1, 1], [2, 1]],
  L: [[2, 0], [0, 1], [1, 1], [2, 1]],
};

export const SHAPE_NAMES = Object.keys(SHAPES);

// 격자 칸 값: 0 = 빈칸, 0 이 아니면 단단함. 값은 그 칸을 남긴 블록 종류 (화면에서 색으로 구분)
export const CELL = { TERRAIN: 1, BUILD: 2, THROWN: 3, SHAPE_BASE: 10, GHOST_BASE: 20 }; // GHOST_BASE + 자리(slot): 유령 투하 1칸 블록 (떨어뜨린 사람 색)
export function cellOfShape(shape) {
  const i = SHAPE_NAMES.indexOf(shape);
  return i < 0 ? CELL.THROWN : CELL.SHAPE_BASE + i;
}

function normalize(cells) {
  let minX = Infinity;
  let minY = Infinity;
  for (const [x, y] of cells) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
  }
  return cells.map(([x, y]) => [x - minX, y - minY]);
}

// 수직축 기준 시계방향 90도 회전을 rot 번 적용한 셀 목록
export function rotatedCells(shape, rot) {
  let cells = SHAPES[shape].map(([x, y]) => [x, y]);
  const r = ((rot % 4) + 4) % 4;
  for (let i = 0; i < r; i++) {
    cells = normalize(cells.map(([x, y]) => [y, -x]));
  }
  return cells;
}

// 조각의 폭/깊이
export function footprint(cells) {
  let w = 0;
  let d = 0;
  for (const [x, y] of cells) {
    if (x + 1 > w) w = x + 1;
    if (y + 1 > d) d = y + 1;
  }
  return { w, d };
}

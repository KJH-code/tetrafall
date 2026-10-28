// 타이틀 화면 로고 계산: three.js·DOM 없는 순수 계산 — client/title-scene.js 가 그리고 test/title.test.js 가 검증한다.
// 글자(config TITLE_TEXT) → 5×7 복셀 칸 → 붙은 칸 4개 이하 조각(테트리미노처럼)으로 나눔 → 아래 줄부터 떨어지는 순서·시각 → 시각마다 높이.
import { CONFIG as C } from './config.js';

// 5×7 글꼴 (위 줄부터, '#' = 칸). 대문자·숫자·몇 기호
const FONT = {
  A: ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  B: ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
  C: ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
  D: ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
  E: ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
  F: ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
  G: ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.###.'],
  H: ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  I: ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '#####'],
  J: ['..###', '...#.', '...#.', '...#.', '#..#.', '#..#.', '.##..'],
  K: ['#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#'],
  L: ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
  M: ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'],
  N: ['#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#', '#...#'],
  O: ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  P: ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
  Q: ['.###.', '#...#', '#...#', '#...#', '#.#.#', '#..#.', '.##.#'],
  R: ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
  S: ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
  T: ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
  U: ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  V: ['#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
  W: ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '##.##', '#...#'],
  X: ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
  Y: ['#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..'],
  Z: ['#####', '....#', '...#.', '..#..', '.#...', '#....', '#####'],
  0: ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
  1: ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  2: ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
  3: ['####.', '....#', '....#', '.###.', '....#', '....#', '####.'],
  4: ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
  5: ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
  6: ['.###.', '#....', '#....', '####.', '#...#', '#...#', '.###.'],
  7: ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
  8: ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
  9: ['.###.', '#...#', '#...#', '.####', '....#', '....#', '.###.'],
  '!': ['..#..', '..#..', '..#..', '..#..', '..#..', '.....', '..#..'],
  '-': ['.....', '.....', '.....', '.###.', '.....', '.....', '.....'],
  ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
};
export const GLYPH_W = 5;
export const GLYPH_H = 7;

// 글자 → 칸 [{ x, y }] (x 는 왼쪽부터, y 는 아래부터 = 0). 글자 사이 1칸. 모르는 글자는 빈칸
export function titleCells(text, gap = 1) {
  const cells = [];
  let ox = 0;
  for (const ch of String(text).toUpperCase()) {
    const g = FONT[ch] || FONT[' '];
    g.forEach((row, r) => {
      for (let c = 0; c < GLYPH_W; c++) if (row[c] === '#') cells.push({ x: ox + c, y: GLYPH_H - 1 - r });
    });
    ox += GLYPH_W + gap;
  }
  return { cells, width: Math.max(0, ox - gap), height: GLYPH_H };
}

// 칸 → 조각: 아래 줄·왼쪽부터 아직 안 쓴 칸에서 시작해 붙은 칸(상하좌우)을 넓이 우선으로 최대 size 개 묶음.
// 조각마다 shape (색 이름: 테트리미노 7종을 차례로), cells, 바닥 높이 minY
export function titlePieces(cells, size = 4, shapes = ['I', 'O', 'T', 'S', 'Z', 'J', 'L']) {
  const key = (x, y) => `${x},${y}`;
  const left = new Map(cells.map((c) => [key(c.x, c.y), c]));
  const order = [...cells].sort((a, b) => a.y - b.y || a.x - b.x);
  const pieces = [];
  for (const start of order) {
    if (!left.has(key(start.x, start.y))) continue;
    const group = [];
    const queue = [start];
    left.delete(key(start.x, start.y));
    while (queue.length && group.length < size) {
      const c = queue.shift();
      group.push(c);
      for (const [dx, dy] of [[0, 1], [1, 0], [-1, 0], [0, -1]]) { // 위로 먼저 (세로 획을 길게 묶음)
        const k = key(c.x + dx, c.y + dy);
        if (left.has(k) && group.length + queue.length < size) {
          queue.push(left.get(k));
          left.delete(k);
        }
      }
    }
    for (const c of queue) left.set(key(c.x, c.y), c); // 크기를 넘은 후보는 돌려놓음 (다음 조각이 씀)
    pieces.push({ shape: shapes[pieces.length % shapes.length], cells: group, minY: Math.min(...group.map((c) => c.y)) });
  }
  return pieces;
}

// 떨어지는 순서: 바닥 높이가 낮은 조각 먼저 (같으면 왼쪽부터) → i 번째가 i × interval ms 에 출발
export function dropSchedule(pieces, interval = C.TITLE_DROP_INTERVAL_MS) {
  const sorted = pieces
    .map((p, i) => ({ p, i, cx: p.cells.reduce((a, c) => a + c.x, 0) / p.cells.length }))
    .sort((a, b) => a.p.minY - b.p.minY || a.cx - b.cx);
  const start = new Array(pieces.length);
  sorted.forEach((s, k) => (start[s.i] = k * interval));
  return start;
}

// 로고가 다 쌓이는 시각 (ms)
export function titleDoneAt(start, fallMs = C.TITLE_FALL_MS, settleMs = C.TITLE_SETTLE_MS) {
  return start.length ? Math.max(...start) + fallMs + settleMs : 0;
}

// t ms 에 조각의 자리 위 높이 (칸): 출발 전 = null (안 보임), 떨어지는 중 = 가속하며 내려옴, 닿은 뒤 작게 한 번 튕기고 0
export function pieceLift(t, start, fallMs = C.TITLE_FALL_MS, dropH = C.TITLE_DROP_H, settleMs = C.TITLE_SETTLE_MS, bounce = C.TITLE_BOUNCE) {
  const u = t - start;
  if (u < 0) return null;
  if (u < fallMs) {
    const k = u / fallMs;
    return dropH * (1 - k * k);
  }
  const s = (u - fallMs) / settleMs;
  if (s >= 1) return 0;
  return bounce * Math.sin(Math.PI * s) * (1 - s);
}

// 타이틀이 보일지: 링크(?room=)로 왔으면 (재접속 자동 복귀 포함) 건너뜀
export function showTitle(search) {
  return !new URLSearchParams(search || '').get('room');
}

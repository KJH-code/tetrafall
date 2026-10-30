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

// 글자 → 칸 [{ x, y }] (x 는 왼쪽부터, y 는 아래부터 = 0). 글자 사이 gap 칸. 모르는 글자는 빈칸.
// bold: 글꼴 한 칸을 bold×bold 칸으로 (2 = 획 2칸 두께, 10×14 글자, 글자 사이도 2배)
export function titleCells(text, gap = 1, bold = 1) {
  const cells = [];
  let ox = 0;
  const k = Math.max(1, Math.floor(bold));
  for (const ch of String(text).toUpperCase()) {
    const g = FONT[ch] || FONT[' '];
    g.forEach((row, r) => {
      for (let c = 0; c < GLYPH_W; c++) {
        if (row[c] !== '#') continue;
        for (let i = 0; i < k; i++) for (let j = 0; j < k; j++) cells.push({ x: ox + c * k + i, y: (GLYPH_H - 1 - r) * k + j });
      }
    });
    ox += (GLYPH_W + gap) * k;
  }
  return { cells, width: Math.max(0, ox - gap * k), height: GLYPH_H * k };
}

// 조각 n 개가 다 쌓이는 시간이 TITLE_BUILD_MS 쯤 되게 출발 간격 (ms). 조각이 많으면 짧게 (겹쳐 떨어짐), 최소 TITLE_DROP_MIN_MS
export function titleInterval(n, buildMs = C.TITLE_BUILD_MS, fallMs = C.TITLE_FALL_MS, settleMs = C.TITLE_SETTLE_MS) {
  if (n <= 1) return 0;
  return Math.max(C.TITLE_DROP_MIN_MS, (buildMs - fallMs - settleMs) / (n - 1));
}

// 로고 폭이 화면 폭의 fill 만큼 차게 하는 카메라 거리. worldW = 로고 폭 (게임 칸), fovDeg = 세로 시야각, aspect = 폭/높이
export function titleCamDist(worldW, fovDeg, aspect, fill = C.TITLE_FILL) {
  const tanH = Math.tan(((fovDeg * Math.PI) / 180) / 2) * aspect;
  return worldW / 2 / (fill * tanH);
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

// 타이틀 테마 (config TITLE_THEMES 키 = 맵 테마 id): 켤 때마다 무작위 하나. rnd = 0~1 난수 (테스트에서 고정)
export const TITLE_THEME_IDS = Object.keys(C.TITLE_THEMES);
export function pickTitleTheme(rnd = Math.random) {
  return TITLE_THEME_IDS[Math.min(TITLE_THEME_IDS.length - 1, Math.floor(rnd() * TITLE_THEME_IDS.length))];
}

// 그 테마의 맵 (타이틀 뒤 메뉴 섬): WORLD_MAP_THEME 거꾸로. 없으면 null (메뉴가 무작위)
export function titleMapFor(theme) {
  return Object.keys(C.WORLD_MAP_THEME).find((m) => C.WORLD_MAP_THEME[m] === theme) || null;
}

const smooth = (k) => (k <= 0 ? 0 : k >= 1 ? 1 : k * k * (3 - 2 * k));

// t ms 에 장면 빛: lit = 장면 밝기 (캄캄 TITLE_LIT_START → 1, TITLE_DARK_MS 동안), burst = 다 쌓인 순간 1 → 0 (TITLE_BURST_MS),
// glow = 글자 빛 (쌓이는 동안 약하게, 터지면 TITLE_BURST_PEAK 배까지 갔다가 TITLE_GLOW[1]). doneAt = 다 쌓이는 시각
export function titleLight(t, doneAt) {
  const lit = C.TITLE_LIT_START + (1 - C.TITLE_LIT_START) * smooth(t / C.TITLE_DARK_MS);
  const u = t - doneAt;
  const burst = u < 0 ? 0 : Math.max(0, 1 - u / C.TITLE_BURST_MS) ** 2;
  const [g0, g1] = C.TITLE_GLOW;
  const after = u < 0 ? 0 : smooth(u / 250); // 터지는 순간 빠르게 오름
  const glow = (g0 + (g1 - g0) * after) * (1 + (C.TITLE_BURST_PEAK - 1) * burst);
  return { lit, burst, glow };
}

// Enter 뒤 ms: push = 카메라가 앞으로 빠져나간 정도 0~1 (점점 빠르게), white = 하얀 정도 0~1 (TITLE_EXIT_MS 에 1),
// 그 뒤 TITLE_EXIT_FADE_MS 동안 1 → 0 (메뉴 섬이 보임). swap = 타이틀 장면을 치우고 메뉴로 바꿀 때 (하얗게 다 덮임)
export function titleExit(ms) {
  const E = C.TITLE_EXIT_MS;
  if (ms < E) {
    const k = Math.max(0, ms) / E;
    return { push: k * k, white: k ** 2.2, swap: false, done: false };
  }
  const f = (ms - E) / C.TITLE_EXIT_FADE_MS;
  return { push: 1, white: 1 - smooth(f), swap: true, done: f >= 1 };
}

// 이번 프레임에 닿은 조각 (t0 < 닿는 시각 <= t1): 착지 소리·번쩍
export function landedBetween(start, t0, t1, fallMs = C.TITLE_FALL_MS) {
  const out = [];
  start.forEach((s, i) => {
    const at = s + fallMs;
    if (at > t0 && at <= t1) out.push(i);
  });
  return out;
}

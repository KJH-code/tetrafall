// 타이틀 로고 계산 (shared/title.js): 글자 칸·조각 나누기·떨어지는 순서·높이·링크면 건너뜀
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { titleCells, titlePieces, dropSchedule, titleDoneAt, pieceLift, showTitle, titleInterval, titleCamDist, GLYPH_W, GLYPH_H } from '../shared/title.js';
import { MAP_IDS } from '../shared/maps.js';
import { MenuScene } from '../client/menu-scene.js';

test('타이틀: 글자 → 5×7 칸, 글자 사이 1칸, 모르는 글자는 빈칸', () => {
  const t = titleCells('T');
  assert.equal(t.width, GLYPH_W);
  assert.equal(t.height, GLYPH_H);
  assert.equal(t.cells.length, 5 + 6, 'T = 윗줄 5 + 기둥 6');
  assert.ok(t.cells.some((c) => c.x === 2 && c.y === 0), '기둥 아래 끝');
  assert.equal(titleCells('TT').width, GLYPH_W * 2 + 1);
  assert.equal(titleCells('T?').cells.length, titleCells('T').cells.length);
  const logo = titleCells(C.TITLE_TEXT);
  assert.equal(logo.width, C.TITLE_TEXT.length * (GLYPH_W + 1) - 1);
  assert.ok(logo.cells.every((c) => c.x >= 0 && c.x < logo.width && c.y >= 0 && c.y < GLYPH_H));
});

test('타이틀: 조각은 칸을 빠짐·겹침 없이 나누고, 4칸 이하·서로 붙어 있음, 색은 테트리미노 7색', () => {
  const { cells } = titleCells(C.TITLE_TEXT);
  const pieces = titlePieces(cells);
  const seen = new Set();
  for (const p of pieces) {
    assert.ok(p.cells.length >= 1 && p.cells.length <= 4);
    assert.ok(C.SHAPE_COLORS[p.shape] !== undefined);
    for (const c of p.cells) {
      const k = `${c.x},${c.y}`;
      assert.ok(!seen.has(k), '겹침 없음');
      seen.add(k);
    }
    // 붙어 있음: 첫 칸에서 조각 안 칸만 밟아 다 닿음
    const inP = new Set(p.cells.map((c) => `${c.x},${c.y}`));
    const reach = new Set([`${p.cells[0].x},${p.cells[0].y}`]);
    const q = [p.cells[0]];
    while (q.length) {
      const c = q.shift();
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const k = `${c.x + dx},${c.y + dy}`;
        if (inP.has(k) && !reach.has(k)) {
          reach.add(k);
          q.push({ x: c.x + dx, y: c.y + dy });
        }
      }
    }
    assert.equal(reach.size, p.cells.length);
  }
  assert.equal(seen.size, cells.length, '빠짐 없음');
  const n4 = pieces.filter((p) => p.cells.length === 4).length;
  for (const k of [1, 2, 3]) assert.ok(n4 > pieces.filter((p) => p.cells.length === k).length, '4칸 조각이 가장 많음 (테트리미노처럼)');
  assert.ok(cells.length / pieces.length >= 2.8, '조각 평균 3칸쯤');
});

test('타이틀: 아래 조각부터 떨어지고, 높이는 출발 전 안 보임 → 내려옴 → 튕기고 0, 다 쌓이는 시각', () => {
  const pieces = titlePieces(titleCells(C.TITLE_TEXT).cells);
  const start = dropSchedule(pieces);
  const order = pieces.map((p, i) => [p.minY, start[i]]).sort((a, b) => a[1] - b[1]);
  for (let i = 1; i < order.length; i++) assert.ok(order[i][0] >= order[i - 1][0], '바닥 높이 순');
  assert.deepEqual([...start].sort((a, b) => a - b), pieces.map((_, i) => i * C.TITLE_DROP_INTERVAL_MS));
  assert.equal(pieceLift(-1, 0), null);
  assert.equal(pieceLift(0, 0), C.TITLE_DROP_H);
  assert.ok(pieceLift(C.TITLE_FALL_MS / 2, 0) < C.TITLE_DROP_H && pieceLift(C.TITLE_FALL_MS / 2, 0) > 0);
  assert.ok(pieceLift(C.TITLE_FALL_MS + C.TITLE_SETTLE_MS / 2, 0) <= C.TITLE_BOUNCE);
  assert.equal(pieceLift(C.TITLE_FALL_MS + C.TITLE_SETTLE_MS, 0), 0);
  const done = titleDoneAt(start);
  assert.equal(done, Math.max(...start) + C.TITLE_FALL_MS + C.TITLE_SETTLE_MS);
  assert.ok(done < 5000, '5초 안에 다 쌓임');
  assert.ok(start.every((s, i) => pieceLift(done, s) === 0));
});

test('타이틀: 링크(?room=)로 오면 건너뜀 (재접속 자동 복귀도 ?room= 로 새로고침)', () => {
  assert.equal(showTitle(''), true);
  assert.equal(showTitle('?x=1'), true);
  assert.equal(showTitle('?room=ABCD'), false);
  assert.equal(showTitle('?room='), true, '빈 코드면 메뉴 (보통 켜기)');
});

test('타이틀: 굵은 글꼴 (한 칸 = 2×2, 획 2칸), 조각이 늘어도 다 쌓이는 시간은 TITLE_BUILD_MS 쯤', () => {
  const thin = titleCells(C.TITLE_TEXT, C.TITLE_GAP, 1);
  const bold = titleCells(C.TITLE_TEXT, C.TITLE_GAP, C.TITLE_BOLD);
  assert.equal(C.TITLE_BOLD, 2);
  assert.equal(bold.cells.length, thin.cells.length * 4);
  assert.equal(bold.height, GLYPH_H * 2);
  assert.equal(bold.width, thin.width * 2);
  const keys = new Set(bold.cells.map((c) => `${c.x},${c.y}`));
  // T 의 기둥은 2칸 폭: 아래 끝 두 칸
  assert.ok(keys.has('4,0') && keys.has('5,0'));
  const pieces = titlePieces(bold.cells);
  const start = dropSchedule(pieces, titleInterval(pieces.length));
  const done = titleDoneAt(start);
  assert.ok(Math.abs(done - C.TITLE_BUILD_MS) < 300, `다 쌓이는 시간 ${done}`);
  assert.equal(titleInterval(1), 0);
  assert.ok(titleInterval(100000) >= C.TITLE_DROP_MIN_MS);
});

test('타이틀: 카메라 거리 — 로고 폭이 화면 폭의 TITLE_FILL, 좁은 화면이면 더 멀리', () => {
  const w = 50;
  const d169 = titleCamDist(w, 75, 16 / 9);
  const half = Math.tan((37.5 * Math.PI) / 180) * (16 / 9) * d169;
  assert.ok(Math.abs(w / 2 / half - C.TITLE_FILL) < 1e-9);
  assert.ok(titleCamDist(w, 75, 4 / 3) > d169);
  assert.ok(C.TITLE_FILL > 0.6 && C.TITLE_FILL < 0.95, '좌우 여백 적당히');
});

test('타이틀: 섬 맵 고정 (config TITLE_MAP = 수정 동굴 계단), 메뉴 장면이 그 맵으로', () => {
  assert.equal(C.TITLE_MAP, 'stairs');
  assert.equal(C.WORLD_MAP_THEME[C.TITLE_MAP], 'crystal');
  assert.ok(MAP_IDS.includes(C.TITLE_MAP));
  assert.equal(new MenuScene(Math.random, false, C.TITLE_MAP).mapId, 'stairs');
  assert.ok(MAP_IDS.includes(new MenuScene(Math.random, false, 'nope').mapId), '없는 맵이면 무작위');
});

// 시작 지형 (2026-10-29 재혁: 맵 7개 다시): 판 크기 10~19 모두에서 바람개비(90°) 대칭·시작 자리 비움·높이 상한·바닥에서 오를 수 있음
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MAP_IDS, mapColumns } from '../shared/maps.js';
import { CONFIG as C } from '../shared/config.js';

const SIZES = [...new Set(Object.values(C.FIELD_SIZES))];
// 맵마다 가장 높은 층 (4명 이상 판 = 14칸 이상에서 정확히, 작은 판은 시작 자리를 비우느라 더 낮을 수 있음)
const TOP = { flat: 0, pyramid: 3, stairs: 4, bowl: 3, spiral: 5, pillars: 4, fortress: 3 };

function heights(id, W) {
  const h = Array.from({ length: W }, () => new Array(W).fill(0));
  for (const [x, y, z] of mapColumns(id, W, W)) h[x][y] = z;
  return h;
}

test('맵: 7개, 칸은 판 안·정수 높이 1..MAP_MAX_H·같은 칸 두 번 없음, 맵마다 블록이 있음 (평지만 빈 판)', () => {
  assert.deepEqual(MAP_IDS, ['flat', 'pyramid', 'stairs', 'bowl', 'spiral', 'pillars', 'fortress']);
  assert.equal(C.MAP_MAX_H, 5);
  for (const id of MAP_IDS) {
    for (const W of SIZES) {
      const cols = mapColumns(id, W, W);
      if (id !== 'flat') assert.ok(cols.length >= 8, `${id} ${W}: 블록 기둥 ${cols.length}`);
      const seen = new Set();
      for (const [x, y, h] of cols) {
        assert.ok(Number.isInteger(x) && Number.isInteger(y) && x >= 0 && x < W && y >= 0 && y < W, `${id} ${W} (${x},${y})`);
        assert.ok(Number.isInteger(h) && h >= 1 && h <= C.MAP_MAX_H, `${id} ${W} 높이 ${h}`);
        assert.ok(!seen.has(x * 100 + y), `${id} ${W} 겹침`);
        seen.add(x * 100 + y);
      }
    }
  }
});

test('맵: 가장 높은 층은 맵마다 정해짐 (14칸 이상 판에서 똑같고, 작은 판은 그 이하)', () => {
  for (const id of MAP_IDS) {
    assert.ok(TOP[id] <= C.MAP_MAX_H);
    for (const W of SIZES) {
      const top = Math.max(0, ...mapColumns(id, W, W).map((c) => c[2]));
      if (W >= C.FIELD_SIZES[4]) assert.equal(top, TOP[id], `${id} ${W}`);
      else assert.ok(top <= TOP[id] && (top >= 1 || id === 'flat'), `${id} ${W}: ${top}`);
    }
  }
});

test('맵: 90° 돌려도 똑같음 (바람개비 대칭) → 같은 종류 시작 자리(모서리끼리·변 가운데끼리) 주변 지형이 같음', () => {
  for (const id of MAP_IDS) {
    for (const W of SIZES) {
      const h = heights(id, W);
      for (let x = 0; x < W; x++) for (let y = 0; y < W; y++) assert.equal(h[W - 1 - y][x], h[x][y], `${id} ${W} (${x},${y})`);
    }
  }
  // 시작 자리도 90° 돌리면 같은 종류 시작 자리로 감
  for (const W of SIZES) {
    const pts = C.spawnPointsFor(W, W);
    const key = (p) => `${p.x.toFixed(2)},${p.y.toFixed(2)}`;
    for (const [from, to] of [[0, 4], [4, 8]]) {
      const set = new Set(pts.slice(from, to).map(key));
      for (const p of pts.slice(from, to)) assert.ok(set.has(key({ x: W - p.y, y: p.x })), `${W} ${key(p)}`);
    }
  }
});

test('맵: 시작 칸과 둘레 MAP_SPAWN_CLEAR 칸은 바닥 (인원마다 실제로 쓰는 시작 자리)', () => {
  for (const id of MAP_IDS) {
    for (let n = 2; n <= C.MAX_PLAYERS; n++) {
      const W = C.FIELD_SIZES[n];
      const h = heights(id, W);
      for (const p of C.spawnPointsFor(W, W).slice(0, n)) {
        const x0 = Math.floor(p.x);
        const y0 = Math.floor(p.y);
        for (let dx = -C.MAP_SPAWN_CLEAR; dx <= C.MAP_SPAWN_CLEAR; dx++) {
          for (let dy = -C.MAP_SPAWN_CLEAR; dy <= C.MAP_SPAWN_CLEAR; dy++) {
            const x = x0 + dx;
            const y = y0 + dy;
            if (x >= 0 && y >= 0 && x < W && y < W) assert.equal(h[x][y], 0, `${id} ${n}명 시작 (${p.x},${p.y}) 옆 (${x},${y})`);
          }
        }
      }
    }
  }
});

test('맵: 어느 블록 윗면이든 바닥에서 걸어 오를 수 있음 (이웃 칸끼리 2층 차이까지 = 2단 점프, 봇 용암 피하기 길찾기와 같은 규칙)', () => {
  for (const id of MAP_IDS) {
    for (const W of SIZES) {
      const h = heights(id, W);
      const ok = h.map((r) => r.map((z) => z === 0));
      const q = [];
      for (let x = 0; x < W; x++) for (let y = 0; y < W; y++) if (ok[x][y]) q.push([x, y]);
      while (q.length) {
        const [x, y] = q.pop();
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          const a = x + dx;
          const b = y + dy;
          if (a < 0 || b < 0 || a >= W || b >= W || ok[a][b] || h[a][b] - h[x][y] > 2) continue;
          ok[a][b] = true;
          q.push([a, b]);
        }
      }
      const bad = [];
      for (let x = 0; x < W; x++) for (let y = 0; y < W; y++) if (!ok[x][y]) bad.push(`${x},${y}:${h[x][y]}`);
      assert.deepEqual(bad, [], `${id} ${W}`);
    }
  }
});

test('맵: 모양이 서로 다르고, 같은 맵이면 판 크기가 달라도 빈칸 비율이 비슷함 (판이 커져도 모양이 같이 커짐)', () => {
  const W = C.FIELD_SIZES[4];
  const sig = MAP_IDS.map((id) => JSON.stringify(mapColumns(id, W, W)));
  assert.equal(new Set(sig).size, MAP_IDS.length);
  for (const id of MAP_IDS) {
    const fill = SIZES.filter((w) => w >= W).map((w) => mapColumns(id, w, w).length / (w * w));
    assert.ok(Math.max(...fill) - Math.min(...fill) < 0.15, `${id}: ${fill.map((f) => f.toFixed(2)).join(' ')}`);
  }
});

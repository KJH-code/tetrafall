// 시작 지형 테마 포인트 (2026-10-29 재혁: 예전 배치 그대로 + 테마 장식만). 판 크기 10~19 모두
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MAP_IDS, mapColumns, baseColumns } from '../shared/maps.js';
import { CONFIG as C } from '../shared/config.js';

const SIZES = [...new Set(Object.values(C.FIELD_SIZES))];
const grid = (cols, W) => {
  const h = Array.from({ length: W }, () => new Array(W).fill(0));
  for (const [x, y, z] of cols) h[x][y] = z;
  return h;
};

test('맵: 칸은 판 안·정수 높이 1..MAP_MAX_H·한 칸 한 번', () => {
  for (const id of MAP_IDS) for (const W of SIZES) {
    const seen = new Set();
    for (const [x, y, z] of mapColumns(id, W, W)) {
      assert.ok(x >= 0 && y >= 0 && x < W && y < W && Number.isInteger(z) && z >= 1 && z <= C.MAP_MAX_H, `${id} ${W} (${x},${y},${z})`);
      assert.ok(!seen.has(x * 100 + y));
      seen.add(x * 100 + y);
    }
  }
});

test('맵: 예전 배치 그대로 + 포인트만 — 바뀐 칸은 48칸 이하, 높아진 칸은 3층까지, 낮아진 칸은 바닥까지 (틈)', () => {
  for (const id of MAP_IDS) for (const W of SIZES) {
    const a = grid(baseColumns(id, W, W), W);
    const b = grid(mapColumns(id, W, W), W);
    let changed = 0;
    let base = 0;
    for (let x = 0; x < W; x++) for (let y = 0; y < W; y++) {
      if (a[x][y]) base++;
      if (a[x][y] === b[x][y]) continue;
      changed++;
      if (b[x][y] > a[x][y]) assert.ok(b[x][y] - a[x][y] <= 3, `${id} ${W} (${x},${y}) ${a[x][y]}→${b[x][y]}`); // 포인트는 3층까지 덧붙임
      else assert.equal(b[x][y], 0, `${id} ${W} (${x},${y}) 틈은 바닥까지`);
    }
    assert.ok(changed <= 48, `${id} ${W}: ${changed}칸 / ${base}`); // 포인트 여러 곳 × 몇 칸 (2026-10-29 재혁 '조금 더': 16 → 48)
    if (id === 'flat') assert.equal(changed, 0);
  }
});

test('맵 포인트: 피라미드 머릿돌 5층·수정 첨탑 6층·뾰족탑 7층·망루 4층·화산 굴뚝 4층·가운데 버섯 4층, 그릇·요새 벽마다 틈 (90° 돌려도 같은 자리)', () => {
  for (const W of SIZES) {
    const top = (id) => Math.max(...mapColumns(id, W, W).map((c) => c[2]));
    assert.deepEqual(['pyramid', 'stairs', 'spiral', 'fortress', 'bowl', 'pillars'].map(top), [W === 10 ? 4 : 5, 6, 7, 4, 4, 4], `${W}`); // 10×10 피라미드는 꼭대기가 좁아 머릿돌 4층
    for (const id of ['bowl', 'fortress']) {
      const a = grid(baseColumns(id, W, W), W);
      const b = grid(mapColumns(id, W, W), W);
      const holes = [];
      for (let x = 0; x < W; x++) for (let y = 0; y < W; y++) if (a[x][y] && !b[x][y]) holes.push([x, y]);
      const key = new Set(holes.map(([x, y]) => x * 100 + y));
      for (const [x, y] of holes) assert.ok(key.has((W - 1 - y) * 100 + x), `${id} ${W} 틈 바람개비 (${x},${y})`);
      // 변마다 틈이 바깥 줄을 끊음
      for (const side of [(i) => [i, 0], (i) => [W - 1, i], (i) => [i, W - 1], (i) => [0, i]]) {
        assert.ok([...Array(W).keys()].some((i) => { const [x, y] = side(i); return a[x][y] && !b[x][y]; }), `${id} ${W} 변마다 틈`);
      }
    }
  }
});

test('맵: 어느 블록 윗면이든 바닥에서 이웃 칸 2층 차이까지(2단 점프)로 오름', () => {
  for (const id of MAP_IDS) for (const W of SIZES) {
    const h = grid(mapColumns(id, W, W), W);
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
    for (let x = 0; x < W; x++) for (let y = 0; y < W; y++) assert.ok(ok[x][y], `${id} ${W} (${x},${y}) ${h[x][y]}층`);
  }
});

test('맵 이름 (2026-10-30 재혁 확정): 화면 이름은 shared/maps.js 한 곳, 로그 이름은 예전 그대로', async () => {
  const { MAPS, mapName, MAP_RANDOM_NAME } = await import('../shared/maps.js');
  const fs = await import('node:fs');
  assert.deepEqual(Object.fromEntries(MAP_IDS.map((id) => [id, mapName(id)])), {
    flat: '바람 들판', pyramid: '황금 피라미드', stairs: '자수정 동굴', bowl: '용암 분화구', spiral: '구름 위 성', pillars: '반딧불 버섯 숲', fortress: '횃불 요새',
  });
  assert.equal(mapName('random'), MAP_RANDOM_NAME);
  assert.equal(MAP_RANDOM_NAME, '무작위');
  // 서버 로그 '맵 X' 는 예전 이름 (npm run stats 맵별이 예전 로그와 이어짐)
  assert.deepEqual(Object.fromEntries(MAP_IDS.map((id) => [id, MAPS[id].log])), {
    flat: '평지', pyramid: '피라미드', stairs: '계단', bowl: '그릇', spiral: '나선 계단', pillars: '기둥 숲', fortress: '요새',
  });
  // 화면에 따로 박힌 이름 없음: 맵 고르기 칸은 main.js 가 채우고, MAP_KO 표는 없어짐
  const html = fs.readFileSync(new URL('../client/index.html', import.meta.url), 'utf8');
  const main = fs.readFileSync(new URL('../client/main.js', import.meta.url), 'utf8');
  assert.ok(!/<select id="map-select">[^]*?<option/.test(html.split('</select>').find((x) => x.includes('id="map-select"')) || ''), 'index.html 맵 option 없음');
  assert.ok(!main.includes('MAP_KO'));
  for (const id of MAP_IDS) assert.ok(!html.includes(`value="${id}"`), id);
});

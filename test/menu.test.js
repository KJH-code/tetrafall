// 메뉴 배경 가짜 대기 장면 (client/menu-scene.js): 서버 없이 화면만. 지형은 맵 그대로, 캐릭터는 땅 위에, 진짜 id 와 안 겹침
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { MenuScene } from '../client/menu-scene.js';
import { MAP_IDS, mapColumns } from '../shared/maps.js';
import { CELL } from '../shared/pieces.js';

function seeded(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

test('메뉴 장면: 맵 지형 그대로, 캐릭터 수는 보통·낮춤, 서로 떨어져 기둥 위(또는 바닥)에 섬', () => {
  for (let seed = 1; seed <= 20; seed++) {
    for (const low of [false, true]) {
      const m = new MenuScene(seeded(seed), low);
      assert.ok(MAP_IDS.includes(m.mapId));
      const { grid, field } = m.state;
      const cols = mapColumns(m.mapId, field.w, field.d);
      assert.equal(grid.filter((v) => v === CELL.TERRAIN).length, cols.reduce((a, [, , h]) => a + h, 0));
      assert.equal(m.players.length, C.MENU_CHARS[low ? 1 : 0]);
      for (const p of m.players) {
        assert.ok(p.id <= -9000, '진짜 플레이어·허수아비 id 와 안 겹침');
        assert.ok(C.CHARACTERS.includes(p.char));
        const x = Math.floor(p.x);
        const y = Math.floor(p.y);
        const z = Math.round(p.z);
        assert.ok(z === 0 || grid[((z - 1) * field.d + y) * field.w + x] === CELL.TERRAIN, '발밑이 바닥이나 지형');
        assert.ok(z >= field.h || !grid[(z * field.d + y) * field.w + x], '블록 속에 안 박힘');
      }
      for (const a of m.players) for (const b of m.players) if (a !== b) assert.ok(Math.hypot(a.x - b.x, a.y - b.y) >= 2.5);
      assert.equal(new Set(m.players.map((p) => p.char)).size, m.players.length, '캐릭터 안 겹침');
    }
  }
});

test('메뉴 장면: 시간이 가면 가끔 이모트 (EMOTE_MS 동안), 카메라가 돎, 이름·% 숨김 표시', () => {
  const m = new MenuScene(seeded(7));
  const yaw0 = m.camYaw;
  let emoted = 0;
  for (let i = 0; i < 600; i++) {
    const { state, cam } = m.step(0.05);
    assert.equal(state.menu, true);
    assert.ok(cam.pitch < 0, '위에서 내려다봄');
    emoted += state.players.filter((p) => p.emote >= 0).length;
  }
  assert.ok(emoted > 0, '30초 안에 누군가 이모트');
  assert.ok(m.camYaw > yaw0);
  assert.ok(m.players.every((p) => p.emote === -1 || (p.emote < C.EMOTE_NAMES.length && p.emoteLeft <= C.EMOTE_MS)));
});

// 맵 테마 표 (shared/config.js WORLD_MAP_THEME · WORLD_THEMES, 화면은 client/world.js): 맵 id·테마 id 가 맞고 값이 다 있는지
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { MAP_IDS } from '../server/maps.js';

const KEYS = ['seed', 'sky', 'sunDir', 'sunColor', 'sunIntensity', 'hemi', 'fog', 'floor', 'terrain', 'cliff', 'rock', 'trunk', 'leaf', 'props', 'cloud', 'far', 'sea', 'clouds', 'islets', 'edgeOpacity', 'hazard'];
const PROPS = ['pine', 'round', 'rock', 'cactus', 'palm', 'pyramid'];

test('맵 테마: 평지 = 초원, 피라미드 = 사막, 나머지 맵은 테마 없음 (예전 노을)', () => {
  assert.equal(C.WORLD_MAP_THEME.flat, 'meadow');
  assert.equal(C.WORLD_MAP_THEME.pyramid, 'desert');
  for (const [map, theme] of Object.entries(C.WORLD_MAP_THEME)) {
    assert.ok(MAP_IDS.includes(map), `없는 맵 ${map}`);
    assert.ok(C.WORLD_THEMES[theme], `없는 테마 ${theme}`);
  }
});

test('맵 테마: 테마마다 값이 다 있음 (하늘 4색·위험 모습·소품 종류)', () => {
  for (const [id, t] of Object.entries(C.WORLD_THEMES)) {
    for (const k of KEYS) assert.ok(t[k] !== undefined, `${id}.${k}`);
    for (const k of ['top', 'mid', 'horizon', 'below']) assert.equal(typeof t.sky[k], 'number', `${id}.sky.${k}`);
    for (const k of ['deep', 'mid', 'foam']) assert.equal(typeof t.hazard[k], 'number', `${id}.hazard.${k}`);
    assert.equal(t.hazard.light.length, 2);
    assert.equal(t.hazard.particles.length, 2);
    assert.ok(['grass', 'sandstone'].includes(t.terrain.paint));
    assert.ok(['grass', 'sand'].includes(t.floor.paint));
    for (const p of t.props) assert.ok(PROPS.includes(p), `${id} 소품 ${p}`);
    assert.ok(t.cliff.length >= 1 && t.leaf.length >= 1);
    assert.ok(t.edgeOpacity >= 0 && t.edgeOpacity <= 0.15, '필드 세로선은 옅게');
  }
  assert.ok(C.WORLD_LOW_DETAIL > 0 && C.WORLD_LOW_DETAIL < 1);
});

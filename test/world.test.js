// 맵 테마 표 (shared/config.js WORLD_MAP_THEME · WORLD_THEMES, 화면은 client/world.js): 맵 id·테마 id 가 맞고 값이 다 있는지
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { MAP_IDS } from '../server/maps.js';

const KEYS = ['seed', 'sky', 'sunDir', 'sunColor', 'sunIntensity', 'hemi', 'fog', 'floor', 'terrain', 'cliff', 'rock', 'trunk', 'leaf', 'props', 'cloud', 'far', 'sea', 'clouds', 'islets', 'edgeOpacity', 'hazard'];
const PROPS = ['pine', 'round', 'rock', 'cactus', 'palm', 'pyramid', 'crystal', 'mushroom', 'deadtree', 'lavarock', 'tower', 'spire', 'house'];
const FAR = ['peak', 'mesa', 'pyramid', 'volcano', 'crystal', 'cumulus', 'bigshroom', 'castle'];
const GLOWS = ['crystal', 'mushroom', 'lavarock', 'volcano', 'bigshroom']; // 빛나는 소품·먼 배경은 테마 glow 색이 있어야
const BUILT = ['tower', 'spire', 'house']; // 탑·집은 wall·roof 색이 있어야

test('맵 테마: 7맵 모두 테마 (평지 초원 · 피라미드 사막 · 계단 수정 동굴 · 그릇 화산 · 나선 하늘 성 · 기둥 버섯 숲 · 요새 중세 성)', () => {
  assert.deepEqual(C.WORLD_MAP_THEME, { flat: 'meadow', pyramid: 'desert', stairs: 'crystal', bowl: 'volcano', spiral: 'skycastle', pillars: 'mushroom', fortress: 'castle' });
  for (const id of MAP_IDS) assert.ok(C.WORLD_MAP_THEME[id], `테마 없는 맵 ${id}`);
  for (const [map, theme] of Object.entries(C.WORLD_MAP_THEME)) {
    assert.ok(MAP_IDS.includes(map), `없는 맵 ${map}`);
    assert.ok(C.WORLD_THEMES[theme], `없는 테마 ${theme}`);
  }
});

test('맵 테마: 테마마다 값이 다 있음 (하늘 4색·위험 모습·소품 종류)', () => {
  for (const [id, t] of Object.entries(C.WORLD_THEMES)) {
    for (const k of KEYS) assert.ok(t[k] !== undefined, `${id}.${k}`);
    for (const k of ['top', 'mid', 'horizon', 'below']) assert.equal(typeof t.sky[k], 'number', `${id}.sky.${k}`);
    assert.ok(['water', 'swamp', 'energy', 'storm', 'lava'].includes(t.hazard.style), `${id}.hazard.style`);
    if (t.hazard.style !== 'lava') for (const k of ['deep', 'mid', 'foam']) assert.equal(typeof t.hazard[k], 'number', `${id}.hazard.${k}`);
    assert.equal(t.hazard.light.length, 2);
    assert.equal(t.hazard.particles.length, 2);
    assert.ok(['grass', 'sandstone', 'bricks', 'crystal', 'basalt', 'stump'].includes(t.terrain.paint));
    assert.ok(['grass', 'sand', 'stone', 'cracks', 'marble', 'moss'].includes(t.floor.paint));
    if (['crystal', 'basalt'].includes(t.terrain.paint)) assert.equal(typeof t.terrain.glow, 'number', `${id} 블록 빛 색`);
    if (t.floor.paint === 'cracks') assert.equal(typeof t.floor.glow, 'number', `${id} 바닥 금 색`);
    for (const p of t.props) assert.ok(PROPS.includes(p), `${id} 소품 ${p}`);
    for (const f of t.far.shapes) assert.ok(FAR.includes(f), `${id} 먼 배경 ${f}`);
    assert.equal(t.far.haze.length, 2);
    if ([...t.props, ...t.far.shapes].some((p) => GLOWS.includes(p))) assert.ok(t.glow && t.glow.length, `${id} glow 색`);
    if (t.props.some((p) => BUILT.includes(p))) assert.ok(t.wall !== undefined && t.roof !== undefined, `${id} wall·roof`);
    assert.ok(t.cliff.length >= 1 && t.leaf.length >= 1);
    assert.ok(t.edgeOpacity >= 0 && t.edgeOpacity <= 0.15, '필드 세로선은 옅게');
  }
  assert.ok(C.WORLD_LOW_DETAIL > 0 && C.WORLD_LOW_DETAIL < 1);
});

test('맵 테마: 위험 모습이 맵끼리 겹치지 않음 (독늪 2개는 색으로 구분), 밤 맵은 반구광을 세게', () => {
  const T = C.WORLD_THEMES;
  assert.equal(T.mushroom.hazard.style, 'swamp');
  assert.equal(T.castle.hazard.style, 'swamp');
  assert.notEqual(T.mushroom.hazard.mid, T.castle.hazard.mid);
  for (const id of ['crystal', 'volcano', 'mushroom']) {
    assert.ok(T[id].sky.stars > 0, `${id} 밤 (별)`);
    assert.ok(T[id].hemi[2] >= 1.4, `${id} 밤에도 캐릭터·블록이 보이게`);
  }
  assert.ok(C.WORLD_FAR.dist[1] < 150, '먼 배경은 하늘 구(150) 안쪽');
  assert.ok(C.WORLD_SEA_FADE[0] < C.WORLD_SEA_FADE[1] && C.WORLD_SEA_FADE[1] < 150);
});

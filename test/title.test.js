// 타이틀 로고 계산 (shared/title.js): 글자 칸·조각 나누기·떨어지는 순서·높이·링크면 건너뜀
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { titleCells, titlePieces, dropSchedule, titleDoneAt, pieceLift, showTitle, titleInterval, titleCamDist, GLYPH_W, GLYPH_H } from '../shared/title.js';
import { MAP_IDS } from '../shared/maps.js';

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

test('타이틀 테마: 맵 테마 7개 모두 엔딩 장면 값이 빠짐 없이, 켤 때마다 무작위 하나 (어느 테마든 나옴), 그 테마의 맵이 있음', async () => {
  const { pickTitleTheme, titleMapFor, TITLE_THEME_IDS } = await import('../shared/title.js');
  assert.deepEqual([...TITLE_THEME_IDS].sort(), Object.keys(C.WORLD_THEMES).sort(), '맵 테마 7개 = 타이틀 테마');
  assert.equal(TITLE_THEME_IDS.length, 7);
  const num = (v) => typeof v === 'number' && Number.isFinite(v);
  for (const id of TITLE_THEME_IDS) {
    const T = C.TITLE_THEMES[id];
    for (const k of ['bg', 'glow', 'edge', 'floor', 'flare']) assert.ok(num(T[k]), `${id}.${k}`);
    for (const k of ['amb', 'key', 'back']) assert.ok(num(T[k][0]) && num(T[k][1]) && T[k][1] > 0, `${id}.${k}`);
    assert.ok(T.fog.length === 3 && T.fog[1] < T.fog[2], `${id}.fog`);
    assert.ok(T.letter.length >= 1 && T.letter.every(num), `${id}.letter`);
    assert.ok(T.motes.length === 4 && T.motes[1] > 0, `${id}.motes`);
    assert.ok(typeof T.name === 'string' && T.name.length > 0);
    // 어두운 장면: 배경이 어두움 (밝기 < 0.12)
    const lum = (((T.bg >> 16) & 255) * 0.3 + ((T.bg >> 8) & 255) * 0.59 + (T.bg & 255) * 0.11) / 255;
    assert.ok(lum < 0.12, `${id} 배경 어둡게 (${lum.toFixed(3)})`);
    const S = T.sound;
    assert.ok(S.drone.length === 2 && S.drone.every(num) && num(S.hum) && num(S.pitch), `${id}.sound`);
    assert.ok(['drip', 'ember', 'wind', 'bubble', 'chime', 'torch', 'cricket'].includes(S.ping), `${id} ping ${S.ping}`);
    assert.ok(['crystal', 'stone', 'sand', 'soft'].includes(S.land), `${id} land ${S.land}`);
    const map = titleMapFor(id);
    assert.ok(MAP_IDS.includes(map), `${id} → 맵 ${map}`);
    assert.equal(C.WORLD_MAP_THEME[map], id);
  }
  assert.equal(C.TITLE_THEMES.crystal.sound.ping, 'drip', '수정 동굴 = 물방울·울림');
  // 무작위: 0~1 난수 칸마다 다른 테마, 다 나옴
  const seen = new Set();
  for (let k = 0; k < 7; k++) seen.add(pickTitleTheme(() => (k + 0.5) / 7));
  assert.equal(seen.size, 7);
  assert.ok(TITLE_THEME_IDS.includes(pickTitleTheme(() => 0.999999)));
  assert.ok(TITLE_THEME_IDS.includes(pickTitleTheme(Math.random)));
  assert.equal(titleMapFor('nope'), null);
});

test('타이틀 빛: 캄캄하게 시작해 밝아짐, 다 쌓인 순간 빛 터짐 (글자 빛 최대) → 가라앉아 잔잔히 빛남', async () => {
  const { titleLight } = await import('../shared/title.js');
  const done = 3000;
  const a = titleLight(0, done);
  assert.equal(a.lit, C.TITLE_LIT_START);
  assert.ok(a.lit < 0.3, '처음은 어둡게');
  assert.equal(a.burst, 0);
  assert.ok(titleLight(C.TITLE_DARK_MS / 2, done).lit > a.lit);
  assert.equal(titleLight(C.TITLE_DARK_MS, done).lit, 1);
  assert.equal(titleLight(done - 1, done).burst, 0, '다 쌓이기 전엔 안 터짐');
  assert.equal(titleLight(done, done).burst, 1);
  const peak = Math.max(...[0, 100, 200, 300, 400].map((u) => titleLight(done + u, done).glow));
  const calm = titleLight(done + C.TITLE_BURST_MS + 100, done);
  assert.equal(calm.burst, 0);
  assert.ok(Math.abs(calm.glow - C.TITLE_GLOW[1]) < 1e-9, '가라앉으면 TITLE_GLOW[1]');
  assert.ok(peak > calm.glow * 1.5, '터질 때 훨씬 밝음');
  assert.ok(titleLight(done - 500, done).glow < calm.glow, '쌓이는 동안은 약하게');
  for (let u = 0; u < C.TITLE_BURST_MS; u += 100) assert.ok(titleLight(done + u + 100, done).burst <= titleLight(done + u, done).burst, '터짐은 줄어들기만');
});

test('타이틀 → 메뉴: Enter 뒤 카메라가 로고 위로 날아가 메뉴 카메라로 (하얀 막 없음, 그 장면이 메뉴 배경), 판은 날아가는 끝 무렵에 들어옴', async () => {
  const { titleExit } = await import('../shared/title.js');
  assert.deepEqual(titleExit(0), { push: 0, white: 0, show: false, done: false });
  let p = 0;
  for (let ms = 0; ms <= C.TITLE_EXIT_MS; ms += 50) {
    const e = titleExit(ms);
    assert.equal(e.white, 0, '하얀 번쩍 없음');
    assert.ok(e.push >= p);
    p = e.push;
  }
  assert.equal(titleExit(C.TITLE_EXIT_MS).push, 1);
  assert.equal(titleExit(C.TITLE_EXIT_MS).done, true);
  assert.equal(titleExit(C.TITLE_EXIT_MS * C.TITLE_MENU_SHOW_AT - 1).show, false);
  assert.equal(titleExit(C.TITLE_EXIT_MS * C.TITLE_MENU_SHOW_AT).show, true, '카메라가 자리 잡는 동안 판이 들어옴');
  assert.ok(C.TITLE_EXIT_MS >= 800 && C.TITLE_EXIT_MS <= 1600, '날아가는 게 보이되 금방 메뉴');
});

test('타이틀 → 메뉴 (움직임 줄이기): 카메라는 안 날고 하얗게 됐다 걷힘, 가장 하얄 때 메뉴 카메라로', async () => {
  const { titleExit } = await import('../shared/title.js');
  const F = C.TITLE_EXIT_FADE_MS;
  assert.equal(titleExit(F / 2, true).push, 0);
  assert.ok(titleExit(F / 2, true).white > 0 && titleExit(F / 2, true).white < 1);
  assert.equal(titleExit(F, true).push, 1);
  assert.equal(titleExit(F, true).white, 1);
  assert.equal(titleExit(F, true).show, true);
  assert.equal(titleExit(F * 2, true).white, 0);
  assert.equal(titleExit(F * 2, true).done, true);
});

test('메뉴 카메라 떠돌기: 날아간 직후 0 에서 천천히 들어오고, 정한 폭 안에서만', async () => {
  const { menuDrift } = await import('../shared/title.js');
  assert.deepEqual(menuDrift(0).map((v) => Math.abs(v)), [0, 0, 0]);
  const D = C.MENU_DRIFT;
  for (let u = 0; u < 120000; u += 777) {
    const [x, z, yaw] = menuDrift(u);
    assert.ok(Math.abs(x) <= D.side + 1e-9 && Math.abs(z) <= D.bob + 1e-9 && Math.abs(yaw) <= D.yaw + 1e-9);
  }
  assert.ok(Math.abs(menuDrift(100)[0]) < Math.abs(menuDrift(D.easeMs + 4000)[0]) + 1, '처음엔 작게');
});

test('대기실·메뉴 앰비언트: 메뉴 = 메뉴 테마, 대기실 (판 전) = 방 맵 테마, 판·결과·연습 = 곡', async () => {
  const { Music } = await import('../client/music.js');
  assert.equal(Music.ambientTheme(null, 'crystal'), 'crystal');
  assert.equal(Music.ambientTheme({ phase: 'lobby', map: { id: 'bowl' } }, 'crystal'), 'volcano');
  assert.equal(Music.ambientTheme({ phase: 'playing', map: { id: 'bowl' } }, 'crystal'), null);
  assert.equal(Music.ambientTheme({ phase: 'over', map: { id: 'bowl' } }, 'crystal'), null);
  assert.equal(Music.ambientTheme({ phase: 'lobby', practice: {}, map: { id: 'bowl' } }, 'crystal'), null);
  for (const m of Object.keys(C.WORLD_MAP_THEME)) assert.ok(C.TITLE_THEMES[Music.ambientTheme({ phase: 'lobby', map: { id: m } })], `맵 ${m} 대기실 장면 테마`);
  assert.equal(Music.ambientTheme({ phase: 'lobby', map: { choice: 'fortress', id: 'flat' } }), 'castle', '고른 맵 (미리보기) 우선');
  assert.equal(Music.ambientTheme({ phase: 'lobby', map: { choice: 'random', id: 'flat' } }), 'meadow', '무작위 + 메뉴 테마 없음 = 지금 섬');
  assert.equal(Music.ambientTheme({ phase: 'lobby', map: { choice: 'random', id: 'flat' } }, 'desert'), 'desert', '무작위면 이번 창 메뉴 테마');
  // 앰비언트가 있으면 곡은 쉼, 없어지면 다시 곡
  const made = [];
  const m = new Music({ ready: () => false });
  m.makeAmbient = (id) => {
    const a = { theme: id, stopped: false, update() {}, stop() { this.stopped = true; } };
    made.push(a);
    return a;
  };
  m.update(null, 'desert');
  assert.equal(m.ambient.theme, 'desert');
  m.update({ phase: 'lobby', map: { id: 'flat' } }, 'desert');
  assert.equal(m.ambient.theme, 'meadow');
  assert.equal(made[0].stopped, true, '테마 바뀌면 이전 것 끔');
  m.update({ phase: 'playing', map: { id: 'flat' } }, 'desert');
  assert.equal(m.ambient, null);
  assert.equal(made[1].stopped, true);
});

test('타이틀: 프레임을 어떻게 나눠도 조각마다 착지 (소리·번쩍) 는 꼭 한 번', async () => {
  const { landedBetween } = await import('../shared/title.js');
  const pieces = titlePieces(titleCells(C.TITLE_TEXT, C.TITLE_GAP, C.TITLE_BOLD).cells);
  const start = dropSchedule(pieces, titleInterval(pieces.length));
  const done = titleDoneAt(start);
  for (const step of [16.7, 33, 7, 250]) {
    const count = new Array(pieces.length).fill(0);
    for (let t = 0; t < done; t += step) for (const i of landedBetween(start, t, Math.min(done, t + step))) count[i]++;
    assert.ok(count.every((c) => c === 1), `프레임 ${step}ms`);
  }
});

test('타이틀 그래픽 값: 블룸·불티는 그래픽 낮춤 값이 더 작고, 무대 소리 값 있음', () => {
  assert.equal(C.TITLE_BLOOM.length, 3);
  assert.ok(C.TITLE_BLOOM_BURST > C.TITLE_BLOOM[0]);
  assert.ok(C.TITLE_SPARKS[1] < C.TITLE_SPARKS[0]);
  assert.ok(C.TITLE_GLOW[0] < C.TITLE_GLOW[1]);
  for (const k of ['vol', 'land', 'burst', 'exit', 'echo']) assert.ok(C.TITLE_SOUND[k] > 0 && C.TITLE_SOUND[k] <= 1, k);
  assert.ok(C.TITLE_SOUND.pingEvery[0] < C.TITLE_SOUND.pingEvery[1]);
});

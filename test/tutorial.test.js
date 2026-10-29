// 직접 해 보는 튜토리얼 (2026-10-29 재혁): 단계 표 (지형·자리·문구), 완료 판정, 서버 흐름 (넘기기·끝·용암·압사), 자동 조종으로 8명 모두 끝까지
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Rooms } from '../server/rooms.js';
import { CONFIG as C } from '../shared/config.js';
import { tutorialLayout, tutorialSteps, tutorialStep, stepText, judge, progressLabel, nextStep, TUTORIAL_N } from '../shared/tutorial.js';
import { TutorialPilot } from '../shared/tutorial-pilot.js';

const TICK = 1000 / C.TICK_RATE;
const STEPS = C.TUTORIAL_STEPS;

function setup(char = 'tank', seed = 1) {
  let s = seed;
  const logs = [];
  const server = [];
  const rooms = new Rooms({
    openLog: (code) => {
      logs.push(code);
      return { log() {}, close() {} };
    },
    serverLog: (m) => server.push(m),
    rng: () => {
      s = (s * 1664525 + 1013904223) >>> 0;
      return s / 4294967296;
    },
  });
  const ws = { OPEN: 1, readyState: 1, msgs: [], send(t) { this.msgs.push(JSON.parse(t)); } };
  const conn = rooms.connect(ws);
  rooms.message(conn, { type: 'tutorial', nick: '재혁', char });
  const g = conn.room.game;
  const run = (ms) => {
    for (let t = 0; t < ms; t += TICK) rooms.tick(TICK);
  };
  return { rooms, logs, server, ws, conn, room: conn.room, g, me: g.players.get(conn.id), run };
}

// 자동 조종으로 끝까지. 반환: { done, results, ms }
function autoplay(char, seed, limitMs = 240000) {
  const { rooms, conn, g } = setup(char, seed);
  const pilot = new TutorialPilot();
  let t = 0;
  while (t < limitMs && !g.tutorial.done) {
    const { input, actions } = pilot.next(g.snapshot(false), conn.id);
    g.handleInput(conn.id, input);
    for (const a of actions) g.handleAction(conn.id, { name: a });
    rooms.tick(TICK);
    t += TICK;
  }
  return { done: g.tutorial.done, results: g.tutorial.results, ms: t };
}

test('단계 표: 4묶음 (이동·점프·대시 / 밀기·낙사·치명타 / 스킬·필살기·아이템 / 블록 피하기·용암), 문구 자리표가 다 채워짐', () => {
  assert.deepEqual([...new Set(STEPS.map((s) => s.part))], [1, 2, 3, 4]);
  assert.deepEqual(STEPS.map((s) => s.id), ['move', 'jump', 'dash', 'push', 'ringout', 'crit', 'skill', 'ult', 'item', 'dodge', 'climb']);
  assert.equal(new Set(STEPS.map((s) => s.id)).size, STEPS.length);
  const keyIds = new Set(['fwd', 'left', 'back', 'right', 'jump', 'dash', 'attack', 'item', 'skill', 'ult']);
  for (const char of C.FIGURE_CHARS) {
    for (const st of STEPS) {
      const txt = stepText(st, { char, keyName: (id) => `<${id}>` });
      assert.ok(!/\{|\}/.test(txt), `${st.id} ${char}: ${txt}`);
      for (const k of st.keys) assert.ok(keyIds.has(k), `${st.id}: 키 ${k}`);
      for (const m of st.text.matchAll(/\{(\w+)\}/g)) if (!['skillDesc', 'ultDesc'].includes(m[1])) assert.ok(st.keys.includes(m[1]), `${st.id}: 문구 키 ${m[1]} 가 keys 에`);
    }
    assert.ok(stepText(tutorialStep('skill'), { char }).includes(C.SKILL_DESC[char]), `${char} 스킬 설명`);
    assert.ok(stepText(tutorialStep('ult'), { char }).includes(C.ULT_DESC[char]), `${char} 필살기 설명`);
  }
  assert.ok(stepText(tutorialStep('jump'), { keyName: (id) => (id === 'jump' ? 'K' : id) }).includes('K 점프'), '바꾼 키 이름으로');
  assert.equal(progressLabel(1, 11), '2 / 11');
  assert.equal(nextStep(TUTORIAL_N - 1), null);
  assert.equal(nextStep(3), 4);
});

test('캐릭터마다 단계: 바드는 치명타 없음 (공중 평타가 천천히 낙하·기타 꽂기), 나머지는 전부', () => {
  for (const char of C.FIGURE_CHARS) {
    const ids = tutorialSteps(char).map((s) => s.id);
    if (char === 'bard') assert.ok(!ids.includes('crit') && ids.length === STEPS.length - 1);
    else assert.equal(ids.length, STEPS.length, char);
  }
});

test('지형·자리: 작은 판(10×10)·큰 판 모두 필드 안, 시작 자리는 바닥, 벽 위 목표는 벽 높이, 낙사 허수아비는 가장자리 가까이, 계단은 1칸씩', () => {
  for (const W of [10, 14, 19]) {
    for (const st of STEPS) {
      const L = tutorialLayout(st, W, W);
      const tops = new Map();
      for (const [x, y, z] of L.cells) {
        assert.ok(x >= 0 && x < W && y >= 0 && y < W, `${st.id} 칸 필드 안`);
        tops.set(`${x},${y}`, Math.max(tops.get(`${x},${y}`) || 0, z + 1));
      }
      const top = (x, y) => tops.get(`${Math.floor(x)},${Math.floor(y)}`) || 0;
      const inside = (p) => p.x > 0.4 && p.x < W - 0.4 && p.y > 0.4 && p.y < W - 0.4;
      assert.ok(inside(L.start), `${st.id} 시작 자리 필드 안`);
      assert.equal(top(L.start.x, L.start.y), 0, `${st.id} 시작은 바닥 (블록 안에 안 묻힘)`);
      for (const d of L.dummies) assert.ok(inside(d) && top(d.x, d.y) === 0, `${st.id} 허수아비 자리`);
      for (const it of L.items) assert.ok(it.x >= 0 && it.x < W && top(it.x, it.y) === 0, `${st.id} 아이템 자리`);
      if (st.id === 'jump') {
        assert.equal(top(L.target.x, L.target.y), st.minZ, '목표 = 2칸 벽 위');
        assert.ok(st.minZ * 1 > 1.28, '한 번 점프(약 1.28칸)로는 못 오름 → 2단 점프');
      }
      if (st.id === 'ringout' && W === 10) assert.ok(Math.min(W - L.dummies[0].x, L.dummies[0].x) <= 2, '낙사 허수아비는 가장자리 2칸 안 (튜토리얼 판은 혼자라 10×10)');
      if (st.id === 'climb') {
        const hs = st.stairs.map((s) => s[3]);
        for (let k = 1; k < hs.length; k++) assert.ok(hs[k] - hs[k - 1] <= 1, '계단은 1칸씩 (한 번 점프로)');
        assert.equal(Math.max(...hs), st.z, '꼭대기 높이 = 목표');
        assert.ok(hs[0] === 1 && st.z - C.TUTORIAL_LAVA_TOP_GAP > 0, '용암은 꼭대기보다 아래에서 멈춤');
      }
    }
  }
});

test('완료 판정 (judge): 단계 종류마다', () => {
  const st = (id) => tutorialStep(id);
  const me = (x, y, z = 0, grounded = true) => ({ x, y, z, grounded });
  assert.ok(judge(st('move'), { me: me(7.4, 7.6), target: { x: 7.5, y: 7.5 } }));
  assert.ok(!judge(st('move'), { me: me(5, 5), target: { x: 7.5, y: 7.5 } }));
  assert.ok(!judge(st('jump'), { me: me(8.5, 5.5, 1.2, false), target: { x: 8.5, y: 5.5 } }), '벽 위에 서야');
  assert.ok(judge(st('jump'), { me: me(8.5, 5.5, 2), target: { x: 8.5, y: 5.5 } }));
  assert.ok(judge(st('dash'), { dashed: true }) && !judge(st('dash'), {}));
  assert.ok(judge(st('push'), { dummyMax: 30 }) && !judge(st('push'), { dummyMax: 29 }));
  for (const [id, key] of [['ringout', 'ringout'], ['crit', 'crit'], ['skill', 'skill'], ['ult', 'ult'], ['item', 'itemUsed']]) {
    assert.ok(judge(st(id), { [key]: true }) && !judge(st(id), {}), id);
  }
  assert.ok(judge(st('dodge'), { dodged: 3 }) && !judge(st('dodge'), { dodged: 2 }));
  assert.ok(judge(st('climb'), { me: me(7, 5, 5) }) && !judge(st('climb'), { me: me(7, 5, 5, false) }) && !judge(st('climb'), { me: me(4, 5, 3) }));
});

test('튜토리얼 방: 비공개·로그 파일 없음·바로 시작, 첫 단계 지형, 넘기기로 끝까지 → done, 끝나면 허수아비·용암 치움', () => {
  const { rooms, logs, ws, conn, room, g, me, run } = setup('hook');
  assert.ok(room.tutorial && room.practice && !room.public);
  assert.equal(logs.length, 0, '로그 파일 없음');
  assert.equal(ws.msgs.find((m) => m.type === 'welcome').room.tutorial, true);
  assert.equal(g.phase, 'playing');
  assert.equal(g.W, 10, '혼자 판 = 10×10 (단계 자리가 이 크기 기준)');
  assert.equal(me.char, 'hook');
  const snap = g.snapshot(false).tutorial;
  assert.deepEqual([snap.i, snap.n, snap.id, snap.ok, snap.done], [0, STEPS.length, 'move', false, false]);
  assert.ok(snap.target);
  run(500);
  for (let i = 1; i < STEPS.length; i++) {
    rooms.message(conn, { type: 'tutorialSkip' });
    const t = g.tutorial.snapshot();
    assert.equal(t.i, i);
    assert.equal(t.id, STEPS[i].id);
    const L = tutorialLayout(STEPS[i], g.W, g.D);
    assert.equal(g.dummies().length, L.dummies.length, `${STEPS[i].id} 허수아비 수`);
    assert.equal(g.items.length, L.items.length, `${STEPS[i].id} 아이템 수`);
    assert.ok(Math.hypot(me.x - L.start.x, me.y - L.start.y) < 1e-6, `${STEPS[i].id} 처음 자리`);
    assert.equal(g.lava.active, STEPS[i].kind === 'climb', '용암은 마지막 단계만');
    run(300);
  }
  rooms.message(conn, { type: 'tutorialSkip' });
  const end = g.tutorial.snapshot();
  assert.ok(end.done && end.id === null && end.target === null);
  assert.equal(end.results.filter((r) => r === 'skip').length, STEPS.length);
  assert.equal(g.dummies().length, 0);
  assert.equal(g.lava.active, false);
  rooms.message(conn, { type: 'tutorialSkip' }); // 끝난 뒤 넘기기는 아무것도 안 함
  assert.ok(g.tutorial.done);
  run(2000);
  assert.equal(g.phase, 'playing', '판이 안 끝남 (연습 모드 위)');
});

test('튜토리얼은 아이템이 저절로 안 나옴 (단계가 놓은 것만), 연습 방에선 넘기기 메시지 무시', () => {
  const { g, run } = setup();
  run(20000);
  assert.equal(g.items.length, 0);
  const p = setup();
  p.rooms.message(p.conn, { type: 'tutorialSkip' });
  assert.equal(p.g.tutorial.i, 1);
  // 연습 방
  const rooms = new Rooms({ openLog: () => ({ log() {}, close() {} }), serverLog: () => {}, rng: Math.random });
  const conn = rooms.connect({ OPEN: 1, readyState: 1, send() {} });
  rooms.message(conn, { type: 'practice', nick: 'x' });
  rooms.message(conn, { type: 'tutorialSkip' });
  assert.equal(conn.room.game.tutorial, undefined);
});

test('해내면 tutorialOk → 잠깐 뒤 다음 단계 (그동안은 판정 안 함), 허수아비 피해 % 는 콤보가 끝나도 쌓인 채', () => {
  const { g, me, run } = setup();
  const L = tutorialLayout(STEPS[0], g.W, g.D);
  me.x = L.target.x;
  me.y = L.target.y;
  run(100);
  assert.ok(g.tutorial.okAt !== null);
  assert.equal(g.tutorial.results[0], 'ok');
  run(C.TUTORIAL_NEXT_MS / 2);
  assert.equal(g.tutorial.i, 0, '체크 보여 주는 중');
  run(C.TUTORIAL_NEXT_MS);
  assert.equal(g.tutorial.i, 1);
  // 밀기 단계: 허수아비 피해 % 를 직접 올려도 (맞은 것처럼) 콤보가 끝난 뒤 되돌아가지 않음
  while (g.tutorial.step.id !== 'push') g.tutorial.skip();
  const d = g.dummies()[0];
  d.damage = 20;
  run(3000);
  assert.equal(d.damage, 20, '쌓인 채');
});

test('블록 피하기: 내 자리를 덮는 블록, 깔리면 그 블록은 안 셈 (안 죽고 제자리) · 용암 단계: 닿으면 처음 자리 + 용암도 처음 높이', () => {
  const { g, me, run } = setup();
  while (g.tutorial.step.id !== 'dodge') g.tutorial.skip();
  run(C.TUTORIAL_DODGE_EVERY_MS + 100);
  const pc = g.pieces[0];
  assert.ok(pc, '블록이 떨어짐');
  const cover = pc.cells.some(([dx, dy]) => pc.px + dx === Math.floor(me.x) && pc.py + dy === Math.floor(me.y));
  assert.ok(cover, '내 자리를 덮음');
  run(C.TUTORIAL_DODGE_DROP_Z * C.TUTORIAL_DODGE_STEP_MS + 500); // 가만히 있으면 깔림
  assert.ok(me.alive, '안 죽음 (연습)');
  assert.equal(g.tutorial.ctx.dodged, 0, '깔린 건 안 셈');
  while (g.tutorial.step.id !== 'climb') g.tutorial.skip();
  run(5000);
  const z1 = g.lava.z;
  assert.ok(z1 > C.TUTORIAL_LAVA_START_Z, '용암이 오름');
  run(C.TUTORIAL_LAVA_MS_PER_CELL * 3); // 바닥에 서 있으면 잠김
  assert.ok(g.lava.z <= C.TUTORIAL_STEPS.find((s) => s.id === 'climb').z - C.TUTORIAL_LAVA_TOP_GAP + 1e-9);
  const L = tutorialLayout(g.tutorial.step, g.W, g.D);
  assert.ok(me.alive && Math.hypot(me.x - L.start.x, me.y - L.start.y) < 0.3, '닿으면 처음 자리');
  assert.ok(g.lava.z < z1 + 0.5, '용암도 처음 높이부터');
});

test('자동 조종으로 8명 모두 끝까지 (넘기기 없이 전부 해냄, 판 시간 2분 안)', () => {
  for (const [k, char] of C.FIGURE_CHARS.entries()) {
    const r = autoplay(char, 11 + k);
    assert.ok(r.done, `${char} 끝남`);
    assert.ok(r.results.every((x) => x === 'ok') && r.results.length === tutorialSteps(char).length, `${char}: ${r.results.join(',')}`);
    assert.ok(r.ms < 120000, `${char}: ${(r.ms / 1000).toFixed(0)}초`);
  }
});

// 봇 위치·지형 지능 (2026-10-26): 복귀 (공중 대시·2단 점프로 안쪽), 가장자리에서 안쪽, 그림자 밑에서 비켜남
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { CONFIG as C } from '../shared/config.js';

const TICK = 1000 / C.TICK_RATE;
function run(g, ms) {
  for (let t = 0; t < ms; t += TICK) g.tick(TICK);
}
function seeded(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

// 사람 1 (멀리 가만히) + 봇 1, 블록·아이템 없이
function setup(seed) {
  const g = new Game(() => {});
  g.rng = seeded(seed);
  const human = g.addPlayer(1);
  const bot = g.addBot();
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  Object.assign(human, { x: 8.5, y: 8.5 });
  return { g, human, bot, brain: g.bots.get(bot.id) };
}

test('봇 복귀: fallingOff — 발밑이 필드 밖이거나 넉백으로 필드 밖에 떨어질 참이면 true, 땅·안쪽이면 false', () => {
  const { g, bot, brain } = setup(1);
  Object.assign(bot, { x: 5, y: 5, z: 0, grounded: true, kbx: 0, kby: 0, vz: 0 });
  assert.equal(brain.fallingOff(g, bot), false, '땅');
  Object.assign(bot, { grounded: false, z: 1, vz: 0 });
  assert.equal(brain.fallingOff(g, bot), false, '안쪽 공중');
  Object.assign(bot, { x: 1, kbx: -8 });
  assert.equal(brain.fallingOff(g, bot), true, '밖으로 날아가는 중');
  Object.assign(bot, { x: -0.5, kbx: 0 });
  assert.equal(brain.fallingOff(g, bot), true, '발밑이 필드 밖');
});

test('봇 복귀: 밖으로 날려진 봇은 공중 대시로 넉백을 끊고 2단 점프로 버텨 필드 위로 돌아옴 (10번 모두)', () => {
  for (let seed = 1; seed <= 10; seed++) {
    const { g, bot } = setup(seed);
    // 왼쪽 끝에서 바깥으로 (밀치기 한 방 넉백쯤), 경직은 끝남
    Object.assign(bot, { x: 0.8, y: 5, z: 0.6, vz: 2, grounded: false, kbx: -6, kby: 0, stunUntil: 0 });
    let dashed = false;
    for (let t = 0; t < 2500 && bot.alive; t += TICK) {
      g.tick(TICK);
      if (bot.airDashes === 0) dashed = true;
    }
    assert.ok(dashed, `seed ${seed}: 공중 대시`);
    assert.ok(bot.alive && bot.grounded && g.inXY(Math.floor(bot.x), Math.floor(bot.y)), `seed ${seed}: 돌아옴 (${bot.x.toFixed(2)}, ${bot.z.toFixed(2)})`);
  }
});

test('봇 복귀: 경직 중에는 못 함 (사람과 같음) — 경직이 풀린 뒤에야 움직임', () => {
  const { g, bot, brain } = setup(2);
  Object.assign(bot, { x: 0.8, y: 5, z: 2, vz: 0, grounded: false, kbx: -6, kby: 0, stunUntil: g.time + 1000 });
  assert.equal(brain.recover(g, bot), false);
  assert.equal(bot.airDashes, C.AIR_DASHES);
});

test('봇: 가장자리에 붙어 서 있으면 안쪽으로 들어감 (10번 모두)', () => {
  for (let seed = 1; seed <= 10; seed++) {
    const { g, bot } = setup(seed);
    Object.assign(bot, { x: 0.4, y: 5, z: 0, grounded: true, kbx: 0, kby: 0 });
    run(g, 1000);
    assert.ok(bot.x > 0.9, `seed ${seed}: x=${bot.x.toFixed(2)}`);
  }
});

test('봇: 상대 뒤를 잡으러 가는 자리는 필드 끝에서 BOT_EDGE_MARGIN 안', () => {
  const { g, human, bot } = setup(3);
  // 상대가 왼쪽 끝 가까이 → 밀 방향은 왼쪽(끝), 봇은 상대 오른쪽(안쪽) 뒤로. 상대가 위쪽 끝에도 붙어 있어도 봇 자리는 끝에서 여유
  Object.assign(human, { x: 1.0, y: 0.6 });
  Object.assign(bot, { x: 5, y: 5 });
  run(g, 2500);
  assert.ok(bot.y >= C.BOT_EDGE_MARGIN - 0.35 && bot.x >= C.BOT_EDGE_MARGIN - 0.35, `봇 (${bot.x.toFixed(2)}, ${bot.y.toFixed(2)})`);
});

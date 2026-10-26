// 이동 스킬 예고 (2026-10-26 재혁, docs/characters.md 2절): 닌자·탱크·갈고리 F 는 지상이면 준비 SKILL_WINDUP_MS, 공중이면 바로.
// 갈고리 F 판정은 갈고리가 닿는 순간 (HOOK_FLY_MS 뒤)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { CONFIG as C } from '../shared/config.js';

const TICK = 1000 / C.TICK_RATE;
function run(g, ms) {
  for (let t = 0; t < ms; t += TICK) g.tick(TICK);
}

function setupChars(chars) {
  const lines = [];
  const g = new Game((s) => lines.push(s), { characters: true });
  g.rng = () => 0.5;
  chars.forEach((c, i) => {
    g.addPlayer(i + 1);
    g.setChar(i + 1, c);
  });
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  return { g, lines, p: (id) => g.players.get(id) };
}

function place(p, x, y, yaw = 0, z = 0) {
  Object.assign(p, { x, y, z, yaw, vz: 0, kbx: 0, kby: 0, grounded: true, stunUntil: 0, freezeUntil: 0 });
}

test('이동 스킬 예고: 수치·대상 캐릭터', () => {
  assert.equal(C.SKILL_WINDUP_MS, 150);
  assert.deepEqual([...C.SKILL_WINDUP_CHARS].sort(), ['hook', 'ninja', 'tank']);
});

test('이동 스킬 예고: 지상에서 쓰면 skillWindup 이벤트 → SKILL_WINDUP_MS 뒤 누른 순간 방향으로 나감 (쿨타임은 누를 때)', () => {
  for (const ch of ['tank', 'ninja', 'hook']) {
    const { g, lines, p } = setupChars([ch, 'builder', 'builder']);
    place(p(1), 1.5, 4.5, 0); // +x 를 봄
    place(p(2), 4, 4.6);
    place(p(3), 9.5, 9.5);
    g.drainEvents();
    g.handleAction(1, { name: 'skill' });
    const ev = g.drainEvents();
    assert.ok(ev.some((e) => e.type === 'skillWindup' && e.who === 1 && e.kind === ch && e.ms === C.SKILL_WINDUP_MS), ch);
    assert.ok(!ev.some((e) => e.type === 'skill'), `${ch}: 아직 안 나감`);
    assert.ok(p(1).skillReadyAt > g.time, `${ch}: 쿨타임은 누를 때`);
    assert.ok(lines.includes(`  [스킬] P1 ${C.CHAR_NAMES[ch]} F 준비`));
    p(1).yaw = Math.PI; // 준비 중에 돌아봐도 누른 방향으로
    run(g, C.SKILL_WINDUP_MS - TICK);
    assert.ok(!g.drainEvents().some((e) => e.type === 'skill'), `${ch}: 준비 중`);
    assert.equal(p(2).damage, 0);
    run(g, 2 * TICK);
    assert.ok(g.drainEvents().some((e) => e.type === 'skill' && e.who === 1), `${ch}: 나감`);
    if (ch === 'tank') assert.ok(p(1).chargeDir.x > 0.99, '돌진은 누른 방향');
    if (ch === 'ninja') assert.ok(p(1).x > 4, `순간 베기는 누른 방향 x=${p(1).x.toFixed(2)}`);
    if (ch === 'hook') {
      assert.ok(p(1).hookFly && Math.cos(p(1).hookFly.yaw) > 0.99, '갈고리는 누른 방향으로 던짐');
      run(g, C.HOOK_FLY_MS + TICK);
    }
    run(g, 400);
    assert.ok(p(2).damage > 0, `${ch}: 맞음`);
  }
});

test('이동 스킬 예고: 공중에서 쓰면 바로 (준비 없음). 다른 캐릭터 F 는 지상이어도 예전 그대로', () => {
  for (const ch of ['tank', 'ninja', 'hook']) {
    const { g, p } = setupChars([ch, 'builder']);
    place(p(1), 1.5, 4.5, 0, 1);
    place(p(2), 9.5, 9.5);
    Object.assign(p(1), { grounded: false, vz: 1 });
    g.drainEvents();
    g.handleAction(1, { name: 'skill' });
    const ev = g.drainEvents();
    assert.ok(!ev.some((e) => e.type === 'skillWindup'), ch);
    assert.ok(ev.some((e) => e.type === 'skill' && e.who === 1), `${ch}: 바로 나감`);
    assert.equal(p(1).windup, null);
  }
  for (const ch of ['builder', 'hunter', 'cannon', 'berserker']) {
    const { g, p } = setupChars([ch, 'tank']);
    place(p(1), 4.5, 4.5, 0);
    place(p(2), 9.5, 9.5);
    g.drainEvents();
    g.handleAction(1, { name: 'skill' });
    assert.ok(!g.drainEvents().some((e) => e.type === 'skillWindup'), ch);
    assert.equal(p(1).windup, null, ch);
  }
});

test('이동 스킬 예고: 준비 중에 맞으면 끊기고 (interrupt) 쿨타임 돌려줌, 나중에 안 나감. 준비 중은 카운터 대상', () => {
  const { g, p } = setupChars(['ninja', 'tank', 'builder']);
  place(p(1), 3, 4.5, Math.PI); // 왼쪽을 봄
  place(p(2), 2, 4.5, 0); // 왼쪽에서 나를 봄
  place(p(3), 9.5, 9.5);
  g.handleAction(1, { name: 'skill' });
  assert.ok(p(1).windup);
  assert.equal(g.busy(p(1)), true, '준비 중 = 카운터 대상');
  g.drainEvents();
  g.applyKnockback(p(1), 1, 0, 3, 1, 300, 5, { by: 2, kind: 'push' });
  const ev = g.drainEvents();
  assert.ok(ev.some((e) => e.type === 'interrupt' && e.who === 1 && e.kind === 'skill'));
  assert.equal(p(1).windup, null);
  assert.equal(p(1).skillReadyAt, g.time, '쿨타임 돌려줌');
  run(g, C.SKILL_WINDUP_MS + TICK);
  assert.ok(!g.drainEvents().some((e) => e.type === 'skill' && e.who === 1), '끊긴 F 는 안 나감');
});

test('갈고리 F: 판정은 갈고리가 닿는 순간 — 그 사이 옆으로 피하면 빗나감, 그대로면 HOOK_FLY_MS 에 끌려옴', () => {
  // 공중에서 던짐 (준비 없음) → 비행 시간만 봄
  for (const dodge of [false, true]) {
    const { g, lines, p } = setupChars(['hook', 'ninja']);
    place(p(1), 1.5, 4.5, 0, 0.5);
    Object.assign(p(1), { grounded: false, vz: 0 });
    place(p(2), 4.5, 4.5);
    g.drainEvents();
    g.handleAction(1, { name: 'skill' });
    const ev = g.drainEvents();
    assert.ok(ev.some((e) => e.type === 'hookThrow' && e.who === 1 && e.ms === C.HOOK_FLY_MS));
    assert.ok(!ev.some((e) => e.type === 'hook'), '아직 안 닿음');
    assert.ok(p(1).skillReadyAt > g.time, '쿨타임');
    assert.equal(p(2).damage, 0);
    if (dodge) place(p(2), 4.5, 6.5); // 옆으로 2칸 (시야 반각 밖)
    while (p(1).hookFly) g.tick(TICK);
    const hit = g.drainEvents().find((e) => e.type === 'hook');
    assert.ok(hit, '닿는 순간 hook 이벤트');
    if (dodge) {
      assert.equal(hit.target, null);
      assert.equal(p(2).damage, 0, '피함');
      assert.ok(lines.includes('  [스킬] P1 갈고리 빗나감'));
    } else {
      assert.equal(hit.target, 2);
      assert.equal(p(2).damage, C.HOOK_DAMAGE, '끌려옴');
    }
  }
});

test('갈고리 F: 지상이면 준비 + 비행 (SKILL_WINDUP_MS + HOOK_FLY_MS), 날아가는 중에 맞으면 끊기고 쿨타임 돌려줌', () => {
  const { g, p } = setupChars(['hook', 'ninja', 'tank']);
  place(p(1), 1.5, 4.5, 0);
  place(p(2), 4.5, 4.5);
  place(p(3), 9.5, 9.5);
  g.handleAction(1, { name: 'skill' });
  run(g, C.SKILL_WINDUP_MS + TICK);
  assert.ok(p(1).hookFly, '준비 끝 → 던짐');
  assert.equal(p(2).damage, 0);
  g.drainEvents();
  g.applyKnockback(p(1), 0, 1, 3, 1, 300, 5, { by: 3, kind: 'push' });
  assert.ok(g.drainEvents().some((e) => e.type === 'interrupt' && e.who === 1 && e.kind === 'skill'));
  assert.equal(p(1).hookFly, null);
  assert.equal(p(1).skillReadyAt, g.time);
  run(g, C.HOOK_FLY_MS + TICK);
  assert.equal(p(2).damage, 0, '끊긴 갈고리는 안 닿음');
});

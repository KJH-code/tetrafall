// 캐릭터 테스트: 패시브 · 스킬 F (쿨타임) · 필살기 R (게이지)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';

const TICK = 1000 / C.TICK_RATE;
function run(g, ms) {
  for (let t = 0; t < ms; t += TICK) g.tick(TICK);
}

// 사람 2~3명, 캐릭터 지정, 평지, 블록·아이템 없이
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

// 평타 한 번: 누르고 준비 시간 뒤 판정까지
function basic(g, id) {
  g.handleAction(id, { name: 'push' });
  const atk = g.players.get(id).atk;
  if (atk) run(g, atk.at - g.time + TICK / 2);
}

function place(p, x, y, yaw = 0, z = 0) {
  Object.assign(p, { x, y, z, yaw, vz: 0, kbx: 0, kby: 0, grounded: true, stunUntil: 0, freezeUntil: 0 });
}

test('캐릭터: 판 사이에만 고름, 사람 기본 탱크, 봇은 무작위, 판 시작 로그에 캐릭터 줄. 캐릭터를 끈 게임은 예전 그대로', () => {
  const lines = [];
  const g = new Game((s) => lines.push(s), { characters: true });
  g.addPlayer(1);
  assert.equal(g.players.get(1).char, C.CHAR_DEFAULT);
  g.rng = () => 0.99;
  assert.equal(g.addBot().char, C.CHARACTERS.at(-1));
  assert.ok(g.setChar(1, 'ninja'));
  assert.equal(g.setChar(1, 'wizard'), false);
  g.startRound();
  assert.equal(g.setChar(1, 'tank'), false, '판 중엔 못 바꿈');
  assert.ok(lines.includes(`  캐릭터: P1 닌자 / P2(봇) ${C.CHAR_NAMES[C.CHARACTERS.at(-1)]}`));
  const old = new Game();
  old.addPlayer(1);
  assert.equal(old.players.get(1).char, null);
  assert.equal(old.setChar(1, 'ninja'), false);
});

test('필살기 게이지: 피해 % 를 주거나 받은 만큼 참, 다 차야 R, 쓰면 0', () => {
  const { g, p } = setupChars(['tank', 'ninja']);
  place(p(1), 4, 4, 0);
  place(p(2), 5, 4);
  basic(g, 1);
  const dmg = C.BASIC_ATTACKS.tank.chain[0].dmg;
  assert.equal(p(1).ult, dmg * C.ULT_PER_DAMAGE, '때린 쪽');
  assert.equal(p(2).ult, dmg * C.ULT_PER_DAMAGE, '맞은 쪽');
  g.handleAction(1, { name: 'ult' });
  assert.ok(p(1).ult > 0, '안 찼으면 안 씀');
  p(1).ult = C.ULT_MAX;
  run(g, C.STUN_MS + 100);
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, 0);
});

test('탱크: 덜 밀림 (피해 % 배율 넉백 × TANK_KB_TAKEN, 평타 중간 타 고정 넉백은 그대로), 돌진은 처음 부딪힌 상대를 치고 멈춤 (쿨타임), 빗나가면 약 3칸', () => {
  const { g, lines, p } = setupChars(['tank', 'builder', 'builder']);
  // 같은 공격: 탱크는 덜 밀리고, 피해 % 는 같음
  g.applyKnockback(p(1), 1, 0, 5, 0, C.STUN_MS, 20, null, true);
  g.applyKnockback(p(2), 1, 0, 5, 0, C.STUN_MS, 20, null, true);
  assert.equal(p(1).damage, 20);
  assert.equal(p(2).damage, 20);
  assert.ok(Math.abs(p(1).kbx / p(2).kbx - C.TANK_KB_TAKEN) < 1e-9);
  run(g, C.STUN_MS + C.COMBO_IFRAME_MS + 100);
  g.applyKnockback(p(1), 1, 0, 2, 0, C.STUN_MS, 5, null, false, { fixed: true });
  g.applyKnockback(p(2), 1, 0, 2, 0, C.STUN_MS, 5, null, false, { fixed: true });
  assert.equal(p(1).kbx, 2, '고정 넉백은 탱크도 그대로');
  assert.equal(p(2).kbx, 2);
  run(g, C.STUN_MS + C.COMBO_IFRAME_MS + 100);
  p(1).damage = 0;
  p(2).damage = 0;
  // 돌진
  place(p(1), 1.5, 4.5, 0);
  place(p(2), 3.5, 4.5);
  place(p(3), 8.5, 8.5);
  g.drainEvents();
  g.handleAction(1, { name: 'skill' });
  assert.ok(g.drainEvents().some((e) => e.type === 'charge' && e.who === 1), '돌진 이벤트 (남에게 보이게)');
  run(g, C.TANK_CHARGE_MS + 100);
  assert.equal(p(2).damage, C.TANK_CHARGE_DAMAGE);
  assert.ok(p(1).x < 3.5, `부딪히고 멈춤 x=${p(1).x.toFixed(2)}`);
  assert.ok(lines.some((l) => l.startsWith('  [돌진] P1 → P2')));
  const ready = p(1).skillReadyAt;
  g.handleAction(1, { name: 'skill' });
  assert.equal(p(1).skillReadyAt, ready, '쿨타임 중엔 안 씀');
  // 빗나가면 약 3칸
  run(g, C.SKILL_CD_MS.tank);
  place(p(1), 1.5, 1.5, 0);
  g.handleAction(1, { name: 'skill' });
  run(g, 1000);
  const d = p(1).x - 1.5;
  assert.ok(d > 2.5 && d < 4, `빗나간 돌진 거리 ${d.toFixed(2)}`);
});

test('탱크: 내려찍기는 떠올랐다가 예고 시간 뒤 쾅, 주변 상대를 위로 띄움 (먼 상대는 무사)', () => {
  const { g, lines, p } = setupChars(['tank', 'ninja', 'ninja']);
  place(p(1), 5, 5);
  place(p(2), 6.5, 5);
  place(p(3), 9.5, 9.5);
  p(1).ult = C.ULT_MAX;
  g.drainEvents();
  g.handleAction(1, { name: 'ult' });
  assert.ok(g.drainEvents().some((e) => e.type === 'slamWarn' && e.r === C.TANK_SLAM_RANGE), '바닥 예고');
  assert.equal(p(2).damage, 0, '바로는 안 맞음');
  run(g, C.TANK_SLAM_WINDUP_MS + TICK);
  assert.equal(p(2).damage, C.TANK_SLAM_DAMAGE);
  assert.ok(p(2).vz > 0 || p(2).z > 0.5, '위로 뜸');
  assert.equal(p(3).damage, 0);
  assert.ok(lines.includes('  [필살] P1 내려찍기 (1명)'));
});

test('캐릭터: 팀전이면 같은 팀은 내려찍기 대상이 아님', () => {
  const lines = [];
  const g = new Game((s) => lines.push(s), { characters: true });
  g.rng = () => 0.5;
  for (let i = 1; i <= 2; i++) g.addPlayer(i);
  g.setChar(1, 'tank');
  g.setTeamMode(true);
  g.setTeam(1, 'red');
  g.setTeam(2, 'red');
  g.addPlayer(3);
  g.setChar(3, 'ninja'); // 탱크면 패시브로 피해가 덜 쌓임
  g.setTeam(3, 'blue');
  g.startRound();
  const p = (id) => g.players.get(id);
  place(p(1), 5, 5);
  place(p(2), 6, 5);
  place(p(3), 4, 5);
  p(1).ult = C.ULT_MAX;
  g.handleAction(1, { name: 'ult' });
  run(g, C.TANK_SLAM_WINDUP_MS + TICK);
  assert.equal(p(2).damage, 0, '같은 팀');
  assert.equal(p(3).damage, C.TANK_SLAM_DAMAGE);
});

// ---------- 캐릭터 평타 (2026-10-25) ----------

// 매 틱 누르고 있으면 (후딜 중 누른 것은 기다렸다 나감) 지상 평타가 끝까지 이어져 한 콤보 마무리
function fullChain(char, damage) {
  const { g, lines, p } = setupChars([char, 'ninja']);
  place(p(1), 3, 4.5, 0);
  place(p(2), 4.2, 4.5);
  p(2).damage = damage;
  g.drainEvents();
  const events = [];
  for (let t = 0; t < 3000 && !lines.some((l) => l.includes(' 마무리')); t += TICK) {
    g.handleAction(1, { name: 'push' });
    g.tick(TICK);
    events.push(...g.drainEvents());
  }
  return { g, lines, p, events };
}

for (const char of C.CHARACTERS.filter((c) => C.BASIC_ATTACKS[c].chain.at(-1).finish && C.BASIC_ATTACKS[c].chain.length > 1)) {
  test(`평타 ${char}: 바로바로 누르면 0% 에서도 150% 에서도 1타부터 마지막 타까지 한 콤보 → 마무리, 피해 합 = 타별 딜 합`, () => {
    const chain = C.BASIC_ATTACKS[char].chain;
    for (const dmg0 of [0, 150]) {
      const { lines, p, events } = fullChain(char, dmg0);
      const n = chain.length;
      assert.ok(lines.includes(`  [콤보] P1 → P2 ${n}타 마무리`), `${dmg0}%:\n${lines.join('\n')}`);
      const eff = chain.map((d) => d.loaded || d); // 갈고리는 판 시작에 장전 → 3타 탕
      assert.equal(p(2).damage - dmg0, eff.reduce((a, d) => a + d.dmg, 0));
      const atk = events.filter((e) => e.type === 'attack' && e.who === 1);
      assert.deepEqual(atk.map((e) => e.n), chain.map((_, i) => i + 1), '타 번호');
      assert.deepEqual(atk.map((e) => e.windup), eff.map((d) => d.windup), '준비 시간');
      assert.ok(atk.every((e) => e.char === char && e.air === false));
      assert.equal(atk.at(-1).finish, true, '마지막 타 예고');
      const hits = events.filter((e) => e.type === 'hit' && e.by === 1);
      assert.ok(hits.every((e) => e.ok) && hits.at(-1).finish);
    }
  });
}

test('평타: 경직은 후딜 + 다음 타 준비 + 0.1초 이상 (바로 누르면 확정), 마무리 타만 finish (닌자는 지상 4타가 아니라 공중 2타), 풀 콤보 최단 시간 ≤ COMBO_MS', () => {
  for (const char of C.CHARACTERS) {
    const { chain, air } = C.BASIC_ATTACKS[char];
    // 지상 마지막 타가 마무리가 아니고 공중 마지막 타가 마무리 (사냥꾼: 2026-10-26 재혁 가·ㄱ — 찔러 넣기 마무리 아님, 공중 내려 베기 마무리)
    const ninja = char === 'ninja' || char === 'tank' || char === 'hunter';
    let t = 0;
    chain.forEach((d, i) => {
      assert.equal(!!d.finish, !ninja && i === chain.length - 1, `${char} ${i + 1}타`);
      if (i === chain.length - 1) return;
      assert.ok(d.stun >= d.rec + chain[i + 1].windup + 100, `${char} ${i + 1}타 경직 ${d.stun}`);
      t += d.rec + chain[i + 1].windup;
    });
    assert.ok(t <= C.COMBO_MS, `${char} 최단 ${t}`);
    air.forEach((d, i) => {
      assert.equal(!!d.finish, ninja && i === air.length - 1, `${char} 공중 ${i + 1}타`);
      if (i < air.length - 1) assert.ok(d.stun >= d.rec + air[i + 1].windup + 100, `${char} 공중 ${i + 1}타 경직`);
    });
  }
  assert.equal(C.BASIC_ATTACKS.ninja.chain.length, 4);
  assert.equal(C.BASIC_ATTACKS.ninja.air.length, 2);
  assert.ok(C.BASIC_ATTACKS.ninja.chain[3].rec > 2 * C.BASIC_ATTACKS.ninja.chain[2].rec, '연타 마지막 타 뒤 후딜은 김');
});

test('평타: 중간 타 넉백은 피해 % 와 상관없이 같음, 마무리 타는 % 가 높을수록 멀리', () => {
  const kb = (dmg, finish) => {
    const { g, p } = setupChars(['tank', 'ninja']);
    place(p(2), 5, 5);
    p(2).damage = dmg;
    const d = C.BASIC_ATTACKS.tank.chain[finish ? 2 : 0];
    if (finish) g.applyKnockback(p(2), 1, 0, 1, 0, 500, 0, null); // 콤보 1타를 먼저
    g.applyKnockback(p(2), 1, 0, d.kb, d.up, d.stun, d.dmg, null, finish, { fixed: !finish, finish });
    return p(2).kbx;
  };
  assert.equal(kb(0, false), kb(150, false));
  assert.equal(kb(0, false), C.BASIC_ATTACKS.tank.chain[0].kb);
  assert.ok(kb(150, true) > kb(0, true) * 2);
});

test('평타: 이어 치기 창을 놓치면 1타부터, 허공 이어 치기 (빗나가도 다음 타, 후딜은 다 받음), 맞으면 준비 중인 평타가 끊김', () => {
  const { g, p } = setupChars(['tank', 'ninja', 'ninja']);
  const chain = C.BASIC_ATTACKS.tank.chain;
  place(p(1), 3, 4.5, 0);
  place(p(2), 4.2, 4.5);
  place(p(3), 9.5, 9.5);
  basic(g, 1);
  assert.equal(p(1).chainN, 1);
  run(g, chain[0].rec + C.BASIC_CHAIN_WINDOW_MS + C.COMBO_IFRAME_MS + 100); // 늦게 누름
  place(p(2), 4.2, 4.5);
  g.drainEvents();
  basic(g, 1);
  assert.equal(g.drainEvents().find((e) => e.type === 'attack').n, 1, '놓치면 1타');
  // 허공 이어 치기: 빗나가도 2타 → 3타로, 후딜은 다 받음
  run(g, 1000);
  p(1).yaw = Math.PI;
  p(1).chainN = 0;
  basic(g, 1);
  assert.equal(p(1).atkLanded, false);
  assert.equal(p(1).chainN, 1, '빗나가도 다음은 2타');
  assert.ok(p(1).pushReadyAt - g.time > chain[0].rec - 2 * TICK, '후딜은 다 받음');
  run(g, p(1).pushReadyAt - g.time + TICK);
  g.drainEvents();
  basic(g, 1);
  assert.equal(g.drainEvents().find((e) => e.type === 'attack').n, 2);
  // 준비 중에 맞으면 끊김
  run(g, 1000);
  p(1).yaw = 0;
  g.handleAction(1, { name: 'push' });
  assert.ok(p(1).atk);
  g.applyKnockback(p(1), -1, 0, 1, 0, 300, 5, { by: 3, kind: 'push' });
  assert.equal(p(1).atk, null);
});

test('평타: 공중 평타 (건축가는 한 타, 공중 1타), 떨어지며 위에서 치면 치명타', () => {
  const { g, lines, p } = setupChars(['builder', 'ninja']);
  place(p(1), 3, 4.5, 0, 1);
  Object.assign(p(1), { grounded: false, vz: -1 });
  place(p(2), 4, 4.5);
  g.drainEvents();
  g.handleAction(1, { name: 'push' });
  const e = g.drainEvents().find((x) => x.type === 'attack');
  assert.equal(e.n, 1, '공중 1타');
  assert.equal(e.air, true);
  assert.equal(e.name, C.BASIC_ATTACKS.builder.air[0].name);
  p(1).vz = -1; // 준비 시간 동안 떨어지는 중으로 둠
  p(1).z = 1;
  run(g, C.BASIC_ATTACKS.builder.air[0].windup + TICK / 2);
  assert.ok(lines.some((l) => l.includes('넉백 치명타') && l.endsWith(`공중 ${C.BASIC_ATTACKS.builder.air[0].name}`)), lines.join('\n'));
  assert.equal(p(2).damage, Math.round(C.BASIC_ATTACKS.builder.air[0].dmg * C.CRIT_DAMAGE_MULT));
});

test('평타 건축가: 내려찍기(마무리) 가 맞으면 그 사람 발밑 기둥 위에 블록 1칸 솟고, 그 사람은 블록 위로', () => {
  const { g, p, events } = fullChain('builder', 0);
  const cx = Math.floor(p(2).x);
  const cy = Math.floor(p(2).y);
  const rise = events.find((e) => e.type === 'wallRise' && e.who === 1);
  assert.ok(rise, '블록 솟음 이벤트');
  const [x, y, z] = rise.cells[0];
  assert.equal(g.gridAt(x, y, z), CELL.BUILD);
  assert.equal(z, 0);
  assert.ok(Math.abs(x - cx) <= 1 && Math.abs(y - cy) <= 1);
  assert.ok(p(2).z >= 1 - 1e-6 || p(2).vz > 0, `위로 z=${p(2).z}`);
});

test('평타: 마무리 타 준비 중에는 이동 속도 × BASIC_FINISH_MOVE_MULT. 아이템 망치는 없음 (2026-10-25)', () => {
  const { g, p } = setupChars(['tank', 'ninja']);
  place(p(1), 3, 1.5, 0);
  p(1).atk = { n: 3, def: C.BASIC_ATTACKS.builder.chain[2], at: g.time + 10000 };
  p(1).input = { fwd: 1, strafe: 0, jump: false };
  run(g, 200);
  const slow = p(1).x - 3;
  assert.ok(Math.abs(slow - C.MOVE_SPEED * 0.2 * C.BASIC_FINISH_MOVE_MULT) < 0.1, `${slow}`);
  assert.ok(!C.ITEM_POOL.includes('weapon') && !C.HELD_ITEMS.includes('weapon'), '망치 아이템 없음');
});

// ---------- F·R 캔슬, 카운터히트 (2026-10-25) ----------

test('캔슬: 평타가 맞은 뒤 후딜에 F 를 누르면 후딜을 끊고 바로 스킬, 이어 치기 창은 다시 열림', () => {
  const { g, p } = setupChars(['tank', 'ninja']);
  place(p(1), 3, 4.5, 0);
  place(p(2), 4.2, 4.5);
  basic(g, 1);
  assert.ok(p(1).atkLanded && g.time < p(1).pushReadyAt, '맞힌 뒤 후딜 중');
  g.drainEvents();
  g.handleAction(1, { name: 'skill' });
  assert.ok(g.drainEvents().some((e) => e.type === 'charge'), '바로 돌진');
  assert.ok(p(1).pushReadyAt <= g.time, '후딜 끊김');
  assert.ok(p(1).chainUntil > g.time && p(1).chainN === 1, '이어 치기 창');
});

test('캔슬: 평타가 빗나간 뒤 후딜에 누른 F 는 기억했다가 후딜이 끝나면 나감', () => {
  const { g, p } = setupChars(['tank', 'ninja']);
  place(p(1), 3, 4.5, Math.PI);
  place(p(2), 4.2, 4.5);
  basic(g, 1);
  assert.equal(p(1).atkLanded, false);
  const ready = p(1).pushReadyAt;
  g.drainEvents();
  g.handleAction(1, { name: 'skill' });
  assert.ok(!g.drainEvents().some((e) => e.type === 'charge'), '후딜 중엔 안 나감');
  assert.equal(p(1).castQueued, 'skill');
  run(g, ready - g.time - TICK);
  assert.ok(!g.drainEvents().some((e) => e.type === 'charge'));
  run(g, 2 * TICK);
  assert.ok(g.drainEvents().some((e) => e.type === 'charge'), '후딜 끝나고 나감');
});

test('캔슬: 평타 준비 중에 누른 F 는 판정을 기다림 (평타는 그대로 나감) — 맞으면 판정 직후, 빗나가면 후딜 뒤. R 도 같음', () => {
  for (const hit of [true, false]) {
    const { g, p } = setupChars(['tank', 'ninja']);
    place(p(1), 3, 4.5, hit ? 0 : Math.PI);
    place(p(2), 4.2, 4.5);
    g.handleAction(1, { name: 'push' });
    const { at } = p(1).atk;
    g.drainEvents();
    g.handleAction(1, { name: 'skill' });
    assert.ok(p(1).atk, '준비 중인 평타는 안 취소');
    run(g, at - g.time + TICK / 2);
    const ev = g.drainEvents();
    assert.ok(ev.some((e) => e.type === 'swing'), '평타 나감');
    assert.equal(ev.some((e) => e.type === 'charge'), hit, hit ? '맞았으면 바로 스킬' : '빗나가면 아직');
    if (!hit) {
      run(g, p(1).pushReadyAt - g.time + TICK);
      assert.ok(g.drainEvents().some((e) => e.type === 'charge'), '후딜 뒤 스킬');
    }
  }
  // R: 준비 중에 누르면 맞힌 직후 내려찍기
  const { g, p } = setupChars(['tank', 'ninja']);
  place(p(1), 3, 4.5, 0);
  place(p(2), 4.2, 4.5);
  p(1).ult = C.ULT_MAX;
  g.handleAction(1, { name: 'push' });
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, C.ULT_MAX, '준비 중엔 안 씀');
  run(g, p(1).atk.at - g.time + TICK / 2);
  assert.equal(p(1).ult, 0, '맞힌 직후 필살기');
  assert.ok(p(1).slamAt > 0);
});

// p3(갈고리)가 p1(탱크) 뒤에서 평타 1타. prep 으로 p1 의 상태를 만든 뒤
function hitBy3(prep, first = 'tank') {
  const { g, lines, p } = setupChars([first, 'ninja', 'hook']);
  place(p(1), 3, 4.5, 0);
  place(p(2), 8.5, 8.5);
  place(p(3), 2, 4.5, 0); // p1 뒤
  prep(g, p);
  g.drainEvents();
  basic(g, 3);
  return { lines, ev: g.drainEvents(), p, g };
}
const countered = (r) => r.ev.some((e) => e.type === 'counter');

test('카운터히트 (2026-10-25 재혁 결정): 빗나간 평타의 후딜·스킬·필살기 준비 중에 맞으면 경직 × COUNTER_STUN_MULT, 멈칫 × COUNTER_HITSTOP_MULT, 로그·이벤트', () => {
  const hookDef = C.BASIC_ATTACKS.hook.chain[0];
  const walk = hitBy3((g, p) => (p(1).input = { fwd: 1, strafe: 0, jump: false }));
  assert.ok(!countered(walk), '걷기만은 아님');
  // 빗나간 평타의 후딜
  const rec = hitBy3((g, p) => {
    p(1).yaw = Math.PI / 2;
    basic(g, 1);
  });
  assert.ok(rec.ev.some((e) => e.type === 'counter' && e.by === 3 && e.target === 1), '이벤트');
  assert.ok(rec.lines.includes('  [카운터] P3 → P1'), rec.lines.join('\n'));
  assert.ok(Math.abs(rec.p(1).stunUntil - rec.p(1).counterAt - hookDef.stun * C.COUNTER_STUN_MULT) < 1e-6, '경직 길게');
  assert.equal(rec.p(3).freezeUntil - rec.p(1).counterAt, C.BASIC_HITSTOP_MS * C.COUNTER_HITSTOP_MULT, '멈칫 길게');
  // 스킬 준비 (건축가 솟는 벽 예고)
  assert.ok(countered(hitBy3((g, p) => {
    p(1).yaw = Math.PI / 2;
    g.handleAction(1, { name: 'skill' });
    p(1).wallAt = g.time + 10000;
  }, 'builder')), '솟는 벽 준비');
  // 탱크 돌진·내려찍기 준비는 아머라 카운터 안 당함 (2026-10-25 예외)
  assert.ok(!countered(hitBy3((g, p) => {
    p(1).ult = C.ULT_MAX;
    g.handleAction(1, { name: 'ult' });
    p(1).slamAt = g.time + 10000;
  })), '탱크 내려찍기 준비 = 아머');
  assert.ok(!countered(hitBy3((g, p) => {
    p(1).yaw = Math.PI / 2;
    g.handleAction(1, { name: 'skill' });
    p(1).chargeUntil = g.time + 10000;
    p(1).chargeDir = { x: 0, y: 0 };
  })), '탱크 돌진 = 아머');
});

test('카운터히트 아님: 평타 준비 중, 맞힌 평타의 후딜, 동시에 누른 평타끼리, 이미 경직 중(콤보)', () => {
  // 평타 준비 중
  assert.ok(!countered(hitBy3((g, p) => {
    g.handleAction(1, { name: 'push' });
    p(1).atk.at = g.time + 10000;
  })), '준비 중');
  // 맞힌 평타의 후딜 (p1 이 p2 를 맞힘)
  assert.ok(!countered(hitBy3((g, p) => {
    place(p(2), 4.2, 4.5);
    basic(g, 1);
    assert.ok(p(1).atkLanded && g.time < p(1).pushReadyAt);
  })), '맞힌 뒤 후딜');
  // 마주 보고 같은 틱에 누름 → 준비가 짧은 닌자가 먼저 맞히고 탱크 평타는 끊김, 카운터 없음
  const { g, p } = setupChars(['tank', 'ninja']);
  place(p(1), 3, 4.5, 0);
  place(p(2), 4.2, 4.5, Math.PI);
  g.drainEvents();
  g.handleAction(1, { name: 'push' });
  g.handleAction(2, { name: 'push' });
  run(g, 300);
  const ev = g.drainEvents();
  assert.ok(!ev.some((e) => e.type === 'counter'), '동시에 누른 평타끼리는 카운터 아님');
  assert.ok(ev.some((e) => e.type === 'hit' && e.by === 2 && e.ok));
  assert.ok(ev.some((e) => e.type === 'interrupt' && e.who === 1 && e.kind === 'basic' && e.n === 1), '탱크 평타 끊김');
  assert.ok(!ev.some((e) => e.type === 'hit' && e.by === 1), '끊긴 평타는 안 나감');
  // 경직 중(콤보 다음 타)에는 카운터 아님
  const r = hitBy3((g, p) => {
    p(1).yaw = Math.PI / 2;
    basic(g, 1);
  });
  const at = r.p(1).counterAt;
  run(r.g, 200);
  r.p(3).pushReadyAt = 0;
  r.p(3).chainN = 0; // 다시 1타 (2타 주먹은 마무리라 콤보가 끝남)
  basic(r.g, 3);
  assert.equal(r.p(1).counterAt, at);
  assert.equal(r.p(1).comboHits, 2);
});

test('끊긴 공격은 소모 없음: 맞아서 끊긴 평타는 후딜 없음, 돌진은 쿨타임, 내려찍기 준비는 게이지를 돌려줌 (interrupt 이벤트). 경직 중 F·R 은 안 나가고 소모도 없음, 기억한 F 가 맞아서 지워져도 소모 없음', () => {
  const { g, p } = setupChars(['tank', 'ninja']);
  const hit = (finish = false) => {
    g.applyKnockback(p(1), -1, 0, 1, 0, 300, 5, { by: 2, kind: 'push' }, finish, { finish }); // 탱크 아머는 마무리 타에만 깨짐
    return g.drainEvents().filter((e) => e.type === 'interrupt' && e.who === 1);
  };
  place(p(1), 3, 4.5, 0);
  place(p(2), 8.5, 8.5);
  // 평타 준비 중에 맞음
  g.handleAction(1, { name: 'push' });
  g.drainEvents();
  assert.deepEqual(hit().map((e) => [e.kind, e.n]), [['basic', 1]]);
  assert.ok(p(1).pushReadyAt <= g.time, '후딜 없음');
  // 경직 중 F·R: 안 나가고 소모 없음
  p(1).ult = C.ULT_MAX;
  g.handleAction(1, { name: 'skill' });
  g.handleAction(1, { name: 'ult' });
  assert.ok(p(1).skillReadyAt <= g.time);
  assert.equal(p(1).ult, C.ULT_MAX);
  assert.equal(p(1).castQueued, null, '경직 중 입력은 기억 안 함');
  run(g, 1000); // 경직(카운터면 ×1.5) + 무적이 끝나게
  // 돌진 중에 맞음 (아머를 깨는 마무리 타) → 쿨타임 돌려받음
  place(p(1), 3, 4.5, Math.PI / 2);
  g.handleAction(1, { name: 'skill' });
  assert.ok(p(1).skillReadyAt > g.time);
  g.drainEvents();
  assert.deepEqual(hit(true).map((e) => e.kind), ['skill']);
  assert.ok(p(1).skillReadyAt <= g.time, '쿨 돌려받음');
  run(g, 1000); // 경직(카운터면 ×1.5) + 무적이 끝나게
  // 내려찍기 준비 중에 맞음 → 게이지 돌려받음
  place(p(1), 3, 4.5, 0);
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, 0);
  g.drainEvents();
  assert.deepEqual(hit(true).map((e) => e.kind), ['ult']);
  assert.equal(p(1).ult, C.ULT_MAX, '게이지 돌려받음');
  run(g, 1000); // 경직(카운터면 ×1.5) + 무적이 끝나게
  // 평타 준비 중 기억한 F 가 맞아서 지워짐 → 소모 없음
  place(p(1), 3, 4.5, 0);
  g.handleAction(1, { name: 'push' });
  g.handleAction(1, { name: 'skill' });
  assert.equal(p(1).castQueued, 'skill');
  g.drainEvents();
  hit();
  assert.equal(p(1).castQueued, null);
  assert.ok(p(1).skillReadyAt <= g.time, '스킬 쿨 그대로');
  run(g, 1000);
  assert.ok(!g.drainEvents().some((e) => e.type === 'charge'), '나중에도 안 나감');
});

test('로그: 마무리 타의 [콤보] 줄은 그 [평타] 줄 다음에', () => {
  const { lines } = fullChain('builder', 0);
  const i = lines.findIndex((l) => l.includes('[콤보] P1 → P2 3타 마무리'));
  assert.ok(i > 0 && lines[i - 1].includes('[평타] P1 → P2') && lines[i - 1].endsWith('3타 내려찍기'), lines.join('\n'));
});

test('봇: 돌진·순간 베기 길에 피할 칸(내가 던진 블록 그림자 등)이 있으면 안 씀 (2026-10-25 재혁 로그: 자기 블록에 돌진해 깔림)', () => {
  for (const char of ['tank', 'ninja']) {
    const g = new Game(() => {}, { characters: true });
    g.rng = () => 0.5;
    const b = g.addBot();
    g.setChar(b.id, char);
    g.addPlayer(1);
    g.startRound();
    const t = g.players.get(1);
    place(b, 2.5, 4.5, 0);
    place(t, 4.6, 4.5);
    const brain = g.bots.get(b.id);
    const shadow = [[3, 4]]; // 둘 사이 칸
    assert.equal(brain.useSkills(g, b, t, [t], shadow), false, `${char}: 그림자를 지나가면 안 씀`);
    assert.equal(brain.useSkills(g, b, t, [t], []), true, `${char}: 없으면 씀`);
  }
});

// ---------- 건축가 (2026-10-25, docs/characters.md 3.1) ----------

const bb = (g, kind, owner = 1) => [...g.bblocks.values()].filter((b) => b.kind === kind && b.owner === owner);

test('건축가 F 지상: 예고 뒤 앞 가로 3 × 1층 벽이 솟고 그 칸의 상대를 띄움. 건축가 블록(벽, 한 묶음)이 되고 BUILDER_BLOCK_MS 뒤 사라짐', () => {
  const { g, lines, p } = setupChars(['builder', 'ninja']);
  place(p(1), 4.5, 4.5, 0); // +x 를 봄
  place(p(2), 5.5, 4.5); // 벽 칸 위
  g.drainEvents();
  g.handleAction(1, { name: 'skill' });
  assert.ok(g.drainEvents().some((e) => e.type === 'wallWarn' && e.cells.length === 3), '바닥 예고');
  assert.equal(g.gridAt(5, 4, 0), 0, '바로는 안 솟음');
  run(g, C.BUILDER_WALL_WARN_MS + TICK);
  for (const y of [3, 4, 5]) assert.equal(g.gridAt(5, y, 0), CELL.BUILD, `(5,${y},0)`);
  assert.equal(g.gridAt(5, 4, 1), 0, '1층');
  assert.equal(p(2).damage, C.BUILDER_WALL_DAMAGE);
  assert.ok(p(2).z >= 1 - 1e-6, `벽 위로 올라감 z=${p(2).z.toFixed(2)}`);
  assert.ok(lines.includes('  [스킬] P1 솟는 벽 (3칸, 1명 띄움)'), lines.join('\n'));
  const walls = bb(g, 'wall');
  assert.equal(walls.length, 3);
  assert.equal(new Set(walls.map((b) => b.group)).size, 1, '한 묶음');
  assert.ok(g.drainEvents().some((e) => e.type === 'bblock' && e.kind === 'wall' && e.cells.length === 3 && e.ms === C.BUILDER_BLOCK_MS));
  assert.equal(g.snapshot().bblocks.length, 3, '화면에 보냄');
  assert.ok(p(1).skillReadyAt > g.time + C.SKILL_CD_MS.builder - C.BUILDER_WALL_WARN_MS - 3 * TICK, `쿨 ${p(1).skillReadyAt - g.time}`);
  run(g, C.BUILDER_BLOCK_MS);
  assert.equal(g.gridAt(5, 4, 0), 0, '수명 끝');
  assert.equal(bb(g, 'wall').length, 0);
  assert.ok(g.drainEvents().some((e) => e.type === 'bblockGone' && e.why === 'expire'));
});

test('건축가 망치: 평타가 내 벽에 닿으면 폭발 — 같은 F 벽 묶음만 연쇄, 치는 방향 앞쪽 사람만 앞으로, 가까운 칸 수 × 피해, 나는 안 맞음, 1칸당 게이지. 상대 평타로는 안 터짐', () => {
  const { g, lines, p } = setupChars(['builder', 'ninja', 'tank']);
  place(p(1), 2.5, 4.5, 0);
  place(p(2), 4.6, 4.5); // 벽 앞 (평타 사거리 밖)
  place(p(3), 1.9, 4.5); // 벽 뒤 (내 뒤)
  g.handleAction(1, { name: 'skill' });
  run(g, C.BUILDER_WALL_WARN_MS + TICK); // x=3, y 3~5 벽
  g.placeBBlock(p(1), 3, 6, 0, 'wall', 999); // 붙어 있는 다른 F 벽
  g.placeBBlock(p(1), 3, 2, 0, 'third', 998); // 붙어 있는 3타 블록
  // 상대 평타로는 안 터짐
  place(p(3), 1.9, 4.5, 0);
  p(3).pushReadyAt = 0;
  basic(g, 3);
  assert.equal(g.gridAt(3, 4, 0), CELL.BUILD, '상대는 못 터뜨림');
  run(g, 1000);
  Object.assign(p(2), { damage: 0, ult: 0 });
  Object.assign(p(3), { damage: 0 });
  p(1).damage = 0; // 위에서 p3 평타에 맞은 것
  place(p(1), 2.5, 4.5, 0);
  place(p(2), 4.6, 4.5);
  place(p(3), 1.9, 4.5);
  p(1).ult = 0;
  p(1).pushReadyAt = 0;
  p(1).chainN = 0;
  g.drainEvents();
  basic(g, 1);
  for (const y of [3, 4, 5]) assert.equal(g.gridAt(3, y, 0), 0, `벽 (3,${y}) 터짐`);
  assert.equal(g.gridAt(3, 6, 0), CELL.BUILD, '다른 F 벽은 안 번짐');
  assert.equal(g.gridAt(3, 2, 0), CELL.BUILD, '3타 블록으로도 안 번짐');
  assert.equal(p(2).damage, 3 * C.BUILDER_BLAST_DAMAGE, '가까운 칸 3개');
  assert.ok(p(2).kbx > 0 && Math.abs(p(2).kby) < 1e-9, '치는 방향 앞으로');
  assert.equal(p(3).damage, 0, '벽 뒤(내 쪽)는 안 맞음');
  assert.equal(p(1).damage, 0, '나는 안 맞음');
  assert.equal(p(1).ult, 3 * C.BUILDER_BLAST_ULT + 3 * C.BUILDER_BLAST_DAMAGE * C.ULT_PER_DAMAGE, '패시브 1칸당 + 준 피해');
  const ev = g.drainEvents().find((e) => e.type === 'blast');
  assert.equal(ev.cells.length, 3);
  assert.deepEqual(ev.dir, { x: 1, y: 0 });
  assert.ok(lines.some((l) => l.startsWith('  [폭발] P1 벽 3칸 → P2')), lines.join('\n'));
  assert.equal(p(2).lastHit.kind, 'blast');
});

test('건축가 3타: 맞으면 상대 발밑, 빗나가면 앞 칸에 블록 (최대 3개, 오래된 것부터 사라짐). 버그: 몸이 옆 칸에 걸쳐 있어도 내 밑에서 솟지 않음', () => {
  // 버그 재현 자리: 내 몸(3.5~4.1)이 상대 칸(4)에 걸쳐 있음
  const { g, p } = setupChars(['builder', 'ninja']);
  place(p(1), 3.8, 4.5, 0);
  place(p(2), 4.6, 4.5);
  Object.assign(p(1), { chainN: 2, chainUntil: Infinity });
  basic(g, 1);
  run(g, 300);
  assert.ok(p(1).z < 0.5, `나는 안 뜸 z=${p(1).z.toFixed(2)}`);
  const [b] = bb(g, 'third');
  assert.ok(b && b.x >= 5, `블록은 내 몸과 안 겹치는 앞 칸 x=${b && b.x}`);
  // 빗나가면 앞 1.5칸, 최대 3개
  const { g: g2, p: p2 } = setupChars(['builder', 'ninja']);
  place(p2(2), 9.5, 9.5);
  const spots = [1.5, 3.5, 5.5, 7.5];
  for (const y of spots) {
    place(p2(1), 1.5, y, 0);
    g2.basicRaise(p2(1), null);
    run(g2, 10);
  }
  const thirds = bb(g2, 'third');
  assert.equal(thirds.length, C.BUILDER_THIRD_MAX);
  assert.deepEqual(thirds.map((t) => [t.x, t.y]).sort(), [[3, 3], [3, 5], [3, 7]], '제일 오래된 (3,1) 이 사라짐');
  assert.equal(g2.gridAt(3, 1, 0), 0);
});

test('건축가 F 공중: 발밑에 발판 + 위로 부스트, 지상 F 와 쿨 같이 씀. 필드 밖이면 칸 없이 부스트만', () => {
  const { g, lines, p } = setupChars(['builder', 'ninja']);
  place(p(2), 9.5, 9.5);
  place(p(1), 4.5, 4.5, 0, 2.5);
  Object.assign(p(1), { grounded: false, vz: -3 });
  g.drainEvents();
  g.handleAction(1, { name: 'skill' });
  assert.equal(g.gridAt(4, 4, 1), CELL.BUILD, '발밑 칸');
  assert.equal(bb(g, 'pad').length, 1);
  assert.equal(p(1).vz, C.BUILDER_PAD_BOOST);
  assert.ok(g.drainEvents().some((e) => e.type === 'padBoost' && e.who === 1));
  assert.ok(p(1).skillReadyAt > g.time);
  run(g, 1000);
  place(p(1), 2.5, 2.5, 0);
  g.handleAction(1, { name: 'skill' });
  assert.equal(p(1).wallAt, 0, '쿨 같이 씀');
  // 필드 밖에서 떨어지는 중
  run(g, C.SKILL_CD_MS.builder);
  place(p(1), -0.8, 4.5, 0, -0.5);
  Object.assign(p(1), { grounded: false, vz: -5 });
  g.handleAction(1, { name: 'skill' });
  assert.equal(p(1).vz, C.BUILDER_PAD_BOOST, '부스트만');
  assert.ok(lines.includes('  [스킬] P1 발판 (칸 없이 부스트)'));
});

test('건축가 R 대폭발: 앞 1칸 띄우고 3×3 이 바닥에서 솟아 위 사람을 띄움 → BUILDER_BIG_FUSE_MS 뒤 폭발. 범위 안 내 블록도 같이, R 블록은 패시브 게이지 없음. 망치로 치면 바로', () => {
  const { g, lines, p } = setupChars(['builder', 'ninja']);
  place(p(1), 1.5, 4.5, 0);
  place(p(2), 4.5, 4.5); // 3×3 (x 3~5, y 3~5) 가운데
  g.placeBBlock(p(1), 6, 4, 0, 'wall', 900); // 범위 안 내 벽
  g.placeBBlock(p(1), 9, 9, 0, 'third', 901); // 범위 밖
  p(1).ult = C.ULT_MAX;
  g.drainEvents();
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, 0);
  const big = bb(g, 'big');
  assert.equal(big.length, 9);
  assert.deepEqual([...new Set(big.map((b) => b.x))].sort(), [3, 4, 5], '앞 1칸(x=2) 띄움');
  assert.ok(p(2).z >= 1 - 1e-6, `위로 z=${p(2).z.toFixed(2)}`);
  assert.ok(g.drainEvents().some((e) => e.type === 'bigBombWarn' && e.cells.length === 9 && e.ms === C.BUILDER_BIG_FUSE_MS));
  p(2).damage = 0;
  run(g, C.BUILDER_BIG_FUSE_MS - 2 * TICK);
  assert.equal(bb(g, 'big').length, 9, '아직');
  run(g, 3 * TICK);
  assert.equal(bb(g, 'big').length, 0, '터짐');
  assert.equal(p(2).damage, C.BUILDER_BIG_DAMAGE);
  assert.equal(p(2).lastHit.kind, 'bigbomb');
  assert.equal(g.gridAt(6, 4, 0), 0, '범위 안 내 벽도 같이');
  assert.equal(g.gridAt(9, 9, 0), CELL.BUILD, '범위 밖은 그대로');
  assert.equal(p(1).ult, C.BUILDER_BLAST_ULT + C.BUILDER_BIG_DAMAGE * C.ULT_PER_DAMAGE, 'R 블록 9칸은 게이지 없음, 같이 터진 벽 1칸만');
  assert.ok(lines.some((l) => l.includes('[필살] P1 대폭발 (1명, 같이 터진 블록 1칸)')), lines.join('\n'));
  // 망치로 일찍
  const { g: g2, p: q } = setupChars(['builder', 'ninja']);
  place(q(1), 1.5, 4.5, 0);
  place(q(2), 9.5, 9.5);
  q(1).ult = C.ULT_MAX;
  g2.handleAction(1, { name: 'ult' });
  place(q(1), 2.4, 4.5, 0);
  basic(g2, 1);
  assert.equal(bb(g2, 'big').length, 0, '망치로 치면 바로 터짐');
  assert.equal(g2.bigBombs.length, 0);
});

test('건축가 블록: 폭탄 등으로 없어진 칸은 기록에서 지움, 층이 지워지면 같이 내려감. 테스트 옵션 BUILDER_BLAST_HOLE: 터진 자리 바닥 1칸이 BUILDER_HOLE_MS 동안 구멍', () => {
  const { g, p } = setupChars(['builder', 'ninja']);
  place(p(2), 9.5, 9.5);
  g.placeBBlock(p(1), 5, 5, 0, 'third', 1);
  g.grid[g.idx(5, 5, 0)] = 0; // 폭탄 등
  run(g, TICK);
  assert.equal(g.bblocks.size, 0);
  g.placeBBlock(p(1), 5, 5, 1, 'third', 2);
  g.dropLayers([0]);
  assert.ok(g.bblocks.has('5,5,0'), '한 층 내려감');
  // 구멍 옵션
  const was = C.BUILDER_BLAST_HOLE;
  C.BUILDER_BLAST_HOLE = true;
  try {
    g.grid[g.idx(6, 6, 0)] = CELL.TERRAIN;
    g.placeBBlock(p(1), 6, 6, 1, 'third', 3);
    g.blast(g.bblocks.get('6,6,1'), { x: 1, y: 0 });
    assert.equal(g.gridAt(6, 6, 0), 0, '구멍');
    run(g, C.BUILDER_HOLE_MS + TICK);
    assert.equal(g.gridAt(6, 6, 0), CELL.TERRAIN, '메워짐');
  } finally {
    C.BUILDER_BLAST_HOLE = was;
  }
});

test('봇 건축가: 떨어지면 공중 F 로 복귀, 내 블록 너머에 상대가 있으면 블록을 쳐서 터뜨림, 상대가 앞 3×3 쯤이면 대폭발', () => {
  const mk = () => {
    const g = new Game(() => {}, { characters: true });
    g.rng = () => 0.5;
    const b = g.addBot();
    g.setChar(b.id, 'builder');
    g.addPlayer(1);
    g.startRound();
    g.nextSpawnAt = Infinity;
    g.controlItemNextAt = Infinity;
    g.powerItemNextAt = Infinity;
    return { g, b, t: g.players.get(1), brain: g.bots.get(b.id) };
  };
  // 복귀
  {
    const { g, b, t, brain } = mk();
    place(t, 5.5, 5.5);
    place(b, -0.6, 4.5, 0, -0.5);
    Object.assign(b, { grounded: false, vz: -4 });
    brain.update(g, b);
    assert.equal(b.vz, C.BUILDER_PAD_BOOST, '공중 F');
  }
  // 블록 치기
  {
    const { g, b, t, brain } = mk();
    place(b, 2.5, 4.5, 0);
    place(t, 4.6, 4.5);
    g.placeBBlock(b, 3, 4, 0, 'wall', 77);
    assert.equal(brain.useSkills(g, b, t, [t], []), true);
    assert.ok(b.atk, '평타 준비');
    run(g, b.atk.at - g.time + TICK);
    assert.equal(g.gridAt(3, 4, 0), 0, '블록 터짐');
    assert.ok(t.damage > 0);
  }
  // 대폭발
  {
    const { g, b, t, brain } = mk();
    place(b, 1.5, 4.5, 0);
    place(t, 4.5, 4.5);
    b.ult = C.ULT_MAX;
    assert.equal(brain.useSkills(g, b, t, [t], []), true);
    assert.equal(g.bigBombs.length, 1);
  }
});

test('건축가 발판도 망치로 치면 터짐 (2026-10-25 재혁): 밟고 있던 발판을 쳐서 떨어짐, 패시브 게이지도 참', () => {
  const { g, lines, p } = setupChars(['builder', 'ninja']);
  place(p(2), 9.5, 9.5);
  place(p(1), 4.5, 4.5, 0, 2.5);
  Object.assign(p(1), { grounded: false, vz: -3 });
  g.handleAction(1, { name: 'skill' }); // 발판 (4,4,1)
  run(g, 1500); // 부스트 뒤 발판 위에 내려섬
  assert.ok(p(1).grounded && Math.abs(p(1).z - 2) < 1e-6, `발판 위 z=${p(1).z}`);
  p(1).ult = 0;
  p(1).chainN = 0;
  basic(g, 1);
  assert.equal(g.gridAt(4, 4, 1), 0, '발판 터짐');
  assert.equal(bb(g, 'pad').length, 0);
  assert.equal(p(1).ult, C.BUILDER_BLAST_ULT, '패시브 게이지');
  assert.ok(lines.some((l) => l.startsWith('  [폭발] P1 발판 1칸')), lines.join('\n'));
  run(g, 600);
  assert.ok(p(1).z < 2 - 0.5, `떨어짐 z=${p(1).z.toFixed(2)}`);
});

// ---------- 닌자 (2026-10-25, docs/characters.md 3.2) ----------

test('닌자 평타: 지상 4타(올려 차기는 마무리 아님, 띄움) → 점프 → 공중 2타(내려 차기 마무리)가 한 콤보, 매 틱 누르면 이어짐', () => {
  const { chain, air } = C.BASIC_ATTACKS.ninja;
  for (const dmg0 of [0, 150]) {
    const { g, lines, p } = setupChars(['ninja', 'builder']);
    place(p(1), 3, 4.5, 0);
    place(p(2), 4.2, 4.5);
    p(2).damage = dmg0;
    const ev = [];
    for (let t = 0; t < 4000 && !lines.some((l) => l.includes(' 마무리')); t += TICK) {
      const last = ev.filter((e) => e.type === 'hit' && e.by === 1).at(-1);
      p(1).input = { fwd: 0, strafe: 0, jump: !!(last && last.n === 4 && !last.air) };
      p(1).yaw = Math.atan2(p(2).y - p(1).y, p(2).x - p(1).x);
      g.handleAction(1, { name: 'push' });
      g.tick(TICK);
      ev.push(...g.drainEvents());
    }
    const atk = ev.filter((e) => e.type === 'attack' && e.who === 1).map((e) => `${e.air ? '공중' : '지상'}${e.n}`);
    assert.deepEqual(atk, ['지상1', '지상2', '지상3', '지상4', '공중1', '공중2'], `${dmg0}%`);
    assert.ok(lines.includes('  [콤보] P1 → P2 6타 마무리'), lines.join('\n'));
    assert.equal(p(2).damage - dmg0, chain.reduce((a, d) => a + d.dmg, 0) + air.reduce((a, d) => a + d.dmg, 0));
    assert.ok(lines.some((l) => l.endsWith('공중 2타 내려 차기')), '로그 이름');
  }
});

test('닌자 갈아타기: 타 번호는 상대와 상관없이 이어짐 (A 1타 → B 2타), 때린 쪽 streak 이 상대가 바뀌어도 이어짐', () => {
  const { g, p } = setupChars(['ninja', 'builder', 'tank']);
  place(p(1), 3, 4.5, 0);
  place(p(2), 4.2, 4.5);
  place(p(3), 3, 5.7, Math.PI / 2);
  basic(g, 1);
  run(g, C.BASIC_ATTACKS.ninja.chain[0].rec);
  p(1).yaw = Math.PI / 2; // 다른 상대
  g.drainEvents();
  basic(g, 1);
  const ev = g.drainEvents();
  assert.equal(ev.find((e) => e.type === 'attack').n, 2, 'B 에게 2타');
  const h = ev.find((e) => e.type === 'hit' && e.target === 3);
  assert.ok(h && h.ok && h.streak === 2, `streak ${h && h.streak}`);
  assert.ok(ev.some((e) => e.type === 'streak' && e.who === 1 && e.n === 2 && e.target === 3));
  assert.equal(p(2).comboHits + p(3).comboHits, 2, '맞는 쪽 콤보는 따로');
});

test('닌자 F: 피해 8, 평타가 맞을 때마다 F 쿨 -0.5초, 공중에서도 됨, 블록에 막히면 벽 차기 (위로 + 작은 충격파, 넉백만)', () => {
  const { g, lines, p } = setupChars(['ninja', 'tank', 'tank']);
  place(p(1), 1.5, 4.5, 0);
  place(p(2), 3, 4.6);
  place(p(3), 9.5, 9.5);
  g.handleAction(1, { name: 'skill' });
  assert.ok(Math.abs(p(1).x - (3 + C.NINJA_BLINK_BEHIND)) < 0.11, `상대 바로 뒤 x=${p(1).x}`);
  assert.equal(p(2).damage, C.NINJA_SLASH_DAMAGE);
  assert.equal(C.NINJA_SLASH_DAMAGE, 8);
  // 평타 적중마다 쿨 감소
  run(g, 1000);
  const ready = p(1).skillReadyAt;
  place(p(1), 2, 4.5, 0);
  place(p(2), 3, 4.5);
  p(1).chainN = 0;
  basic(g, 1);
  assert.equal(p(1).skillReadyAt, ready - C.NINJA_HIT_CD_CUT_MS, 'F 쿨 -0.5초');
  // 공중 + 벽 차기
  run(g, C.SKILL_CD_MS.ninja);
  for (let y = 0; y < C.GRID_D; y++) g.grid[g.idx(5, y, 1)] = CELL.BUILD;
  g.gridChanged();
  place(p(2), 4.2, 3.5);
  place(p(1), 2.5, 4.5, 0, 1.2);
  Object.assign(p(1), { grounded: false, vz: -1 });
  p(2).damage = 0;
  g.drainEvents();
  g.handleAction(1, { name: 'skill' });
  assert.ok(p(1).x <= 5 - C.PLAYER_HALF + 1e-9 && p(1).x > 4.4, `블록 앞 x=${p(1).x}`);
  assert.equal(p(1).vz, C.NINJA_WALLKICK_UP, '위로 튀어 오름');
  const ev = g.drainEvents();
  assert.ok(ev.some((e) => e.type === 'wallKick' && e.who === 1));
  assert.ok(lines.some((l) => l.includes('[스킬] P1 벽 차기')), lines.join('\n'));
  // 막힌 데가 없으면 벽 차기 없음
  run(g, C.SKILL_CD_MS.ninja);
  for (let y = 0; y < C.GRID_D; y++) g.grid[g.idx(5, y, 1)] = 0;
  g.gridChanged();
  place(p(1), 1.5, 8.5, 0);
  g.drainEvents();
  g.handleAction(1, { name: 'skill' });
  assert.ok(!g.drainEvents().some((e) => e.type === 'wallKick'));
});

test('닌자 R 강화: 6초 동안 지상 1~3타·공중 평타가 표창 2연발 (즉시 판정, 사거리 3, 경직 짧게), 4타 올려 차기는 그대로. 끝나면 원래대로', () => {
  const { g, p } = setupChars(['ninja', 'builder']);
  const S = C.NINJA_STAR;
  place(p(1), 2, 4.5, 0);
  place(p(2), 4.5, 4.5); // 근접 사거리 밖, 표창 사거리 안
  p(1).ult = C.ULT_MAX;
  g.drainEvents();
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, 0);
  assert.ok(g.drainEvents().some((e) => e.type === 'empower' && e.ms === C.NINJA_EMPOWER_MS));
  g.handleAction(1, { name: 'push' });
  run(g, S.windup + S.gap + 2 * TICK);
  const ev = g.drainEvents();
  assert.ok(ev.some((e) => e.type === 'attack' && e.star && e.n === 1));
  assert.equal(ev.filter((e) => e.type === 'star').length, 2, '2연발');
  assert.equal(p(2).damage, 2 * S.dmg);
  assert.ok(S.stun < C.BASIC_ATTACKS.ninja.chain[0].stun, '경직은 근접보다 짧게');
  assert.ok(2 * S.dmg > C.BASIC_ATTACKS.ninja.chain[0].dmg, '딜은 조금 더');
  // 4타는 올려 차기 그대로
  p(1).chainN = 3;
  p(1).chainUntil = Infinity;
  p(1).pushReadyAt = 0;
  g.drainEvents();
  g.handleAction(1, { name: 'push' });
  assert.equal(g.drainEvents().find((e) => e.type === 'attack').name, '올려 차기');
  // 끝나면 원래대로
  run(g, C.NINJA_EMPOWER_MS);
  p(1).chainN = 0;
  p(1).pushReadyAt = 0;
  g.drainEvents();
  g.handleAction(1, { name: 'push' });
  assert.equal(g.drainEvents().find((e) => e.type === 'attack').name, '찌르기');
});

test('닌자 패시브: 이속 보통, 받는 넉백 × NINJA_KB_TAKEN, 공중에서 떨어지는 블록에 닿으면 공중 점프 회복 (한 블록에 한 번)', () => {
  const { g, p } = setupChars(['ninja', 'builder']);
  place(p(1), 1.5, 1.5, 0);
  place(p(2), 1.5, 8.5, 0);
  p(1).input = { fwd: 1, strafe: 0, jump: false };
  p(2).input = { fwd: 1, strafe: 0, jump: false };
  run(g, 500);
  assert.ok(Math.abs(p(1).x - p(2).x) < 1e-6, '이속 같음');
  p(1).input = p(2).input = { fwd: 0, strafe: 0, jump: false };
  run(g, 500);
  g.applyKnockback(p(1), 1, 0, 5, 0, C.STUN_MS, 0, null, true);
  g.applyKnockback(p(2), 1, 0, 5, 0, C.STUN_MS, 0, null, true);
  assert.ok(Math.abs(p(1).kbx / p(2).kbx - C.NINJA_KB_TAKEN) < 1e-9);
  run(g, 1500);
  // 떨어지는 블록 옆면에 닿음
  const piece = { id: 0, shape: 'O', rot: 0, cells: [[0, 0]], px: 5, py: 5, pz: 3, landZ: 0, fits: false };
  g.addPiece(piece, { phase: 'falling', controller: null, stepMs: 100000, nextStepAt: g.time + 100000, controlEndsAt: 0 });
  place(p(1), 4.68, 5.5, 0, 3.2); // 몸 상자 오른쪽 4.98, 블록 옆면 5 (닿기 직전)
  Object.assign(p(1), { grounded: false, vz: 0, airJumps: 0 });
  g.drainEvents();
  g.tick(TICK);
  assert.equal(p(1).airJumps, C.AIR_JUMPS, '공중 점프 회복');
  assert.ok(g.drainEvents().some((e) => e.type === 'ninjaTouch' && e.who === 1));
  p(1).airJumps = 0;
  g.tick(TICK);
  assert.equal(p(1).airJumps, 0, '같은 블록은 한 번');
});

test('봇 닌자: 필드 밖으로 떨어지면 안쪽으로 공중 F (바닥 옆면에 막히면 벽 차기로 튀어 오름), R 은 표창 사거리 안 상대에게', () => {
  const g = new Game(() => {}, { characters: true });
  g.rng = () => 0.5;
  const b = g.addBot();
  g.setChar(b.id, 'ninja');
  g.addPlayer(1);
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  const t = g.players.get(1);
  const brain = g.bots.get(b.id);
  place(t, 5.5, 5.5);
  place(b, -0.5, 4.5, 0, -0.6);
  Object.assign(b, { grounded: false, vz: -4 });
  g.drainEvents();
  brain.update(g, b);
  assert.ok(b.skillReadyAt > g.time, '공중 F 씀');
  assert.ok(g.drainEvents().some((e) => e.type === 'wallKick'), '바닥 옆면에 막혀 벽 차기');
  assert.equal(b.vz, C.NINJA_WALLKICK_UP);
  // R
  place(b, 3, 5.5, 0);
  b.ult = C.ULT_MAX;
  assert.equal(brain.useSkills(g, b, t, [t], []), true);
  assert.ok(b.empowerUntil > g.time);
});

// ---------- 탱크 (2026-10-25, docs/characters.md 3.3) ----------

test('탱크 평타: 평평평(방패 올려치기는 마무리 아님, 띄움) → 점프 → 공중 방패 내려치기(마무리)가 한 콤보', () => {
  const { chain, air } = C.BASIC_ATTACKS.tank;
  const { g, lines, p } = setupChars(['tank', 'builder']);
  place(p(1), 3, 4.5, 0);
  place(p(2), 4.2, 4.5);
  const ev = [];
  for (let t = 0; t < 4000 && !lines.some((l) => l.includes(' 마무리')); t += TICK) {
    const last = ev.filter((e) => e.type === 'hit' && e.by === 1).at(-1);
    p(1).input = { fwd: 0, strafe: 0, jump: !!(last && last.n === 3 && !last.air) };
    p(1).yaw = Math.atan2(p(2).y - p(1).y, p(2).x - p(1).x);
    g.handleAction(1, { name: 'push' });
    g.tick(TICK);
    ev.push(...g.drainEvents());
  }
  const atk = ev.filter((e) => e.type === 'attack' && e.who === 1).map((e) => `${e.air ? '공중' : '지상'}${e.n}`);
  assert.deepEqual(atk, ['지상1', '지상2', '지상3', '공중1']);
  assert.ok(lines.includes('  [콤보] P1 → P2 4타 마무리'), lines.join('\n'));
  assert.equal(p(2).damage, chain.reduce((a, d) => a + d.dmg, 0) + air[0].dmg);
});

test('탱크 아머: F 돌진 중 맞으면 넉백·경직 없이 피해 % 만, 돌진은 안 멈춤, 카운터 없음. 마무리 타·필살기면 깨지고 보통처럼 맞음', () => {
  const { g, lines, p } = setupChars(['tank', 'ninja', 'builder']);
  place(p(1), 1.5, 4.5, 0);
  place(p(2), 1.5, 3.5);
  place(p(3), 9.5, 9.5);
  g.handleAction(1, { name: 'skill' });
  g.drainEvents();
  const x0 = p(1).x;
  assert.equal(g.applyKnockback(p(1), 0, 1, 5, 3, 500, 7, { by: 2, kind: 'push' }), true);
  assert.equal(p(1).damage, 7, '피해는 받음');
  assert.ok(p(1).stunUntil <= g.time && p(1).kby === 0, '넉백·경직 없음');
  assert.ok(g.time < p(1).chargeUntil, '돌진 계속');
  const ev = g.drainEvents();
  assert.ok(ev.some((e) => e.type === 'armor' && e.who === 1 && e.by === 2));
  assert.ok(!ev.some((e) => e.type === 'counter'));
  assert.ok(lines.includes('  [아머] P1 ← P2 버팀 (P1 7%)'), lines.join('\n'));
  run(g, C.TANK_CHARGE_MS);
  assert.ok(p(1).x - x0 > 2, `끝까지 돌진 ${(p(1).x - x0).toFixed(2)}`);
  // 마무리 타면 깨짐
  run(g, C.SKILL_CD_MS.tank);
  place(p(1), 1.5, 4.5, 0);
  g.handleAction(1, { name: 'skill' });
  g.drainEvents();
  g.applyKnockback(p(1), 0, 1, 5, 3, 500, 7, { by: 2, kind: 'push' }, true, { finish: true });
  const ev2 = g.drainEvents();
  assert.ok(ev2.some((e) => e.type === 'armorBreak' && e.who === 1));
  assert.ok(ev2.some((e) => e.type === 'interrupt' && e.who === 1 && e.kind === 'skill'));
  assert.ok(p(1).stunUntil > g.time && p(1).kby > 0, '보통처럼 맞음');
  assert.ok(!ev2.some((e) => e.type === 'counter'), '깨질 때도 카운터 없음');
});

test('탱크 R: 떠오르는 동안 아머 (필살기에는 깨짐). 쾅 → 가운데 충격파 + 바깥 고리 바닥이 1층 솟아 위 사람을 띄우고 TANK_RING_MS 뒤 가라앉음 (압사 없음)', () => {
  const { g, lines, p } = setupChars(['tank', 'ninja', 'builder']);
  place(p(1), 5, 5);
  place(p(2), 5 + C.TANK_SLAM_RANGE + 0.6, 5); // 바깥 고리 위
  place(p(3), 9.5, 0.5);
  p(1).ult = C.ULT_MAX;
  g.handleAction(1, { name: 'ult' });
  g.drainEvents();
  g.applyKnockback(p(1), 1, 0, 5, 3, 500, 4, { by: 3, kind: 'push' });
  assert.ok(g.drainEvents().some((e) => e.type === 'armor'), '떠오르는 동안 아머');
  assert.ok(p(1).slamAt > 0, '내려찍기 계속');
  run(g, C.TANK_SLAM_WINDUP_MS + TICK);
  const rise = g.drainEvents().find((e) => e.type === 'quakeRise');
  assert.ok(rise && rise.cells.length > 0 && rise.ms === C.TANK_RING_MS);
  const [cx, cy, cz] = rise.cells.find(([x, y]) => x === Math.floor(p(2).x - 0.01) || Math.hypot(x + 0.5 - 5, y + 0.5 - 5) > C.TANK_SLAM_RANGE);
  assert.equal(g.gridAt(cx, cy, cz), CELL.BUILD, '솟음');
  assert.ok(rise.cells.every(([x, y]) => Math.hypot(x + 0.5 - 5, y + 0.5 - 5) > C.TANK_SLAM_RANGE), '바깥 고리만');
  assert.ok(p(2).z >= 1 - 1e-6 || p(2).vz > 0, `띄움 z=${p(2).z.toFixed(2)}`);
  assert.ok(p(2).alive, '압사 없음');
  assert.ok(lines.some((l) => l.includes('솟는 땅 1명')), lines.join('\n'));
  run(g, C.TANK_RING_MS + TICK);
  assert.ok(rise.cells.every(([x, y, z]) => g.gridAt(x, y, z) === 0), '가라앉음');
  assert.ok(g.drainEvents().some((e) => e.type === 'quakeFall'));
});

test('탱크 패시브: 덜 밀림 ×0.92 하나 — 받은 피해 게이지는 다른 캐릭터와 같음 (2026-10-25 재혁: 배율 삭제)', () => {
  const { g, p } = setupChars(['tank', 'builder']);
  g.applyKnockback(p(1), 1, 0, 1, 0, 300, 10, { by: 2, kind: 'push' });
  assert.equal(p(1).ult, 10 * C.ULT_PER_DAMAGE);
  assert.equal(C.TANK_ULT_TAKEN_MULT, undefined);
  assert.equal(p(2).ult, 10 * C.ULT_PER_DAMAGE);
  assert.equal(C.TANK_KB_TAKEN, 0.92);
});

// ---------- 연타 중엔 시간 마무리 없음 (2026-10-25 재혁) ----------

// 매 타를 누를 수 있게 된 뒤 delay ms 늦게 누름 (사람 손). 띄우는 마지막 지상 타 뒤엔 점프
function lateCombo(char, delay) {
  const { g, lines, p } = setupChars([char, 'builder']);
  place(p(1), 3, 4.5, 0);
  place(p(2), 4.2, 4.5);
  const launchN = C.BASIC_ATTACKS[char].chain.length;
  const ev = [];
  let first = null;
  for (let t = 0; t < 5000 && !lines.some((l) => l.includes(' 마무리')); t += TICK) {
    const last = ev.filter((e) => e.type === 'hit' && e.by === 1).at(-1);
    p(1).input = { fwd: 0, strafe: 0, jump: false };
    if (last && last.n === launchN && !last.air && p(1).grounded) g.handleAction(1, { name: 'jump' }); // 짧게 누른 점프
    p(1).yaw = Math.atan2(p(2).y - p(1).y, p(2).x - p(1).x);
    if (!p(1).atk && g.time >= p(1).pushReadyAt + delay) g.handleAction(1, { name: 'push' });
    g.tick(TICK);
    for (const e of g.drainEvents()) {
      ev.push(e);
      if (e.type === 'hit' && e.by === 1 && first === null) first = g.time;
    }
  }
  return { lines, ev, ms: g.time - first };
}

test('연타 중엔 시간 마무리 없음: 매 타 60ms 늦게 눌러 COMBO_MS 를 넘겨도 닌자 6타·탱크 4타가 연타 마무리까지 이어짐 (점프는 짧게 눌러도 기억)', () => {
  for (const [char, n] of [['ninja', 6], ['tank', 4]]) {
    const { lines, ms } = lateCombo(char, 60);
    assert.ok(lines.includes(`  [콤보] P1 → P2 ${n}타 마무리`), `${char}:\n${lines.join('\n')}`);
    assert.ok(ms > C.COMBO_MS, `${char} 콤보 ${ms}ms > COMBO_MS`);
  }
});

test('연타 중엔 시간 마무리 없음 — 무한 콤보는 안 됨: 평타를 계속 누르고 F 로 캔슬해도 한 콤보 길이에 끝이 있고, 스킬 타는 COMBO_MS 뒤 시간 마무리', () => {
  for (const char of C.CHARACTERS) {
    const { g, lines, p } = setupChars([char, 'builder']);
    place(p(1), 3, 4.5, 0);
    place(p(2), 4.2, 4.5);
    const launchN = C.BASIC_ATTACKS[char].chain.length;
    let lastHit = null;
    for (let t = 0; t < 8000; t += TICK) {
      Object.assign(p(1), { x: 3, y: 4.5 }); // 순간 베기로 필드 밖으로 나가지 않게 제자리
      Object.assign(p(2), { x: p(1).x + 1.1, y: p(1).y }); // 상대가 계속 붙어 있다고 침 (최악)
      p(2).z = Math.max(p(2).z, 0);
      p(1).yaw = 0;
      p(1).input = { fwd: 0, strafe: 0, jump: !!(lastHit && lastHit.n === launchN && !lastHit.air) };
      g.handleAction(1, { name: 'push' });
      g.handleAction(1, { name: 'skill' });
      p(1).skillReadyAt = Math.min(p(1).skillReadyAt, g.time + 1000); // 쿨도 짧다고 침
      g.tick(TICK);
      for (const e of g.drainEvents()) if (e.type === 'hit' && e.by === 1 && e.n) lastHit = e;
    }
    const lens = lines.filter((l) => l.includes('[콤보] P1 → P2')).map((l) => Number(l.match(/(\d+)타/)[1]));
    // 광전사: F 광폭 도약이 매번 4칸 뛰어 떨어져서 첫 콤보 뒤로는 한 타씩만 맞음 (콤보로 안 셈) → 첫 콤보만 끝이 있으면 됨
    assert.ok(lens.length > (char === 'berserker' ? 0 : 1), `${char}: 콤보가 끝나고 다시 시작`);
    const set = C.BASIC_ATTACKS[char];
    const bound = set.chain.length + set.air.length + 4; // 연타 전부 + 캔슬로 끼운 스킬 몇 번
    assert.ok(Math.max(...lens) <= bound, `${char}: 최대 ${Math.max(...lens)}타 (상한 ${bound}) ${lens.join(',')}`);
  }
  // 스킬 타는 COMBO_MS 뒤 시간 마무리
  const { g, p } = setupChars(['ninja', 'builder']);
  place(p(2), 5, 5);
  g.applyKnockback(p(2), 1, 0, 1, 0, 2000, 1, { by: 1, kind: 'push' });
  run(g, C.COMBO_MS + TICK);
  g.applyKnockback(p(2), 1, 0, 1, 0, 600, 1, { by: 1, kind: 'slash' });
  assert.equal(p(2).comboHits, 0, '스킬은 시간 마무리');
  // 연타 중인 평타는 아님
  const q = setupChars(['ninja', 'builder']);
  place(q.p(2), 5, 5);
  q.g.applyKnockback(q.p(2), 1, 0, 1, 0, 2000, 1, { by: 1, kind: 'push' });
  run(q.g, C.COMBO_MS + TICK);
  q.g.applyKnockback(q.p(2), 1, 0, 1, 0, 600, 1, { by: 1, kind: 'push' }, false, { fixed: true, chained: true });
  assert.equal(q.p(2).comboHits, 2, '연타 중 평타는 이어짐');
});

test('점프 선입력: 땅에서 누른 점프(action)는 JUMP_BUFFER_MS 동안 기억 — 멈칫 중에 짧게 눌러도 풀리면 뜀', () => {
  const { g, p } = setupChars(['ninja', 'builder']);
  place(p(1), 3, 4.5, 0);
  place(p(2), 8.5, 8.5);
  p(1).freezeUntil = g.time + 100; // 멈칫 중
  p(1).input = { fwd: 0, strafe: 0, jump: false };
  g.handleAction(1, { name: 'jump' });
  run(g, 150);
  assert.ok(p(1).z > 0.1 || p(1).vz > 0, `뜀 z=${p(1).z.toFixed(2)}`);
  // 오래된 선입력은 버림
  run(g, 1500);
  p(1).freezeUntil = g.time + C.JUMP_BUFFER_MS + 100;
  g.handleAction(1, { name: 'jump' });
  run(g, C.JUMP_BUFFER_MS + 200);
  assert.ok(p(1).z < 0.05, '버퍼 지나면 안 뜀');
});

// ---------- 갈고리 (2026-10-25, docs/characters.md 3.4) ----------

test('갈고리 평타: 휘두르기 → 주먹 → 장전이면 탕 (사거리 2, 넉백 큼, 빈 총이 됨) / 빈 총이면 갈고리 내려치기 (약함). 패시브 사거리 없음', () => {
  const { g, lines, p } = setupChars(['hook', 'builder']);
  assert.equal(p(1).loaded, true, '판 시작에 장전');
  place(p(1), 3, 4.5, 0);
  place(p(2), 4.2, 4.5);
  const ev = [];
  for (let t = 0; t < 3000 && !lines.some((l) => l.includes(' 마무리')); t += TICK) {
    g.handleAction(1, { name: 'push' });
    g.tick(TICK);
    ev.push(...g.drainEvents());
  }
  assert.deepEqual(ev.filter((e) => e.type === 'attack' && e.who === 1).map((e) => e.name), ['갈고리 휘두르기', '주먹', '탕']);
  assert.ok(ev.some((e) => e.type === 'bang' && e.who === 1));
  assert.equal(p(1).loaded, false, '쏘면 빈 총');
  assert.equal(g.snapshot().players.find((x) => x.id === 1).loaded, false);
  // 빈 총: 내려치기
  run(g, 2000);
  place(p(1), 3, 4.5, 0);
  place(p(2), 4.2, 4.5);
  p(1).chainN = 2;
  p(1).chainUntil = Infinity;
  p(1).pushReadyAt = 0;
  g.drainEvents();
  g.handleAction(1, { name: 'push' });
  assert.equal(g.drainEvents().find((e) => e.type === 'attack').name, '갈고리 내려치기');
  assert.ok(C.BASIC_ATTACKS.hook.chain[2].loaded.dmg > C.BASIC_ATTACKS.hook.chain[2].dmg, '탕이 더 셈');
  assert.equal(C.HOOK_PUSH_RANGE_MULT, undefined, '패시브 없음');
  // 탕 사거리 2: 1.8 밖도 맞음
  const q = setupChars(['hook', 'builder']);
  place(q.p(1), 3, 4.5, 0);
  place(q.p(2), 4.95, 4.5);
  Object.assign(q.p(1), { chainN: 2, chainUntil: Infinity });
  basic(q.g, 1);
  assert.equal(q.p(2).damage, C.BASIC_ATTACKS.hook.chain[2].loaded.dmg);
});

test('갈고리 공중 평타: 갈고리 스핀 — 수평 한 바퀴로 주변 전부 (뒤도)', () => {
  const { g, p } = setupChars(['hook', 'builder', 'tank']);
  place(p(1), 4.5, 4.5, 0, 0.5);
  Object.assign(p(1), { grounded: false, vz: 2 });
  place(p(2), 5.5, 4.5);
  place(p(3), 3.5, 4.5); // 뒤
  g.handleAction(1, { name: 'push' });
  run(g, C.BASIC_ATTACKS.hook.air[0].windup + TICK / 2);
  assert.ok(p(2).damage > 0 && p(3).damage > 0, `앞 ${p(2).damage} 뒤 ${p(3).damage}`);
});

test('갈고리 F: 상대가 먼저 닿으면 끌어옴 + 장전, 블록이 먼저 닿으면 내가 끌려감 (공중 가능), 빗나가도 쿨타임. 끌려간 뒤 떨어지면 갈고리 킬', () => {
  const { g, lines, p } = setupChars(['hook', 'ninja', 'ninja']);
  place(p(1), 1.5, 4.5, 0);
  place(p(2), 4.5, 4.5);
  place(p(3), 9.5, 9.5);
  p(1).loaded = false;
  g.handleAction(1, { name: 'skill' });
  assert.ok(Math.abs(p(2).x - (p(1).x + C.HOOK_PULL_TO)) < 0.05, `끌려옴 x=${p(2).x}`);
  assert.equal(p(2).damage, C.HOOK_DAMAGE);
  assert.equal(p(1).loaded, true, '끌어오면 장전');
  assert.ok(lines.some((l) => l.startsWith('  [스킬] P1 갈고리 → P2') && l.endsWith('장전')));
  assert.equal(p(2).lastHit.kind, 'hook');
  // 끌려온 뒤 떨어지면 갈고리 킬
  Object.assign(p(2), { x: -3, z: C.FALL_DEATH_Z - 1 });
  g.tick(TICK);
  assert.ok(lines.some((l) => /\[사망\] P2 낙사 .*킬 P1 갈고리/.test(l)));
  // 블록이 먼저 닿음: 내가 끌려감 (공중에서도)
  run(g, C.SKILL_CD_MS.hook);
  g.grid[g.idx(5, 2, 1)] = CELL.TERRAIN;
  g.gridChanged();
  place(p(3), 7.5, 2.5); // 블록 뒤 상대
  place(p(1), 1.5, 2.5, 0, 0.3);
  Object.assign(p(1), { grounded: false, vz: -1 });
  g.drainEvents();
  g.handleAction(1, { name: 'skill' });
  assert.ok(g.drainEvents().some((e) => e.type === 'hook' && e.block && e.target === null));
  assert.equal(p(3).damage, 0, '블록 뒤 상대는 안 끌려옴');
  run(g, 400);
  assert.ok(p(1).x > 4, `블록 쪽으로 끌려감 x=${p(1).x.toFixed(2)}`);
  // 빗나감도 쿨타임
  run(g, C.SKILL_CD_MS.hook);
  place(p(1), 1.5, 7.5, Math.PI);
  g.handleAction(1, { name: 'skill' });
  assert.ok(lines.includes('  [스킬] P1 갈고리 빗나감'));
  assert.ok(p(1).skillReadyAt > g.time);
});

test('갈고리 R 블록 내려찍기: 보는 방향 첫 블록을 뽑아 → 앞 직선을 내려찍고 (넉백 + 띄움) → 끝 칸에 박힘 (사람은 밀쳐냄, 압사 없음). 블록 없으면 안 쓰임, 건축가 블록은 속성 그대로, 필드 밖이면 사라짐', () => {
  const { g, lines, p } = setupChars(['hook', 'ninja', 'builder']);
  place(p(1), 4.5, 4.5, 0); // +x
  place(p(2), 6.5, 4.5); // 직선 위
  place(p(3), 9.5, 0.5, Math.PI); // 끝 칸 (x=9) 에 서 있음
  p(1).ult = C.ULT_MAX;
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, C.ULT_MAX, '블록 없으면 안 쓰임');
  g.placeBBlock(p(3), 7, 4, 1, 'wall', 55); // 앞에 건축가 블록 (가슴 높이)
  g.drainEvents();
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, 0);
  assert.equal(g.gridAt(7, 4, 1), 0, '뽑힘');
  assert.ok(g.drainEvents().some((e) => e.type === 'blockGrab' && e.builder));
  run(g, C.HOOK_GRAB_MS + TICK);
  assert.equal(p(2).damage, C.HOOK_SLAM_DAMAGE);
  assert.ok(p(2).kbx > 0 && (p(2).vz > 0 || p(2).z > 0.1), '넉백 + 띄움');
  assert.equal(p(2).lastHit.kind, 'blockslam');
  const x = Math.floor(4.5 + C.HOOK_SLAM_LEN);
  assert.equal(g.gridAt(x, 4, 0), CELL.BUILD, `끝 칸 (${x},4,0) 박힘`);
  const b = g.bblocks.get(`${x},4,0`);
  assert.ok(b && b.owner === 3 && b.kind === 'wall', '건축가 블록 그대로');
  assert.ok(lines.some((l) => l.includes(`[필살] P1 블록 내려찍기 (1명) → (${x},4,0) 박힘`)), lines.join('\n'));
  // 박히는 칸 사람은 밀쳐냄
  const q = setupChars(['hook', 'ninja']);
  place(q.p(1), 1.5, 2.5, 0);
  q.g.grid[q.g.idx(3, 2, 1)] = CELL.TERRAIN;
  q.g.gridChanged();
  place(q.p(2), 1.5 + C.HOOK_SLAM_LEN, 2.5); // 끝 칸
  q.p(1).ult = C.ULT_MAX;
  q.g.handleAction(1, { name: 'ult' });
  run(q.g, C.HOOK_GRAB_MS + TICK);
  assert.ok(q.p(2).alive, '압사 없음');
  assert.equal(q.g.gridAt(Math.floor(1.5 + C.HOOK_SLAM_LEN), 2, 0), CELL.TERRAIN);
  // 필드 밖이면 사라짐
  const r = setupChars(['hook', 'ninja']);
  place(r.p(2), 9.5, 9.5);
  place(r.p(1), 7.5, 2.5, 0);
  r.g.grid[r.g.idx(8, 2, 1)] = CELL.TERRAIN;
  r.g.gridChanged();
  r.p(1).ult = C.ULT_MAX;
  r.g.handleAction(1, { name: 'ult' });
  run(r.g, C.HOOK_GRAB_MS + TICK);
  let left = 0;
  for (let i = 0; i < r.g.grid.length; i++) if (r.g.grid[i] === CELL.TERRAIN) left++;
  assert.equal(left, 0, '필드 밖으로 사라짐');
});

test('봇 갈고리: 상대 쪽으로 블록이 닿으면 R 블록 내려찍기, 없으면 안 씀. 떨어질 때 안쪽에 블록이 있으면 F 로 걸어 복귀', () => {
  const g = new Game(() => {}, { characters: true });
  g.rng = () => 0.5;
  const b = g.addBot();
  g.setChar(b.id, 'hook');
  g.addPlayer(1);
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  const t = g.players.get(1);
  const brain = g.bots.get(b.id);
  place(b, 2.5, 4.5, 0);
  place(t, 6.5, 4.5);
  b.ult = C.ULT_MAX;
  brain.useSkills(g, b, t, [t], []);
  assert.equal(b.ult, C.ULT_MAX, '블록 없으면 안 씀');
  g.grid[g.idx(4, 4, 1)] = CELL.TERRAIN;
  g.gridChanged();
  assert.equal(brain.useSkills(g, b, t, [t], []), true);
  assert.ok(b.grab, '블록 뽑음');
  // 복귀
  const g2 = new Game(() => {}, { characters: true });
  g2.rng = () => 0.5;
  const b2 = g2.addBot();
  g2.setChar(b2.id, 'hook');
  g2.addPlayer(1);
  g2.startRound();
  place(g2.players.get(1), 8.5, 8.5);
  g2.grid[g2.idx(1, 4, 0)] = CELL.TERRAIN;
  g2.gridChanged();
  place(b2, -0.6, 4.5, 0, -0.5);
  Object.assign(b2, { grounded: false, vz: -4 });
  g2.bots.get(b2.id).update(g2, b2);
  assert.ok(b2.zipUntil > g2.time, '블록에 걸어 끌려감');
});

test('갈고리 블록 찾기 (2026-10-25 버그): 땅에 서서 평지의 1칸 높이 블록을 보면 (살짝 아래로) R 이 그 블록을 뽑고 F 도 걸림. 바닥을 보면 안 잡힘', () => {
  const { g, p } = setupChars(['hook', 'ninja']);
  place(p(2), 9.5, 9.5);
  g.grid[g.idx(5, 4, 0)] = CELL.THROWN; // 떨어져 쌓인 1칸 높이 블록
  g.gridChanged();
  place(p(1), 2.5, 4.5, 0);
  p(1).pitch = -Math.atan2(C.EYE_HEIGHT - 0.5, 3); // 블록 가운데를 봄
  assert.deepEqual(g.hookRayBlock(p(1)), { ...g.hookRayBlock(p(1)), x: 5, y: 4, z: 0 });
  p(1).ult = C.ULT_MAX;
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, 0, 'R 쓰임');
  assert.equal(g.gridAt(5, 4, 0), 0, '뽑힘');
  run(g, C.HOOK_GRAB_MS + TICK);
  // F 도 걸림 (수평으로 봐도 발 층 보조로 잡힘)
  g.grid[g.idx(5, 2, 0)] = CELL.THROWN;
  g.gridChanged();
  place(p(1), 2.5, 2.5, 0);
  p(1).pitch = 0;
  g.drainEvents();
  g.handleAction(1, { name: 'skill' });
  assert.ok(g.drainEvents().some((e) => e.type === 'hook' && e.block && e.block[2] === 0));
  // 바닥만 보면 없음
  const q = setupChars(['hook', 'ninja']);
  place(q.p(2), 9.5, 9.5);
  place(q.p(1), 2.5, 4.5, 0);
  q.p(1).pitch = -1.2;
  assert.equal(q.g.hookRayBlock(q.p(1)), null);
});

// ---------- 사람 테스트 수정 (2026-10-26) ----------

test('건축가 F 벽: 예고 동안 건축가가 벽 칸으로 걸어 들어가면 그 칸은 안 솟고 건축가는 안 뜸', () => {
  const { g, p } = setupChars(['builder', 'ninja']);
  place(p(2), 9.5, 9.5);
  place(p(1), 4.5, 4.5, 0);
  g.handleAction(1, { name: 'skill' }); // x=5, y 3~5
  place(p(1), 5.5, 4.5, 0); // 가운데 벽 칸 위로
  run(g, C.BUILDER_WALL_WARN_MS + TICK);
  assert.equal(g.gridAt(5, 4, 0), 0, '내가 선 칸은 안 솟음');
  assert.equal(g.gridAt(5, 3, 0), CELL.BUILD);
  assert.equal(g.gridAt(5, 5, 0), CELL.BUILD);
  assert.ok(p(1).z < 0.05, `안 뜸 z=${p(1).z}`);
});

test('탱크 R: 예고 0.7초 (TANK_SLAM_WINDUP_MS), 바깥 고리 up 5. blink 이벤트 from 에 z', () => {
  assert.equal(C.TANK_SLAM_WINDUP_MS, 700);
  assert.equal(C.TANK_RING_UP, 5);
  const { g, p } = setupChars(['ninja', 'builder']);
  place(p(2), 9.5, 9.5);
  place(p(1), 1.5, 4.5, 0, 0.5);
  Object.assign(p(1), { grounded: false });
  g.drainEvents();
  g.handleAction(1, { name: 'skill' });
  const e = g.drainEvents().find((x) => x.type === 'blink');
  assert.equal(e.from.z, 0.5);
});

test('갈고리 R 한 번 누르면 나감 (2026-10-26 재혁: 두 번 눌러야 했음): 정면·살짝 아래·살짝 위, 조준이 블록 옆으로 조금 빗나가도 뽑힘. 평타 후딜 중 R 은 후딜 끝나고 나감. 블록이 없으면 ultFail', () => {
  for (const pitch of [0, -0.3, 0.25]) {
    for (const off of [0, 0.7]) {
      const { g, p } = setupChars(['hook', 'ninja']);
      place(p(2), 9.5, 9.5);
      g.grid[g.idx(5, 4, 0)] = CELL.THROWN;
      g.gridChanged();
      place(p(1), 2.5, 4.5, Math.atan2(off, 3));
      p(1).pitch = pitch;
      p(1).ult = C.ULT_MAX;
      g.handleAction(1, { name: 'ult' });
      assert.equal(p(1).ult, 0, `pitch ${pitch} off ${off}: 한 번에`);
      assert.equal(g.gridAt(5, 4, 0), 0);
    }
  }
  // 평타 후딜 중 R
  const { g, p } = setupChars(['hook', 'ninja']);
  place(p(2), 9.5, 9.5);
  g.grid[g.idx(5, 4, 0)] = CELL.THROWN;
  g.gridChanged();
  place(p(1), 2.5, 4.5, 0);
  p(1).ult = C.ULT_MAX;
  basic(g, 1); // 빗나감 → 후딜
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, C.ULT_MAX, '후딜 중엔 기억');
  run(g, p(1).pushReadyAt - g.time + TICK);
  assert.equal(p(1).ult, 0, '후딜 끝나고 나감');
  // 블록 없음 → ultFail
  const q = setupChars(['hook', 'ninja']);
  place(q.p(2), 9.5, 9.5);
  place(q.p(1), 2.5, 4.5, 0);
  q.p(1).ult = C.ULT_MAX;
  q.g.drainEvents();
  q.g.handleAction(1, { name: 'ult' });
  assert.ok(q.g.drainEvents().some((e) => e.type === 'ultFail' && e.who === 1 && e.reason === 'noBlock'));
  assert.equal(q.p(1).ult, C.ULT_MAX);
  // 기억한 R 이 맞아서 버려지면 castDrop
  q.g.handleAction(1, { name: 'push' });
  q.g.handleAction(1, { name: 'ult' });
  q.g.drainEvents();
  q.g.applyKnockback(q.p(1), 1, 0, 1, 0, 300, 1, { by: 2, kind: 'push' });
  assert.ok(q.g.drainEvents().some((e) => e.type === 'castDrop' && e.who === 1 && e.kind === 'ult'));
});

// ---------- 사냥꾼 (2026-10-26, docs/characters.md 3.5) ----------

test('사냥꾼 표식: 지상 평타 마무리(찔러 넣기)가 맞을 때만 +1 (최대 3, 사냥꾼마다 따로), 공중 평타로는 안 쌓임, 마지막으로 쌓인 뒤 5초면 사라짐. snapshot marks', () => {
  const { g, lines, p } = setupChars(['hunter', 'tank', 'hunter']);
  place(p(3), 9.5, 9.5);
  const chain = () => {
    place(p(1), 3, 4.5, 0);
    place(p(2), 4.2, 4.5);
    Object.assign(p(1), { chainN: 2, chainUntil: Infinity, pushReadyAt: 0 });
    basic(g, 1);
    run(g, 1000); // 경직·무적 풀림
  };
  // 1·2타는 표식 없음
  place(p(1), 3, 4.5, 0);
  place(p(2), 4.2, 4.5);
  basic(g, 1);
  assert.equal(g.markOf(p(1), p(2)), 0);
  run(g, 1000);
  for (const n of [1, 2, 3, 3]) {
    chain();
    assert.equal(g.markOf(p(1), p(2)), n, `표식 ${n}`);
  }
  assert.ok(lines.includes('  [표식] P1 → P2 3개'));
  assert.equal(g.markOf(p(3), p(2)), 0, '다른 사냥꾼 것은 따로');
  const snap = g.snapshot().players.find((x) => x.id === 2);
  assert.equal(snap.marks[0].by, 1);
  assert.equal(snap.marks[0].n, 3);
  // 공중 평타는 안 쌓임
  const q = setupChars(['hunter', 'tank']);
  place(q.p(1), 3, 4.5, 0, 1);
  Object.assign(q.p(1), { grounded: false, vz: -1 });
  place(q.p(2), 4, 4.5);
  basic(q.g, 1);
  assert.ok(q.p(2).damage > 0);
  assert.equal(q.g.markOf(q.p(1), q.p(2)), 0, '공중은 표식 없음');
  // 5초 뒤 사라짐
  run(g, C.HUNTER_MARK_MS - 1000 - 2 * TICK);
  assert.equal(g.markOf(p(1), p(2)), 3);
  g.drainEvents();
  run(g, 3 * TICK);
  assert.equal(g.markOf(p(1), p(2)), 0, '사라짐');
  assert.ok(g.drainEvents().some((e) => e.type === 'markGone' && e.by === 1 && e.target === 2));
});

test('사냥꾼 F 추적 도약: 사거리 6 안 표식 있는 가장 가까운 상대에게 예고 0.2초 뒤 도약해 덮침 (평타로 이어짐), 표식이 없으면 보는 방향 3칸', () => {
  const { g, p } = setupChars(['hunter', 'tank', 'builder']);
  place(p(1), 2, 4.5, Math.PI); // 뒤를 보고 있어도
  place(p(2), 7, 4.5);
  place(p(3), 9.5, 9.5);
  p(2).marks.set(1, { n: 1, at: g.time });
  g.drainEvents();
  g.handleAction(1, { name: 'skill' });
  assert.ok(g.drainEvents().some((e) => e.type === 'leapWarn' && e.target === 2 && e.ms === C.HUNTER_LEAP_WINDUP_MS));
  run(g, C.HUNTER_LEAP_WINDUP_MS + C.HUNTER_LEAP_MS + 2 * TICK);
  assert.ok(Math.hypot(p(2).x - p(1).x, p(2).y - p(1).y) <= C.HUNTER_POUNCE_RANGE, `덮침 거리 ${(p(2).x - p(1).x).toFixed(2)}`);
  assert.equal(p(2).damage, C.HUNTER_POUNCE_DAMAGE);
  assert.ok(p(2).stunUntil > g.time, '경직 → 평타 연결');
  assert.equal(p(2).lastHit.kind, 'pounce');
  // 표식 없음: 보는 방향 3칸
  run(g, C.SKILL_CD_MS.hunter);
  p(2).marks.clear();
  place(p(1), 2, 1.5, 0);
  g.handleAction(1, { name: 'skill' });
  run(g, C.HUNTER_LEAP_WINDUP_MS + C.HUNTER_LEAP_MS + 2 * TICK);
  assert.ok(Math.abs(p(1).x - (2 + C.HUNTER_LEAP_DIST)) < 0.3, `x=${p(1).x.toFixed(2)}`);
});

test('사냥꾼 찔러 넣기 (재혁 "가"): 마무리 아님 — 평평평이 맞아도 콤보·경직이 이어지고 무적이 안 붙어 F 덮침이 들어감 (표식 +1), 덮침 뒤 평타도 이어짐', () => {
  const { g, p } = setupChars(['hunter', 'tank']);
  place(p(1), 3, 5, 0);
  place(p(2), 4.1, 5);
  for (let i = 0; i < 3; i++) {
    basic(g, 1);
    if (i < 2) run(g, p(1).pushReadyAt - g.time + TICK);
  }
  assert.equal(g.markOf(p(1), p(2)), 1, '표식 +1');
  assert.equal(p(2).comboHits, 3, '콤보 이어짐');
  assert.ok(p(2).iframeUntil <= g.time, '무적 없음');
  assert.ok(p(2).stunUntil - g.time >= C.HUNTER_LEAP_WINDUP_MS + C.HUNTER_LEAP_MS, '경직이 F 덮침까지 감');
  assert.ok(Math.abs(p(2).kbx) < 3, `밀림 작음 ${p(2).kbx}`);
  g.handleAction(1, { name: 'skill' }); // 맞힌 후딜 캔슬
  run(g, C.HUNTER_LEAP_WINDUP_MS + C.HUNTER_LEAP_MS + 2 * TICK);
  assert.equal(p(2).lastHit.kind, 'pounce', '덮침 들어감');
  assert.equal(p(2).comboHits, 4, '덮침도 콤보 (시간 마무리 아님)');
  assert.ok(p(2).iframeUntil <= g.time);
  const before = p(2).damage;
  basic(g, 1);
  assert.ok(p(2).damage > before, '덮침 뒤 평타');
});

test('사냥꾼 F 유도 (재혁 "다"): 도약 중 표식 대상이 움직이면 착지 직전까지 따라감, 처음 자리에서 최대 HUNTER_LEAP_HOMING_MAX 칸', () => {
  const leapTo = (moveY) => {
    const { g, p } = setupChars(['hunter', 'tank']);
    place(p(1), 2, 5, 0);
    place(p(2), 6, 5);
    p(2).marks.set(1, { n: 1, at: g.time });
    g.handleAction(1, { name: 'skill' });
    run(g, C.HUNTER_LEAP_WINDUP_MS + TICK); // 도약 시작
    for (let t = 0; t < C.HUNTER_LEAP_MS + 2 * TICK; t += TICK) {
      Object.assign(p(2), { x: 6, y: 5 + Math.min(moveY, (moveY * t) / C.HUNTER_LEAP_MS) }); // 도약 중 옆으로 걸어감
      g.tick(TICK);
    }
    return { g, p };
  };
  const a = leapTo(1.2);
  assert.ok(a.p(1).y > 5.4, `따라감 y ${a.p(1).y.toFixed(2)}`);
  assert.ok(Math.hypot(a.p(2).x - a.p(1).x, a.p(2).y - a.p(1).y) <= C.HUNTER_POUNCE_RANGE, '덮칠 거리 안');
  assert.equal(a.p(2).lastHit.kind, 'pounce', '덮침');
  const b = leapTo(5); // 너무 멀리 가면 최대 보정까지만
  assert.ok(b.p(1).y <= 5 + C.HUNTER_LEAP_HOMING_MAX + 0.1, `최대 보정 y ${b.p(1).y.toFixed(2)}`);
  assert.ok(b.p(1).y >= 5 + C.HUNTER_LEAP_HOMING_MAX - 0.4, `보정은 함 y ${b.p(1).y.toFixed(2)}`);
});

test('사냥꾼 재혁 ㄱ·ㄴ·표식 10초: 공중 내려 베기가 마무리 (콤보 끝·무적), 처형 사격 넉백 = 기본 + 표식당 2.5, 표식은 10초 유지', () => {
  assert.equal(C.HUNTER_MARK_MS, 10000);
  assert.equal(C.HUNTER_SHOT_KB_PER_MARK, 2.5);
  // 평평평 → 점프 → 공중 내려 베기 = 마무리
  const { g, p } = setupChars(['hunter', 'tank']);
  place(p(1), 3, 5, 0);
  place(p(2), 4.1, 5);
  for (let i = 0; i < 3; i++) {
    basic(g, 1);
    run(g, p(1).pushReadyAt - g.time + TICK);
  }
  assert.ok(p(2).comboHits >= 3);
  Object.assign(p(1), { z: p(2).z + 0.5, grounded: false, vz: 0, x: p(2).x - 1, y: p(2).y, yaw: 0 });
  basic(g, 1);
  assert.equal(p(2).lastHit.kind, 'push');
  assert.equal(p(2).comboHits, 0, '콤보 끝');
  assert.ok(p(2).iframeUntil > g.time, '마무리 무적');
  // 처형 사격 넉백: 표식 수에 비례
  const shot = (n) => {
    const q = setupChars(['hunter', 'tank']);
    place(q.p(1), 2, 5, 0);
    place(q.p(2), 5, 5);
    q.p(2).marks.set(1, { n, at: q.g.time });
    q.p(1).ult = q.g.ultMax(q.p(1));
    q.g.handleAction(1, { name: 'ult' });
    run(q.g, C.HUNTER_SHOT_WINDUP_MS + TICK);
    return Math.hypot(q.p(2).kbx, q.p(2).kby);
  };
  const r = shot(3) / shot(1);
  const want = (C.HUNTER_SHOT_KB_BASE + 3 * C.HUNTER_SHOT_KB_PER_MARK) / (C.HUNTER_SHOT_KB_BASE + C.HUNTER_SHOT_KB_PER_MARK);
  assert.ok(Math.abs(r - want) < 0.05 * want, `넉백 비 ${r.toFixed(3)} (기대 ${want.toFixed(3)}, 표식 피해 % 차이 포함)`);
});

test('사냥꾼 R 처형 사격: 게이지 2배, 각 90°·사거리 8 안 표식 대상 전부를 0.5초 조준 뒤 맞힘 (표식 1개당 피해), 표식 소모, 블록이 가리면 막힘, 표식 3개를 맞히면 게이지를 돌려받음, 대상이 없으면 안 쓰임', () => {
  const { g, lines, p } = setupChars(['hunter', 'tank', 'builder', 'ninja']);
  assert.equal(g.ultMax(p(1)), C.ULT_MAX * 2);
  assert.equal(g.snapshot().players.find((x) => x.id === 1).ultMax, C.ULT_MAX * 2);
  place(p(1), 2, 6.5, 0);
  place(p(2), 6, 6.5); // 표식 2
  place(p(3), 6, 9.5); // 표식 3
  place(p(4), 6, 3.5); // 블록 뒤, 표식 1
  p(2).marks.set(1, { n: 2, at: g.time });
  p(3).marks.set(1, { n: 3, at: g.time });
  p(4).marks.set(1, { n: 1, at: g.time });
  for (let z = 0; z < 3; z++) for (const y of [4, 5]) g.grid[g.idx(4, y, z)] = CELL.TERRAIN; // p4 앞을 가림
  g.gridChanged();
  p(1).ult = C.ULT_MAX; // 1배로는 못 씀
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, C.ULT_MAX, '게이지 2배');
  p(1).ult = g.ultMax(p(1));
  g.drainEvents();
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, 0);
  const aim = g.drainEvents().find((e) => e.type === 'aim');
  assert.deepEqual(aim.targets.sort(), [2, 3], '블록 뒤는 조준에서 빠짐');
  assert.equal(p(2).damage, 0, '바로는 안 맞음');
  run(g, C.HUNTER_SHOT_WINDUP_MS + TICK);
  assert.equal(p(2).damage, 2 * C.HUNTER_SHOT_DAMAGE_PER_MARK);
  assert.equal(p(3).damage, 3 * C.HUNTER_SHOT_DAMAGE_PER_MARK);
  assert.equal(p(4).damage, 0, '블록이 막음');
  assert.equal(g.markOf(p(1), p(2)), 0, '표식 소모');
  assert.equal(g.markOf(p(1), p(4)), 1, '막힌 대상 표식은 그대로');
  assert.equal(p(1).ult, g.ultMax(p(1)), '표식 3개 → 게이지 돌려받음');
  assert.equal(p(3).lastHit.kind, 'execute');
  assert.ok(lines.some((l) => l.includes('[필살] P1 처형 사격') && l.includes('막힘') && l.includes('게이지 회수')), lines.join('\n'));
  // 대상 없음 → 안 쓰임 + ultFail
  run(g, 2000);
  for (const i of [2, 3, 4]) p(i).marks.clear();
  g.drainEvents();
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, g.ultMax(p(1)));
  assert.ok(g.drainEvents().some((e) => e.type === 'ultFail' && e.reason === 'noTarget'));
});

test('봇 사냥꾼: 표식 대상이 보이면 R, 표식 있는 상대가 떨어져 있으면 F', () => {
  const g = new Game(() => {}, { characters: true });
  g.rng = () => 0.5;
  const b = g.addBot();
  g.setChar(b.id, 'hunter');
  g.addPlayer(1);
  g.startRound();
  g.nextSpawnAt = Infinity;
  const t = g.players.get(1);
  const brain = g.bots.get(b.id);
  place(b, 2, 4.5, Math.PI);
  place(t, 6, 4.5);
  t.marks.set(b.id, { n: 2, at: g.time });
  b.ult = g.ultMax(b);
  assert.equal(brain.useSkills(g, b, t, [t], []), true);
  assert.ok(b.huntAim, 'R 조준');
  // F (새 판: 위에서 쏜 상대는 날아감)
  const g2 = new Game(() => {}, { characters: true });
  g2.rng = () => 0.5;
  const b2 = g2.addBot();
  g2.setChar(b2.id, 'hunter');
  g2.addPlayer(1);
  g2.startRound();
  const t2 = g2.players.get(1);
  place(b2, 2, 4.5, 0);
  place(t2, 6, 4.5);
  t2.marks.set(b2.id, { n: 1, at: g2.time });
  assert.equal(g2.bots.get(b2.id).useSkills(g2, b2, t2, [t2], []), true);
  assert.ok(b2.leap, 'F 도약');
});

test('사냥꾼 R: 콘 안에 표식 있는 사람·없는 사람이 섞이면 표식 있는 사람만 맞음. 대상 없으면 게이지 유지 + ultFail. snapshot ultTarget', () => {
  const { g, p } = setupChars(['hunter', 'tank', 'builder']);
  place(p(1), 2, 4.5, 0);
  place(p(2), 5, 4.5); // 표식 없음
  place(p(3), 5, 5.8); // 표식 1
  const snap = () => g.snapshot().players.find((x) => x.id === 1).ultTarget;
  assert.equal(snap(), false, '표식 대상 없음');
  p(1).ult = g.ultMax(p(1));
  g.drainEvents();
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, g.ultMax(p(1)), '게이지 유지');
  assert.ok(g.drainEvents().some((e) => e.type === 'ultFail' && e.reason === 'noTarget'));
  p(3).marks.set(1, { n: 1, at: g.time });
  assert.equal(snap(), true, 'R 대상 있음');
  g.handleAction(1, { name: 'ult' });
  run(g, C.HUNTER_SHOT_WINDUP_MS + TICK);
  assert.equal(p(2).damage, 0, '표식 없는 사람은 안 맞음');
  assert.equal(p(3).damage, C.HUNTER_SHOT_DAMAGE_PER_MARK);
  assert.equal(g.snapshot().players.find((x) => x.id === 2).ultTarget, undefined, '사냥꾼만');
});

// ---------- 대포수 (2026-10-26, docs/characters.md 3.6) ----------

test('대포수 장전: 최대 3발, 판 시작에 가득, 쏘면 줄고 2.5초마다 한 발. 탄이 없으면 평타는 후려치기. snapshot cannon', () => {
  const { g, p } = setupChars(['cannon', 'tank']);
  place(p(2), 9.5, 9.5);
  place(p(1), 2.5, 4.5, Math.PI / 2);
  assert.equal(p(1).cannonAmmo, C.CANNON_AMMO_MAX);
  for (let k = 0; k < 3; k++) {
    g.handleAction(1, { name: 'push' });
    run(g, 600);
  }
  assert.equal(p(1).cannonAmmo, 0);
  g.drainEvents();
  g.handleAction(1, { name: 'push' });
  assert.equal(g.drainEvents().find((e) => e.type === 'attack').name, '후려치기', '탄 없으면 후려치기');
  const s = g.snapshot().players.find((x) => x.id === 1).cannon;
  assert.equal(s.ammo, 0);
  assert.ok(s.reloadLeft > 0 && s.reloadLeft <= C.CANNON_RELOAD_MS);
  run(g, C.CANNON_RELOAD_MS * 3 + 100);
  assert.equal(p(1).cannonAmmo, 3, '다시 가득');
  run(g, C.CANNON_RELOAD_MS);
  assert.equal(p(1).cannonAmmo, 3, '최대 3');
});

test('대포수 포탄: 보이는 투사체로 날아가 (즉시 판정 아님) 맞으면 넉백 큼, 쏘면 반동 (공중에서 더 크게)', () => {
  const { g, p } = setupChars(['cannon', 'tank']);
  place(p(1), 2.5, 4.5, 0);
  place(p(2), 7.5, 4.5);
  p(1).pitch = -Math.atan2(C.EYE_HEIGHT - 0.2 - 0.8, 5); // 상대 가슴
  g.drainEvents();
  g.handleAction(1, { name: 'push' });
  run(g, C.BASIC_ATTACKS.cannon.chain[0].ammo.windup + TICK);
  assert.ok(g.drainEvents().some((e) => e.type === 'shellFire' && e.who === 1));
  assert.equal(g.snapshot().shells.length, 1, '날아가는 중');
  assert.equal(p(2).damage, 0, '바로는 안 맞음');
  assert.ok(p(1).kbx < 0, '반동으로 뒤로');
  run(g, 600);
  assert.equal(p(2).damage, C.CANNON_SHELL_DAMAGE);
  assert.equal(p(2).lastHit.kind, 'shell');
  assert.ok(p(2).kbx > 0);
  // 공중 반동이 더 큼
  const ground = (() => {
    const q = setupChars(['cannon', 'tank']);
    place(q.p(2), 9.5, 9.5);
    place(q.p(1), 4.5, 4.5, 0);
    q.g.fireShell(q.p(1), false);
    return -q.p(1).kbx;
  })();
  const air = (() => {
    const q = setupChars(['cannon', 'tank']);
    place(q.p(2), 9.5, 9.5);
    place(q.p(1), 4.5, 4.5, 0, 2);
    q.p(1).grounded = false;
    q.g.fireShell(q.p(1), false);
    return -q.p(1).kbx;
  })();
  assert.equal(ground, C.CANNON_RECOIL);
  assert.equal(air, C.CANNON_RECOIL_AIR);
});

test('대포수 포탄: 쌓인 블록에 맞으면 1칸 부숨 (멈춤), 시작 지형·바닥은 안 부숨', () => {
  const { g, p } = setupChars(['cannon', 'tank']);
  place(p(2), 9.5, 9.5);
  place(p(1), 2.5, 4.5, 0);
  g.grid[g.idx(5, 4, 1)] = CELL.THROWN;
  g.grid[g.idx(6, 4, 1)] = CELL.THROWN;
  g.gridChanged();
  g.drainEvents();
  g.fireShell(p(1), false);
  run(g, 800);
  assert.equal(g.gridAt(5, 4, 1), 0, '1칸 부숨');
  assert.equal(g.gridAt(6, 4, 1), CELL.THROWN, '멈춤 (뒤 칸은 그대로)');
  assert.ok(g.drainEvents().some((e) => e.type === 'blockBreak' && e.cells.length === 1));
  // 시작 지형
  g.grid[g.idx(5, 4, 1)] = CELL.TERRAIN;
  g.gridChanged();
  g.fireShell(p(1), false);
  run(g, 800);
  assert.equal(g.gridAt(5, 4, 1), CELL.TERRAIN, '시작 지형은 안 부숨');
  // 바닥 (아래로 쏨)
  p(1).pitch = -1.2;
  g.fireShell(p(1), false);
  run(g, 800);
  assert.equal(g.shells.length, 0, '바닥에 닿아 사라짐');
});

test('대포수 F 발밑 포격: 위로 크게 + 발밑 범위 넉백 (공중에서도), 탄 안 씀', () => {
  const { g, p } = setupChars(['cannon', 'tank']);
  place(p(1), 4.5, 4.5, 0);
  place(p(2), 5.5, 4.5);
  g.handleAction(1, { name: 'skill' });
  assert.equal(p(1).vz, C.CANNON_JUMP_UP);
  assert.equal(p(2).damage, C.CANNON_FBLAST_DAMAGE);
  assert.ok(p(2).kbx > 0);
  assert.equal(p(1).cannonAmmo, C.CANNON_AMMO_MAX, '탄 안 씀');
  assert.ok(p(1).skillReadyAt > g.time);
});

test('대포수 R 대형 포탄: 블록을 관통하며 지나간 쌓인 블록 전부 부숨 (시작 지형은 통과), 사람은 밀치고 계속, 끝에서 폭발, 반동 큼', () => {
  const { g, lines, p } = setupChars(['cannon', 'tank', 'builder']);
  place(p(1), 1.5, 4.5, 0);
  place(p(2), 4.5, 4.5); // 길 위
  place(p(3), 9.5, 4.5); // 끝 근처
  for (const x of [3, 6, 7]) g.grid[g.idx(x, 4, 1)] = CELL.THROWN;
  g.grid[g.idx(5, 4, 1)] = CELL.TERRAIN;
  g.gridChanged();
  p(1).ult = C.ULT_MAX;
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).kbx, -C.CANNON_R_RECOIL, '반동 큼');
  run(g, (C.CANNON_R_RANGE / C.CANNON_R_SPEED) * 1000 + 200);
  for (const x of [3, 6, 7]) assert.equal(g.gridAt(x, 4, 1), 0, `(${x},4,1) 부숨`);
  assert.equal(g.gridAt(5, 4, 1), CELL.TERRAIN, '시작 지형은 그대로');
  assert.ok(p(2).damage >= C.CANNON_R_DAMAGE, '지나가며 밀침');
  assert.ok(p(3).damage >= C.CANNON_R_DAMAGE, '계속 날아가 뒤 사람도');
  assert.ok(lines.some((l) => l.includes('[필살] P1 대형 포탄 폭발')), lines.join('\n'));
});

test('봇 대포수: 탄이 있으면 거리를 두고 조준해 포탄을 쏨, 앞에 상대가 있으면 R', () => {
  const g = new Game(() => {}, { characters: true });
  g.rng = () => 0.5;
  const b = g.addBot();
  g.setChar(b.id, 'cannon');
  g.addPlayer(1);
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  const t = g.players.get(1);
  place(b, 2.5, 4.5, 0);
  place(t, 7.5, 4.5);
  g.drainEvents();
  for (let k = 0; k < 30; k++) g.tick(TICK);
  assert.ok(g.drainEvents().some((e) => e.type === 'shellFire' && e.who === b.id), '포탄 쏨');
  assert.ok(b.cannonAmmo < C.CANNON_AMMO_MAX);
  b.ult = C.ULT_MAX;
  Object.assign(b, { atk: null, pushReadyAt: 0 }); // 포탄 후딜이면 R 은 기억했다가 나감 → 후딜 없을 때로
  place(t, b.x + 5, b.y);
  assert.equal(g.bots.get(b.id).useSkills(g, b, t, [t], []), true);
  assert.equal(b.ult, 0, 'R');
  // 조준 오차: 쏠 때마다 좌우·위아래 각각 ±BOT_SHELL_AIM_ERROR_RAD 안 무작위 (사람처럼 빗나감)
  const brain = g.bots.get(b.id);
  brain.rng = () => 1;
  brain.rollShellErr();
  assert.ok(Math.abs(brain.shellErr.yaw - C.BOT_SHELL_AIM_ERROR_RAD) < 1e-9);
  brain.rng = () => 0;
  brain.rollShellErr();
  assert.ok(Math.abs(brain.shellErr.pitch + C.BOT_SHELL_AIM_ERROR_RAD) < 1e-9);
  assert.ok(C.BOT_SHELL_AIM_ERROR_RAD > 0);
});

test('광전사 분노: 주는 넉백 × (1 + 자기 피해 % × 계수), 상한 없음. 고정 넉백 중간 타(가로 베기)는 그대로. 다른 캐릭터는 분노 없음', () => {
  const kb = (char, dmg, opts = {}) => {
    const { g, p } = setupChars([char, 'tank']);
    place(p(2), 5, 5);
    p(1).damage = dmg;
    g.applyKnockback(p(2), 1, 0, 4, 0, 600, 0, { by: 1, kind: 'push' }, true, opts);
    return p(2).kbx;
  };
  const base = kb('berserker', 0);
  for (const d of [100, 200, 300, 500]) assert.ok(Math.abs(kb('berserker', d) / base - (1 + d * C.BERSERKER_RAGE_PER_PERCENT)) < 1e-9, `${d}%`);
  assert.equal(kb('berserker', 300, { fixed: true }), kb('berserker', 0, { fixed: true }), '고정 넉백은 분노 없음');
  assert.equal(kb('hunter', 300), kb('hunter', 0), '다른 캐릭터는 분노 없음');
  // 실제 평타: 1타 가로 베기(고정) 는 같고, 공중 회전 베기(배율) 는 셈
  const swing = (dmg, air) => {
    const { g, p } = setupChars(['berserker', 'tank']);
    place(p(1), 4, 5, 0, air ? 1 : 0);
    if (air) p(1).grounded = false;
    place(p(2), 5.2, 5, 0, air ? 1 : 0);
    p(1).damage = dmg;
    basic(g, 1);
    return p(2).kbx;
  };
  assert.ok(swing(0, false) > 0);
  assert.equal(swing(200, false), swing(0, false), '가로 베기는 분노 없음');
  assert.ok(Math.abs(swing(200, true) / swing(0, true) - 1.6) < 1e-6, '공중 회전 베기는 분노 ×1.6');
});

test('광전사 평타: 가로 베기 (넓은 사거리) → 내려찍기 (마무리), 공중 회전 베기는 사방', () => {
  const { g, p } = setupChars(['berserker', 'tank', 'builder']);
  place(p(1), 4, 5, 0);
  place(p(2), 4 + 2.0, 5); // 보통 사거리(1.8) 밖, 가로 베기 사거리 안
  place(p(3), 1, 1);
  basic(g, 1);
  assert.equal(p(2).damage, 7, '가로 베기');
  run(g, 350);
  basic(g, 1);
  assert.equal(p(2).damage, 17, '내려찍기');
  // 공중 회전 베기: 등 뒤도
  const q = setupChars(['berserker', 'tank']);
  place(q.p(1), 4, 5, 0, 1);
  q.p(1).grounded = false;
  place(q.p(2), 3, 5, 0, 1);
  basic(q.g, 1);
  assert.equal(q.p(2).damage, 8, '등 뒤도 맞음');
  assert.ok(q.p(2).kbx < 0, '바깥(뒤)으로');
});

test('광전사 F 광폭 도약: 앞으로 약 4칸 뛰고 땅에 닿으면 착지 충격파, 도약 중 맞으면 충격파 없음', () => {
  const { g, p, lines } = setupChars(['berserker', 'tank']);
  place(p(1), 2, 5, 0);
  place(p(2), 6.8, 5);
  g.handleAction(1, { name: 'skill' });
  assert.ok(p(1).rush);
  assert.ok(p(1).skillReadyAt >= g.time + C.SKILL_CD_MS.berserker - 1);
  g.drainEvents();
  run(g, 1200);
  assert.ok(Math.abs(p(1).x - (2 + C.BERSERKER_LEAP_DIST)) < 0.4, `x ${p(1).x}`);
  assert.equal(p(1).rush, null);
  assert.equal(p(2).damage, C.BERSERKER_WAVE_DAMAGE, lines.join('\n'));
  assert.ok(p(2).kbx > 0);
  // 도약 중에 맞으면 끊김
  const q = setupChars(['berserker', 'tank']);
  place(q.p(1), 2, 5, 0);
  place(q.p(2), 6.8, 5);
  q.g.handleAction(1, { name: 'skill' });
  run(q.g, 200);
  q.g.applyKnockback(q.p(1), -1, 0, 1, 0, 300, 1, { by: 2, kind: 'push' });
  run(q.g, 1500);
  assert.equal(q.p(2).damage, 0, '충격파 없음');
});

test('광전사 R 분노 소용돌이: 피해 % 최대 40 깎음, 회전 중 작게 바깥으로 계속 밀침, 끝에 크게 날림 (R 시작 때 깎은 뒤 피해 % 만큼, 재혁 가), 맞으면 끊김', () => {
  // 깎기
  const a = setupChars(['berserker', 'tank']);
  a.p(1).damage = 25;
  a.p(1).ult = C.ULT_MAX;
  a.g.handleAction(1, { name: 'ult' });
  assert.equal(a.p(1).damage, 0, '0 아래로는 안 감');
  assert.ok(a.p(1).spin);
  // 회전 + 끝 날림: 상대를 붙여 둠
  const spinKb = (startDmg) => {
    const { g, p, lines } = setupChars(['berserker', 'tank']);
    place(p(1), 4, 5, 0);
    place(p(2), 5, 5);
    p(1).damage = startDmg;
    p(1).ult = C.ULT_MAX;
    g.handleAction(1, { name: 'ult' });
    assert.equal(p(1).damage, startDmg - Math.min(C.BERSERKER_RAGE_CUT, startDmg));
    let ticks = 0;
    let out = true;
    let endKb = 0;
    for (let t = 0; t < C.BERSERKER_SPIN_MS + 200; t += TICK) {
      g.tick(TICK);
      for (const e of g.drainEvents()) {
        if (e.type === 'hit' && e.kind === 'spin' && e.ok) {
          ticks++;
          if (p(2).kbx <= 0) out = false;
        }
        if (e.type === 'hit' && e.kind === 'spinend' && e.ok) endKb = p(2).kbx;
      }
      if (p(1).spin) Object.assign(p(2), { x: 5, y: 5, z: 0 }); // 붙어 있다고 침
    }
    assert.ok(ticks >= 5, `작은 밀침 ${ticks}번`);
    assert.ok(out, '바깥으로만 (빨아들이지 않음)');
    assert.ok(endKb > 0, lines.join('\n'));
    return endKb;
  };
  const k200 = spinKb(200);
  const k40 = spinKb(40);
  const after = (d) => d - Math.min(C.BERSERKER_RAGE_CUT, d);
  assert.ok(Math.abs(k200 / k40 - (1 + after(200) * C.BERSERKER_RAGE_PER_PERCENT) / (1 + after(40) * C.BERSERKER_RAGE_PER_PERCENT)) < 1e-6, '끝 날림 = 깎은 뒤 분노');
  // 회전 중 맞으면 끊김
  const b = setupChars(['berserker', 'tank']);
  place(b.p(1), 4, 5, 0);
  place(b.p(2), 8, 5);
  b.p(1).ult = C.ULT_MAX;
  b.g.handleAction(1, { name: 'ult' });
  run(b.g, 300);
  b.g.drainEvents();
  b.g.applyKnockback(b.p(1), -1, 0, 1, 0, 300, 1, { by: 2, kind: 'push' });
  assert.equal(b.p(1).spin, null);
  assert.ok(b.g.drainEvents().some((e) => e.type === 'interrupt' && e.who === 1 && e.kind === 'ult'));
  assert.equal(b.g.snapshot().players.find((x) => x.id === 1).berserker.spinLeft, 0);
});

test('봇 광전사: 피해 % 높고 붙어 있으면 R, 조금 떨어진 상대에게 F 로 붙음', () => {
  const g = new Game(() => {}, { characters: true });
  g.rng = () => 0.5;
  const b = g.addBot();
  g.setChar(b.id, 'berserker');
  g.addPlayer(1);
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  const t = g.players.get(1);
  const brain = g.bots.get(b.id);
  place(b, 3, 5, 0);
  place(t, 4.2, 5);
  b.ult = C.ULT_MAX;
  b.damage = 20;
  assert.equal(brain.useSkills(g, b, t, [t], []), false, '피해 % 낮으면 R 아낌');
  b.damage = 120;
  assert.equal(brain.useSkills(g, b, t, [t], []), true);
  assert.ok(b.spin, 'R');
  b.spin = null;
  place(t, 6.5, 5);
  assert.equal(brain.useSkills(g, b, t, [t], []), true);
  assert.ok(b.rush, 'F 도약');
});

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
  assert.ok(lines.includes('  캐릭터: P1 닌자 / P2(봇) 갈고리'));
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
  const { g, lines, p } = setupChars(['tank', 'ninja', 'ninja']);
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

test('닌자: 이동 빠름, 순간 베기는 벽 앞까지 + 지나간 길의 상대를 한 번 베고 그 바로 뒤에서 멈춤', () => {
  const { g, lines, p } = setupChars(['ninja', 'tank', 'tank']);
  // 이동 속도
  place(p(1), 1.5, 1.5, 0);
  place(p(2), 1.5, 8.5, 0);
  place(p(3), 8.5, 8.5);
  p(1).input = { fwd: 1, strafe: 0, jump: false };
  p(2).input = { fwd: 1, strafe: 0, jump: false };
  run(g, 500);
  const r = (p(1).x - 1.5) / (p(2).x - 1.5);
  assert.ok(Math.abs(r - C.NINJA_SPEED_MULT) < 0.02, `속도 비 ${r.toFixed(3)}`);
  p(1).input = { fwd: 0, strafe: 0, jump: false };
  p(2).input = { fwd: 0, strafe: 0, jump: false };
  // 순간 베기: 길 위의 상대(p2)는 베이고, 길 밖(p3)은 무사
  place(p(1), 1.5, 4.5, 0);
  place(p(2), 3, 4.6);
  place(p(3), 3, 7.5);
  g.handleAction(1, { name: 'skill' });
  assert.ok(Math.abs(p(1).x - (3 + C.NINJA_STRIKE_BEHIND)) < 0.11, `상대 바로 뒤에서 멈춤 x=${p(1).x}`);
  assert.equal(p(2).damage, C.NINJA_SLASH_DAMAGE);
  assert.equal(p(3).damage, 0);
  assert.ok(lines.some((l) => l.includes('[스킬] P1 순간 베기 2.3칸 (1명)')), lines.join('\n'));
  // 아무도 없으면 NINJA_BLINK_DIST 칸
  run(g, C.SKILL_CD_MS.ninja + C.COMBO_IFRAME_MS);
  place(p(1), 1.5, 1.5, 0);
  g.handleAction(1, { name: 'skill' });
  assert.ok(Math.abs(p(1).x - (1.5 + C.NINJA_BLINK_DIST)) < 0.11, `x=${p(1).x}`);
  // 벽 앞까지
  run(g, C.SKILL_CD_MS.ninja);
  for (let y = 0; y < C.GRID_D; y++) g.grid[g.idx(3, y, 0)] = CELL.BUILD;
  g.gridChanged();
  place(p(1), 1.5, 4.5, 0);
  g.handleAction(1, { name: 'skill' });
  assert.ok(p(1).x <= 3 - C.PLAYER_HALF + 1e-9 && p(1).x > 2.4, `벽 앞 x=${p(1).x}`);
});

test('닌자 콤보: 평타 → 순간 베기 → 평타가 한 콤보로 이어지고, 그림자 일격은 등 뒤 치명타 + 맞히면 순간 베기 초기화', () => {
  const { g, lines, p } = setupChars(['ninja', 'builder']);
  place(p(1), 2, 5, 0);
  place(p(2), 3, 5);
  basic(g, 1);
  assert.equal(p(2).comboHits, 1);
  run(g, C.BASIC_HITSTOP_MS);
  p(1).yaw = Math.atan2(p(2).y - p(1).y, p(2).x - p(1).x);
  g.handleAction(1, { name: 'skill' }); // 상대를 지나가며 벰
  assert.equal(p(2).comboHits, 2, '평타 → 베기');
  run(g, C.HITSTOP_MS + TICK);
  p(1).yaw = Math.atan2(p(2).y - p(1).y, p(2).x - p(1).x);
  p(1).pushReadyAt = 0;
  basic(g, 1);
  assert.equal(p(2).comboHits, 3, '→ 평타');
  assert.ok(lines.some((l) => l.includes('[평타] P1 → P2') && l.endsWith('2타 반대 찌르기')), '스킬을 끼워도 이어 치기 (2타)');
  // 그림자 일격: 등 뒤로 + 치명타 + 순간 베기 초기화
  assert.ok(p(1).skillReadyAt > g.time, '순간 베기 쿨 중');
  p(1).ult = C.ULT_MAX;
  run(g, C.HITSTOP_MS + TICK);
  const before = p(2).damage;
  g.handleAction(1, { name: 'ult' });
  assert.ok(p(2).damage > before, '맞음');
  assert.ok(lines.some((l) => l.includes('넉백 치명타')), '치명타');
  assert.ok(p(1).skillReadyAt <= g.time, '순간 베기 초기화');
  assert.equal(p(1).ult, 0);
  // 6칸 안에 아무도 없으면 안 쓰이고 게이지 그대로
  run(g, 3000);
  place(p(2), 9.5, 9.5);
  place(p(1), 0.5, 0.5);
  p(1).ult = C.ULT_MAX;
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, C.ULT_MAX);
});

test('건축가: 솟는 벽은 예고 뒤 앞 가로 3 × 2층으로 솟고 그 칸의 상대를 위로 띄움, 블록 비 = 조준한 곳에 1×1 블록 5개 + 예고', () => {
  const { g, lines, p } = setupChars(['builder', 'ninja']);
  place(p(1), 4.5, 4.5, 0); // +x 를 봄
  place(p(2), 5.5, 4.5); // 벽 칸 위
  g.drainEvents();
  g.handleAction(1, { name: 'skill' });
  assert.ok(g.drainEvents().some((e) => e.type === 'wallWarn' && e.cells.length === 6), '바닥 예고');
  assert.equal(g.gridAt(5, 4, 0), 0, '바로는 안 솟음');
  run(g, C.BUILDER_WALL_WARN_MS + TICK);
  for (const y of [3, 4, 5]) for (const z of [0, 1]) assert.equal(g.gridAt(5, y, z), CELL.BUILD, `(5,${y},${z})`);
  assert.equal(p(2).damage, C.BUILDER_WALL_DAMAGE);
  assert.ok(p(2).z >= 2 - 1e-6, `벽 위로 올라감 z=${p(2).z.toFixed(2)}`);
  assert.ok(lines.includes('  [스킬] P1 솟는 벽 (6칸, 1명 띄움)'), lines.join('\n'));
  // 블록 비
  run(g, 2000);
  p(1).ult = C.ULT_MAX;
  Object.assign(p(1), { x: 1.5, y: 1.5, yaw: Math.PI / 4, pitch: -0.4 });
  g.handleAction(1, { name: 'ult' });
  const rain = g.pieces.filter((pc) => pc.thrownBy === 1);
  assert.equal(rain.length, C.BUILDER_RAIN_CELLS.length);
  assert.ok(rain.every((pc) => pc.cells.length === 1));
  assert.ok(g.drainEvents().some((e) => e.type === 'rainWarn' && e.cells.length === rain.length));
  assert.equal(p(1).ult, 0);
});

test('갈고리: 밀치기 사거리 +, 갈고리는 보는 방향 상대를 내 앞으로 + 피해 (빗나가도 쿨타임), 평타 → 갈고리 → 평타 콤보, 끌려간 뒤 떨어지면 갈고리 킬', () => {
  const { g, lines, p } = setupChars(['hook', 'ninja', 'ninja']);
  // 사거리: 보통 사거리 밖, 늘어난 사거리 안
  place(p(1), 4, 4.5, 0);
  place(p(2), 4 + C.PUSH_RANGE * 1.1, 4.5);
  place(p(3), 9.5, 9.5);
  basic(g, 1);
  assert.ok(p(2).damage > 0);
  run(g, 1000 + C.COMBO_IFRAME_MS);
  // 평타로 밀고 → 갈고리로 당겨 → 평타
  place(p(1), 1.5, 4.5, 0);
  place(p(2), 2.5, 4.5);
  p(1).pushReadyAt = 0;
  p(1).chainN = 0;
  g.handleAction(1, { name: 'push' });
  run(g, 300);
  const d0 = p(2).damage;
  g.handleAction(1, { name: 'skill' });
  assert.ok(Math.abs(p(2).x - (p(1).x + C.HOOK_PULL_TO)) < 0.05, `끌려옴 x=${p(2).x}`);
  assert.equal(p(2).damage, d0 + C.HOOK_DAMAGE);
  assert.equal(p(2).comboHits, 2, '평타 → 갈고리');
  assert.ok(lines.some((l) => l.startsWith('  [스킬] P1 갈고리 → P2')));
  assert.equal(p(2).lastHit.kind, 'hook');
  run(g, C.HITSTOP_MS + TICK);
  p(1).pushReadyAt = 0;
  basic(g, 1);
  assert.ok(lines.includes('  [콤보] P1 → P2 3타 마무리'), '→ 평타 2타 주먹 = 마무리');
  // 끌려온 뒤 떨어지면 갈고리 킬 (마지막 공격 기록)
  p(2).lastHit = { by: 1, kind: 'hook', name: 'P1' };
  Object.assign(p(2), { x: -3, z: C.FALL_DEATH_Z - 1 });
  g.tick(TICK);
  assert.ok(lines.some((l) => /\[사망\] P2 낙사 .*킬 P1 갈고리/.test(l)));
  // 빗나감도 쿨타임
  run(g, C.SKILL_CD_MS.hook);
  place(p(1), 1.5, 4.5, Math.PI);
  g.handleAction(1, { name: 'skill' });
  assert.ok(lines.includes('  [스킬] P1 갈고리 빗나감'));
  assert.ok(p(1).skillReadyAt > g.time);
});

test('갈고리: 회오리는 주변 모두 끌어모아 피해, 잠깐 뒤 바깥으로 한꺼번에 튕김 (한 콤보)', () => {
  const { g, p } = setupChars(['hook', 'ninja']);
  place(p(1), 5, 5);
  place(p(2), 8, 5);
  p(1).ult = C.ULT_MAX;
  g.handleAction(1, { name: 'ult' });
  assert.ok(Math.abs(p(2).x - (5 + C.HOOK_PULL_TO)) < 0.05, `회오리 x=${p(2).x}`);
  assert.equal(p(2).damage, C.HOOK_ULT_DAMAGE);
  run(g, C.HOOK_WHIRL_FLING_MS + TICK);
  assert.ok(p(2).kbx > 0, '바깥(+x)으로 튕김');
  assert.equal(p(2).comboHits, 2);
});

test('캐릭터: 팀전이면 같은 팀은 갈고리·회오리·내려찍기 대상이 아님', () => {
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

test('건축가 패시브: 설치 블록 아이템을 주우면 BUILDER_BRICK_BONUS 개 더', () => {
  const { g, p } = setupChars(['builder', 'tank']);
  g.givePower(p(1), 'brick');
  g.givePower(p(2), 'brick');
  assert.equal(p(1).bricks, C.BRICK_USES + C.BUILDER_BRICK_BONUS);
  assert.equal(p(2).bricks, C.BRICK_USES);
});

test('닌자 그림자 일격: 무적인 상대는 안 고르고, 근처에 무적인 상대뿐이면 안 쓰여 게이지 그대로 (순간 베기 초기화도 없음)', () => {
  const { g, p } = setupChars(['ninja', 'tank']);
  place(p(1), 3, 5, 0);
  place(p(2), 5, 5);
  p(2).iframeUntil = g.time + 1000;
  p(1).ult = C.ULT_MAX;
  p(1).skillReadyAt = g.time + 5000;
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, C.ULT_MAX, '안 쓰임');
  assert.ok(p(1).skillReadyAt > g.time, '초기화 없음');
  assert.equal(p(2).damage, 0);
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

for (const char of C.CHARACTERS) {
  test(`평타 ${char}: 바로바로 누르면 0% 에서도 150% 에서도 1타부터 마지막 타까지 한 콤보 → 마무리, 피해 합 = 타별 딜 합`, () => {
    const chain = C.BASIC_ATTACKS[char].chain;
    for (const dmg0 of [0, 150]) {
      const { lines, p, events } = fullChain(char, dmg0);
      const n = chain.length;
      assert.ok(lines.includes(`  [콤보] P1 → P2 ${n}타 마무리`), `${dmg0}%:\n${lines.join('\n')}`);
      assert.equal(p(2).damage - dmg0, chain.reduce((a, d) => a + d.dmg, 0));
      const atk = events.filter((e) => e.type === 'attack' && e.who === 1);
      assert.deepEqual(atk.map((e) => e.n), chain.map((_, i) => i + 1), '타 번호');
      assert.deepEqual(atk.map((e) => e.windup), chain.map((d) => d.windup), '준비 시간');
      assert.ok(atk.every((e) => e.char === char && e.air === false));
      assert.equal(atk.at(-1).finish, true, '마지막 타 예고');
      const hits = events.filter((e) => e.type === 'hit' && e.by === 1);
      assert.ok(hits.every((e) => e.ok) && hits.at(-1).finish);
    }
  });
}

test('평타: 경직은 후딜 + 다음 타 준비 + 0.1초 이상 (바로 누르면 확정), 마무리 타만 finish, 풀 콤보 최단 시간 ≤ COMBO_MS', () => {
  for (const char of C.CHARACTERS) {
    const chain = C.BASIC_ATTACKS[char].chain;
    let t = 0;
    chain.forEach((d, i) => {
      assert.equal(!!d.finish, i === chain.length - 1, `${char} ${i + 1}타`);
      if (i === chain.length - 1) return;
      assert.ok(d.stun >= d.rec + chain[i + 1].windup + 100, `${char} ${i + 1}타 경직 ${d.stun}`);
      t += d.rec + chain[i + 1].windup;
    });
    assert.ok(t <= C.COMBO_MS, `${char} 최단 ${t}`);
  }
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

test('평타: 이어 치기 창을 놓치면 1타부터, 빗나가도 1타부터, 맞으면 준비 중인 평타가 끊김', () => {
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
  // 빗나감
  run(g, chain[0].rec);
  p(1).yaw = Math.PI;
  basic(g, 1);
  assert.equal(p(1).chainN, 0, '빗나가면 1타부터');
  // 준비 중에 맞으면 끊김
  run(g, 1000);
  p(1).yaw = 0;
  g.handleAction(1, { name: 'push' });
  assert.ok(p(1).atk);
  g.applyKnockback(p(1), -1, 0, 1, 0, 300, 5, { by: 3, kind: 'push' });
  assert.equal(p(1).atk, null);
});

test('평타: 공중 평타는 캐릭터마다 한 타 (타 번호 0), 떨어지며 위에서 치면 치명타. 빗나가면 이어 치기도 1타부터', () => {
  const { g, lines, p } = setupChars(['builder', 'ninja']);
  place(p(1), 3, 4.5, 0, 1);
  Object.assign(p(1), { grounded: false, vz: -1 });
  place(p(2), 4, 4.5);
  g.drainEvents();
  g.handleAction(1, { name: 'push' });
  const e = g.drainEvents().find((x) => x.type === 'attack');
  assert.equal(e.n, 0);
  assert.equal(e.air, true);
  assert.equal(e.name, C.BASIC_ATTACKS.builder.air.name);
  p(1).vz = -1; // 준비 시간 동안 떨어지는 중으로 둠
  p(1).z = 1;
  run(g, C.BASIC_ATTACKS.builder.air.windup + TICK / 2);
  assert.ok(lines.some((l) => l.includes('넉백 치명타') && l.endsWith(`공중 ${C.BASIC_ATTACKS.builder.air.name}`)), lines.join('\n'));
  assert.equal(p(2).damage, Math.round(C.BASIC_ATTACKS.builder.air.dmg * C.CRIT_DAMAGE_MULT));
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

test('평타: 마무리 타 준비 중에는 이동 속도 × BASIC_FINISH_MOVE_MULT, 망치를 들면 평타 대신 망치', () => {
  const { g, p } = setupChars(['tank', 'ninja']);
  place(p(1), 3, 1.5, 0);
  p(1).atk = { n: 3, def: C.BASIC_ATTACKS.tank.chain[2], at: g.time + 10000 };
  p(1).input = { fwd: 1, strafe: 0, jump: false };
  run(g, 200);
  const slow = p(1).x - 3;
  assert.ok(Math.abs(slow - C.MOVE_SPEED * 0.2 * C.BASIC_FINISH_MOVE_MULT) < 0.1, `${slow}`);
  p(1).atk = null;
  p(1).input = { fwd: 0, strafe: 0, jump: false };
  place(p(1), 3, 4.5, 0);
  place(p(2), 4, 4.5);
  p(1).weaponUses = 1;
  g.handleAction(1, { name: 'push' });
  assert.equal(p(2).damage, C.DAMAGE_GAIN.weapon, '망치는 바로');
  assert.equal(p(1).atk, null);
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
function hitBy3(prep) {
  const { g, lines, p } = setupChars(['tank', 'ninja', 'hook']);
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
  // 필살기 준비 (내려찍기), 스킬 중 (돌진)
  assert.ok(countered(hitBy3((g, p) => {
    p(1).ult = C.ULT_MAX;
    g.handleAction(1, { name: 'ult' });
    p(1).slamAt = g.time + 10000;
  })), '내려찍기 준비');
  assert.ok(countered(hitBy3((g, p) => {
    p(1).yaw = Math.PI / 2;
    g.handleAction(1, { name: 'skill' });
    p(1).chargeUntil = g.time + 10000;
    p(1).chargeDir = { x: 0, y: 0 }; // 제자리 (판정 전에 멀어지지 않게)
  })), '돌진 중');
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
  const hit = () => {
    g.applyKnockback(p(1), -1, 0, 1, 0, 300, 5, { by: 2, kind: 'push' });
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
  // 돌진 중에 맞음 → 쿨타임 돌려받음
  place(p(1), 3, 4.5, Math.PI / 2);
  g.handleAction(1, { name: 'skill' });
  assert.ok(p(1).skillReadyAt > g.time);
  g.drainEvents();
  assert.deepEqual(hit().map((e) => e.kind), ['skill']);
  assert.ok(p(1).skillReadyAt <= g.time, '쿨 돌려받음');
  run(g, 1000); // 경직(카운터면 ×1.5) + 무적이 끝나게
  // 내려찍기 준비 중에 맞음 → 게이지 돌려받음
  place(p(1), 3, 4.5, 0);
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, 0);
  g.drainEvents();
  assert.deepEqual(hit().map((e) => e.kind), ['ult']);
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
  const { lines } = fullChain('tank', 0);
  const i = lines.findIndex((l) => l.includes('[콤보] P1 → P2 3타 마무리'));
  assert.ok(i > 0 && lines[i - 1].includes('[평타] P1 → P2') && lines[i - 1].endsWith('3타 방패 밀기'), lines.join('\n'));
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

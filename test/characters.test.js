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
  g.handleAction(1, { name: 'push' });
  assert.equal(p(1).ult, C.DAMAGE_GAIN.push * C.ULT_PER_DAMAGE, '때린 쪽');
  assert.equal(p(2).ult, C.DAMAGE_GAIN.push * C.ULT_PER_DAMAGE, '맞은 쪽');
  g.handleAction(1, { name: 'ult' });
  assert.ok(p(1).ult > 0, '안 찼으면 안 씀');
  p(1).ult = C.ULT_MAX;
  run(g, C.STUN_MS + 100);
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(1).ult, 0);
});

test('탱크: 피해 % 덜 쌓임, 돌진은 처음 부딪힌 상대를 치고 멈춤 (쿨타임), 빗나가면 약 3칸', () => {
  const { g, lines, p } = setupChars(['tank', 'ninja', 'ninja']);
  // 같은 공격: 탱크는 피해 % 가 덜 쌓이고, 이번 넉백은 같음
  g.applyKnockback(p(1), 1, 0, 5, 0, C.STUN_MS, 20, null);
  g.applyKnockback(p(2), 1, 0, 5, 0, C.STUN_MS, 20, null);
  assert.equal(p(1).damage, Math.round(20 * C.TANK_DAMAGE_TAKEN));
  assert.equal(p(2).damage, 20);
  assert.equal(p(1).kbx, p(2).kbx);
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
  assert.equal(p(2).damage, Math.round(C.NINJA_SLASH_DAMAGE * C.TANK_DAMAGE_TAKEN));
  assert.equal(p(3).damage, 0);
  assert.ok(lines.some((l) => l.includes('[스킬] P1 순간 베기 2.3칸 (1명)')), lines.join('\n'));
  // 아무도 없으면 3칸
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
  g.handleAction(1, { name: 'push' });
  assert.equal(p(2).comboHits, 1);
  run(g, C.HITSTOP_MS + TICK);
  p(1).yaw = Math.atan2(p(2).y - p(1).y, p(2).x - p(1).x);
  g.handleAction(1, { name: 'skill' }); // 상대를 지나가며 벰
  assert.equal(p(2).comboHits, 2, '평타 → 베기');
  run(g, C.HITSTOP_MS + TICK);
  p(1).yaw = Math.atan2(p(2).y - p(1).y, p(2).x - p(1).x);
  p(1).pushReadyAt = 0;
  g.handleAction(1, { name: 'push' });
  assert.equal(p(2).comboHits, 3, '→ 평타');
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
  g.handleAction(1, { name: 'push' });
  assert.ok(p(2).damage > 0);
  run(g, C.STUN_MS + C.COMBO_IFRAME_MS + 100);
  // 평타로 밀고 → 갈고리로 당겨 → 평타
  place(p(1), 1.5, 4.5, 0);
  place(p(2), 2.5, 4.5);
  p(1).pushReadyAt = 0;
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
  g.handleAction(1, { name: 'push' });
  assert.equal(p(2).comboHits, 3, '→ 평타');
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

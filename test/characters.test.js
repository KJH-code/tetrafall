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

test('탱크: 피해 % 덜 쌓임, 버티기 동안 안 밀림 (쿨타임), 지면 강타는 주변 상대를 날림', () => {
  const { g, lines, p } = setupChars(['tank', 'ninja', 'ninja']);
  // 같은 공격: 탱크는 피해 % 가 덜 쌓이고, 이번 넉백은 같음
  g.applyKnockback(p(1), 1, 0, 5, 0, C.STUN_MS, 20, null);
  g.applyKnockback(p(2), 1, 0, 5, 0, C.STUN_MS, 20, null);
  assert.equal(p(1).damage, Math.round(20 * C.TANK_DAMAGE_TAKEN));
  assert.equal(p(2).damage, 20);
  assert.equal(p(1).kbx, p(2).kbx);
  p(1).damage = 0;
  p(2).damage = 0;
  // 버티기
  place(p(1), 4.5, 4.5);
  place(p(2), 3.5, 4.5, 0);
  g.handleAction(1, { name: 'skill' });
  assert.ok(lines.includes('  [스킬] P1 버티기'));
  g.handleAction(2, { name: 'push' });
  assert.equal(p(1).damage, 0, '버티는 동안 안 밀림');
  g.handleAction(1, { name: 'skill' });
  assert.equal(p(1).skillReadyAt, g.time + C.TANK_HOLD_CD_MS, '쿨타임 중엔 다시 안 씀 (시각 그대로)');
  run(g, C.TANK_HOLD_MS + 100);
  place(p(2), 3.5, 4.5, 0);
  g.handleAction(2, { name: 'push' });
  assert.ok(p(1).damage > 0, '버티기 끝나면 밀림');
  // 지면 강타
  run(g, C.STUN_MS + 100);
  place(p(1), 5, 5);
  place(p(2), 6, 5);
  place(p(3), 5, 9.5); // 멀리
  p(1).ult = C.ULT_MAX;
  g.handleAction(1, { name: 'ult' });
  assert.equal(p(2).damage, C.TANK_SLAM_DAMAGE);
  assert.ok(p(2).kbx > 0 && p(2).vz > 0, '바깥으로 날아감');
  assert.equal(p(3).damage, 0, '멀면 안 맞음');
  assert.ok(lines.includes('  [필살] P1 지면 강타 (1명)'));
});

test('닌자: 이동 빠름, 순간이동은 벽 앞까지, 그림자는 유령화 + 다음 밀치기 치명타', () => {
  const { g, lines, p } = setupChars(['ninja', 'tank']);
  // 이동 속도
  place(p(1), 1.5, 1.5, 0);
  place(p(2), 1.5, 8.5, 0);
  p(1).input = { fwd: 1, strafe: 0, jump: false };
  p(2).input = { fwd: 1, strafe: 0, jump: false };
  run(g, 500);
  const r = (p(1).x - 1.5) / (p(2).x - 1.5);
  assert.ok(Math.abs(r - C.NINJA_SPEED_MULT) < 0.02, `속도 비 ${r.toFixed(3)}`);
  p(1).input = { fwd: 0, strafe: 0, jump: false };
  p(2).input = { fwd: 0, strafe: 0, jump: false };
  // 순간이동: 빈 땅이면 3칸
  place(p(1), 1.5, 4.5, 0);
  g.handleAction(1, { name: 'skill' });
  assert.ok(Math.abs(p(1).x - (1.5 + C.NINJA_BLINK_DIST)) < 0.11, `x=${p(1).x}`);
  // 벽 앞까지
  run(g, C.NINJA_BLINK_CD_MS);
  for (let y = 0; y < C.GRID_D; y++) g.grid[g.idx(3, y, 0)] = CELL.BUILD;
  g.gridChanged();
  place(p(1), 1.5, 4.5, 0);
  g.handleAction(1, { name: 'skill' });
  assert.ok(p(1).x <= 3 - C.PLAYER_HALF + 1e-9 && p(1).x > 2.4, `벽 앞 x=${p(1).x}`);
  // 그림자
  p(1).ult = C.ULT_MAX;
  g.handleAction(1, { name: 'ult' });
  assert.ok(g.isGhost(p(1)) && p(1).critNext);
  for (let y = 0; y < C.GRID_D; y++) g.grid[g.idx(3, y, 0)] = 0;
  g.gridChanged();
  place(p(1), 5, 5, 0);
  place(p(2), 6, 5);
  g.handleAction(1, { name: 'push' });
  assert.ok(lines.some((l) => l.includes('[밀치기] P1 → P2 넉백 치명타')), '땅에서 때려도 치명타');
  assert.equal(p(1).critNext, false, '한 번만');
});

test('건축가: 벽 세우기 = 앞 가로 3 × 2층 (빈 칸만), 블록 비 = 조준한 곳에 1×1 블록 5개', () => {
  const { g, lines, p } = setupChars(['builder', 'tank']);
  place(p(1), 4.5, 4.5, 0); // +x 를 봄
  place(p(2), 8.5, 8.5);
  g.handleAction(1, { name: 'skill' });
  for (const y of [3, 4, 5]) for (const z of [0, 1]) assert.equal(g.gridAt(5, y, z), CELL.BUILD, `(5,${y},${z})`);
  assert.ok(lines.includes('  [스킬] P1 벽 세우기 (6칸)'));
  // 블록 비
  p(1).ult = C.ULT_MAX;
  Object.assign(p(1), { x: 1.5, y: 1.5, yaw: Math.PI / 4, pitch: -0.4 });
  g.handleAction(1, { name: 'ult' });
  const rain = g.pieces.filter((pc) => pc.thrownBy === 1);
  assert.equal(rain.length, C.BUILDER_RAIN_CELLS.length);
  assert.ok(rain.every((pc) => pc.cells.length === 1));
  assert.equal(p(1).ult, 0);
});

test('갈고리: 밀치기 사거리 +, 갈고리는 보는 방향 상대를 내 앞으로 (빗나가도 쿨타임), 회오리는 주변 모두. 끌려간 뒤 떨어지면 갈고리 킬', () => {
  const { g, lines, p } = setupChars(['hook', 'tank', 'tank']);
  // 사거리: 보통 사거리 밖, 늘어난 사거리 안
  place(p(1), 4, 4.5, 0);
  place(p(2), 4 + C.PUSH_RANGE * 1.1, 4.5);
  place(p(3), 9.5, 9.5);
  g.handleAction(1, { name: 'push' });
  assert.ok(p(2).damage > 0);
  run(g, C.STUN_MS + 100);
  // 갈고리
  place(p(1), 1.5, 4.5, 0);
  place(p(2), 5.5, 4.5);
  g.handleAction(1, { name: 'skill' });
  assert.ok(Math.abs(p(2).x - (1.5 + C.HOOK_PULL_TO)) < 0.05, `끌려옴 x=${p(2).x}`);
  assert.ok(lines.includes('  [스킬] P1 갈고리 → P2'));
  assert.equal(p(2).lastHit.kind, 'hook');
  // 끌려온 뒤 (다른 공격 없이) 떨어지면 갈고리 킬
  Object.assign(p(2), { x: -3, z: C.FALL_DEATH_Z - 1 });
  g.tick(TICK);
  assert.ok(lines.some((l) => /\[사망\] P2 낙사 .*킬 P1 갈고리/.test(l)));
  // 빗나감도 쿨타임
  run(g, C.HOOK_CD_MS);
  place(p(1), 1.5, 4.5, Math.PI);
  g.handleAction(1, { name: 'skill' });
  assert.ok(lines.includes('  [스킬] P1 갈고리 빗나감'));
  assert.ok(p(1).skillReadyAt > g.time);
  // 회오리
  place(p(1), 5, 5);
  place(p(3), 8, 5);
  p(1).ult = C.ULT_MAX;
  g.handleAction(1, { name: 'ult' });
  assert.ok(Math.abs(p(3).x - (5 + C.HOOK_PULL_TO)) < 0.05, `회오리 x=${p(3).x}`);
  assert.ok(p(3).freezeUntil > g.time, '잠깐 못 움직임');
  // 끌어온 바로 다음 밀치기가 먹힘 (넉백 무시가 아님)
  p(1).yaw = 0;
  g.handleAction(1, { name: 'push' });
  assert.ok(p(3).damage > 0, '갈고리 → 밀치기 연계');
});

test('캐릭터: 팀전이면 같은 팀은 갈고리·회오리·지면 강타 대상이 아님', () => {
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
  assert.equal(p(2).damage, 0, '같은 팀');
  assert.equal(p(3).damage, C.TANK_SLAM_DAMAGE);
});

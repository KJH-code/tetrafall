// JS 판(server/game.js)에서 비교 숫자를 뽑는다. 고도 테스트(tests/test_compare.gd)가 같은 장면을 돌려 이 값과 비교.
// 실행: node godot/prototype/tools/js_compare.mjs  (JS 파일은 읽기만 함)
import { Game } from '../../../server/game.js';
import { CONFIG as C } from '../../../shared/config.js';

const TICK = 1000 / C.TICK_RATE;

// 2인 평지 (지형 비움), 블록 안 떨어짐
function setup() {
  const g = new Game();
  g.rng = () => 0.5;
  g.addPlayer(1);
  g.addPlayer(2);
  g.startRound();
  g.grid.fill(0);
  g.gridChanged();
  g.pieces = [];
  g.refreshPieceCells();
  g.nextSpawnAt = Infinity;
  return { g, a: g.players.get(1), b: g.players.get(2) };
}
const run = (g, ms) => {
  for (let t = 0; t < ms - 1e-6; t += TICK) g.tick(TICK);
};
const r3 = (v) => Math.round(v * 1000) / 1000;
const out = {};

// 1. 밀치기 한 방: A(3,5) 가 +x 를 보고, B(4.2,5) 를 밀침 → 2초 뒤 B 가 밀려난 거리 (피해 0%, 50%)
for (const dmg of [0, 50]) {
  const { g, a, b } = setup();
  Object.assign(a, { x: 3, y: 5, yaw: 0 });
  Object.assign(b, { x: 4.2, y: 5, yaw: Math.PI, damage: dmg });
  g.handleAction(1, { name: 'push' });
  run(g, 2000);
  out[`push_dist_${dmg}`] = r3(b.x - 4.2);
  out[`push_damage_after_${dmg}`] = b.damage;
}

// 2. 블록 낙하: O 블록이 PIECE_SPAWN_Z 에서 빈 칸(4,4)에 착지할 때까지 시간 (ms), 그리고 (2,2) 면 P1(2.5,2.5) 압사까지 시간
for (const [key, px] of [['piece_land_ms', 4], ['crush_ms', 2]]) {
  const { g, a } = setup();
  const pc = g.makePiece('O', 0, px, px, C.PIECE_SPAWN_Z);
  Object.assign(pc, { phase: 'falling', controller: null, stepMs: C.AUTO_FALL_STEP_MS, nextStepAt: g.time + C.AUTO_FALL_STEP_MS, controlEndsAt: 0 });
  g.addPiece(pc, {});
  const t0 = g.time;
  let at = null;
  for (let i = 0; i < 2000 && at === null; i++) {
    g.tick(TICK);
    if (key === 'piece_land_ms' ? !g.pieces.includes(pc) : !a.alive) at = g.time - t0;
  }
  out[key] = at === null ? null : r3(at);
}

// 3. 점프: 최고 높이·공중 시간
{
  const { g, a } = setup();
  Object.assign(a, { x: 5, y: 5 });
  g.handleInput(1, { fwd: 0, strafe: 0, jump: true, yaw: 0 });
  g.tick(TICK);
  g.handleInput(1, { fwd: 0, strafe: 0, jump: false, yaw: 0 });
  let peak = 0;
  let air = TICK;
  for (let i = 0; i < 200; i++) {
    g.tick(TICK);
    peak = Math.max(peak, a.z);
    if (a.grounded) break;
    air += TICK;
  }
  out.jump_peak = r3(peak);
  out.jump_air_ms = r3(air);
}

// 4. 대시: 제자리에서 +x 대시 → 2초 뒤 이동 거리
{
  const { g, a } = setup();
  Object.assign(a, { x: 2, y: 5, yaw: 0 });
  g.handleAction(1, { name: 'dash' });
  run(g, 2000);
  out.dash_dist = r3(a.x - 2);
}

// 5. 걷기: 1초 앞으로
{
  const { g, a } = setup();
  Object.assign(a, { x: 2, y: 5, yaw: 0 });
  g.handleInput(1, { fwd: 1, strafe: 0, jump: false, yaw: 0 });
  run(g, 1000);
  out.walk_1s = r3(a.x - 2);
}

// 6. 낙사: 피해 150% 인 B 를 가장자리 쪽으로 밀침 → 낙사까지 시간 (ms)
{
  const { g, a, b } = setup();
  Object.assign(a, { x: 7.5, y: 5, yaw: 0 });
  Object.assign(b, { x: 8.7, y: 5, damage: 150 });
  g.handleAction(1, { name: 'push' });
  const t0 = g.time;
  let dead = null;
  for (let i = 0; i < 300 && dead === null; i++) {
    g.tick(TICK);
    if (!b.alive) dead = g.time - t0;
  }
  out.fall_death_ms = dead === null ? null : r3(dead);
  out.fall_death_cause = g.deaths[0]?.cause ?? null;
}

// ---- 닌자 (캐릭터 켬, 둘 다 닌자) ----
function setupNinja() {
  const g = new Game(() => {}, { characters: true });
  g.rng = () => 0.5;
  g.addPlayer(1);
  g.addPlayer(2);
  for (const p of g.players.values()) p.char = 'ninja';
  g.startRound();
  g.grid.fill(0);
  g.gridChanged();
  g.pieces = [];
  g.refreshPieceCells();
  g.nextSpawnAt = Infinity;
  return { g, a: g.players.get(1), b: g.players.get(2) };
}

// 7. 닌자 지상 연타: 3틱마다 평타를 1.5초 누름 → 3초 뒤 B 피해·밀린 거리·최고 높이, A 앞으로 나간 거리
{
  const { g, a, b } = setupNinja();
  Object.assign(a, { x: 3, y: 5, yaw: 0 });
  Object.assign(b, { x: 4, y: 5, yaw: Math.PI });
  let peak = 0;
  for (let i = 0; i < 90; i++) {
    if (i < 45 && i % 3 === 0) g.handleAction(1, { name: 'push' });
    g.tick(TICK);
    peak = Math.max(peak, b.z);
  }
  out.ninja_combo_damage = b.damage;
  out.ninja_combo_bx = r3(b.x - 4);
  out.ninja_combo_bpeak = r3(peak);
  out.ninja_combo_ax = r3(a.x - 3);
  out.ninja_combo_ult = r3(a.ult);
}

// 8. 닌자 F 순간 베기 (지상 → 150ms 준비): A(2,5) → B(4,5) 를 지나 뒤에 섬. 1초 뒤
{
  const { g, a, b } = setupNinja();
  Object.assign(a, { x: 2, y: 5, yaw: 0 });
  Object.assign(b, { x: 4, y: 5 });
  g.handleAction(1, { name: 'skill' });
  run(g, 1000);
  out.ninja_blink_ax = r3(a.x);
  out.ninja_blink_bdamage = b.damage;
  out.ninja_blink_bx = r3(b.x);
}

// 9. 닌자 R 강화 → 평타 = 표창 2연발 (사거리 3): A(2,5) B(4.5,5). 1초 뒤 B 피해
{
  const { g, a, b } = setupNinja();
  Object.assign(a, { x: 2, y: 5, yaw: 0, ult: 100 });
  Object.assign(b, { x: 4.5, y: 5 });
  g.handleAction(1, { name: 'ult' });
  g.tick(TICK);
  g.handleAction(1, { name: 'push' });
  run(g, 1000);
  out.ninja_star_bdamage = b.damage;
  out.ninja_star_bx = r3(b.x - 4.5);
}

// 10. 닌자 F 벽 차기: 2칸 벽 (5,*) 앞에서 순간 베기 → 위로 튀는 최고 높이
{
  const { g, a } = setupNinja();
  for (let y = 0; y < g.D; y++) for (let z = 0; z < 2; z++) g.grid[g.idx(5, y, z)] = 1;
  g.gridChanged();
  Object.assign(a, { x: 3.5, y: 5.5, yaw: 0 });
  g.handleAction(1, { name: 'skill' });
  let peak = 0;
  for (let i = 0; i < 60; i++) {
    g.tick(TICK);
    peak = Math.max(peak, a.z);
  }
  out.ninja_wallkick_ax = r3(a.x);
  out.ninja_wallkick_peak = r3(peak);
}

console.log(JSON.stringify(out, null, 2));

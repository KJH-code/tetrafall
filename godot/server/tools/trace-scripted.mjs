// 각본 판 기록 (S3 전투·캐릭터 검증용, 봇 없이): 캐릭터마다 사람 둘이 정해진 틱에 입력·행동을 넣는 판을 틱마다 한 줄 JSONL 로 — trace.mjs 와 같은 형식
// {"t":틱,"logs":[...],"snap":스냅샷 글자}. 킬 점수전 (떨어져도 부활), 블록·아이템은 끔 (nextSpawnAt·아이템 시각 = Infinity) → 전투·캐릭터만. C# 쪽은 같은 각본 자료를 돌려 trace-diff.mjs 로 비교.
// 실행: node godot/server/tools/trace-scripted.mjs <캐릭터|번호> <출력.jsonl> [--combat (전투만 도는 틱)]   ·  --list (각본 목록) · --dump <파일.json> (각본 자료 — C# 가 읽음)
//
// 각본 단계 (틱 t 에, 틱을 돌리기 전에): { t, who, input: { fwd, strafe, jump, pitch } } — yaw 는 상대 쪽 (face: true) 또는 값
//                                       { t, who, action: { name, ... } } · { t, who, set: { ult: 'max' } } (필살기 게이지 채우기)
//                                       { t, who, set: { reset: true } } (둘을 가운데 근처로: P1 (W/2-1, D/2), P2 (W/2+0.2, D/2), 바닥, 속도 0)
import fs from 'node:fs';
import { Game } from '../../../server/game.js';
import { CONFIG as C } from '../../../shared/config.js';
import { mulberry32 } from '../../../tools/sim.js';

const TICK = 1000 / C.TICK_RATE;

// 캐릭터 하나의 각본: P1 = 그 캐릭터, P2 = 상대 (opp). 다가가며 평타 3타 → 스킬 → 점프·공중 평타 → 대시 → 필살기 → 상대도 반격
function scriptFor(ch, opp) {
  const s = [];
  const face = (t, who, fwd = 1) => s.push({ t, who, input: { fwd, strafe: 0, jump: false, pitch: 0, face: true } });
  for (let t = 0; t < 600; t += 15) {
    face(t, 1, t < 450 ? 1 : 0);
    face(t, 2, t >= 300 ? 1 : 0);
  }
  const act = (t, who, name, extra = {}) => s.push({ t, who, action: { name, ...extra } });
  [20, 28, 36].forEach((t) => act(t, 1, 'push'));
  act(80, 1, 'skill');
  act(130, 1, 'jump');
  act(138, 1, 'push');
  act(170, 1, 'dash');
  s.push({ t: 199, who: 1, set: { ult: 'max' } });
  act(200, 1, 'ult');
  [260, 268, 276].forEach((t) => act(t, 1, 'push'));
  s.push({ t: 284, who: 1, set: { ult: 'max' } }); // 평타를 맞힌 뒤 필살기 한 번 더 (사냥꾼은 표식이 쌓인 뒤라야 쏨)
  act(285, 1, 'ult');
  act(300, 2, 'push');
  act(310, 2, 'push');
  act(330, 2, 'skill');
  act(360, 1, 'skill');
  s.push({ t: 389, who: 2, set: { ult: 'max' } });
  act(390, 2, 'ult');
  act(420, 1, 'jump');
  act(424, 1, 'jump');
  act(430, 1, 'push');
  act(470, 1, 'dash');
  act(480, 1, 'push');
  // 떨어져 나간 사람 때문에 싸움이 끊기지 않게 150틱마다 둘을 가운데 근처로 (위치·속도만)
  for (const t of [150, 300, 450]) s.push({ t, who: 1, set: { reset: true } });
  [152, 156, 160, 164, 302, 306].forEach((t) => act(t, 1, 'push'));
  [154, 158, 304].forEach((t) => act(t, 2, 'push'));
  s.sort((a, b) => a.t - b.t);
  return s;
}

export const SCRIPTS = C.CHARACTERS.map((ch, i) => ({
  name: ch,
  seed: 1000 + i,
  chars: [ch, ch === 'ninja' ? 'tank' : 'ninja'],
  ticks: 600,
  mode: 'kills',
  steps: scriptFor(ch, ch === 'ninja' ? 'tank' : 'ninja'),
}));

// 전투만 도는 틱 (S3 검증용, 판 흐름(S2)·아이템(S4) 없이): server/game.js tick 에서 블록·낙사·부활·용암·아이템·판 끝을 뺀 같은 순서.
// 떨어진 사람은 죽지 않고 계속 떨어짐 (양쪽 같게). C# 쪽은 tests/Tetrafall.Tests/CombatTraceTests.cs 의 CombatTick
export function combatTick(g, dtMs) {
  g.flushLogs();
  g.time += dtMs;
  if (g.phase !== 'playing') return;
  const dt = dtMs / 1000;
  let remaining = dt;
  while (remaining > 0) {
    const h = Math.min(remaining, C.MAX_STEP_DT);
    for (const p of g.players.values()) if (g.onField(p)) g.integratePlayer(p, h);
    remaining -= h;
  }
  for (const p of g.players.values()) if (p.grounded && p.alive && g.onField(p)) p.lastGround = g.groundKind(p);
  g.updateCombat();
  if (g.shells.length) g.updateShells(dt);
  if (g.notes.length) g.updateNotes(dt);
}

// 한 판 기록. onLine(줄 객체) 로 내보냄. combat: 전투만 도는 틱 (combatTick)
export function runScript(sc, onLine, { combat = false } = {}) {
  const rnd = mulberry32(sc.seed);
  const realRandom = Math.random;
  Math.random = mulberry32(sc.seed ^ 0x5bd1e995);
  let logs = [];
  try {
    // 전투만: 카운트다운 1ms 로 시작하고 바로 'playing' (판 시작 beginPlay 는 판 흐름 S2 — C# 에 아직 없음. A1 physics 자료와 같은 방법)
    const g = new Game((line) => logs.push(line), { characters: true, skyStairs: false, countdownMs: combat ? 1 : 0 });
    g.rng = rnd;
    g.addPlayer(1);
    g.addPlayer(2);
    g.setChar(1, sc.chars[0]);
    g.setChar(2, sc.chars[1]);
    g.setMap('flat');
    g.setMode(sc.mode); // 킬 점수전: 떨어져도 부활 → 각본 끝까지 (생존이면 첫 낙사에 판이 끝남)
    if (!g.startRound()) throw new Error('시작 못 함');
    if (combat) g.phase = 'playing';
    g.nextSpawnAt = Infinity;
    g.controlItemNextAt = Infinity;
    g.powerItemNextAt = Infinity;
    onLine({ t: 0, logs, snap: JSON.stringify(g.snapshot(true)) });
    logs = [];
    let k = 0;
    for (let ticks = 0; ticks < sc.ticks && g.phase !== 'over'; ) {
      for (; k < sc.steps.length && sc.steps[k].t === ticks; k++) {
        const st = sc.steps[k];
        const p = g.players.get(st.who);
        const o = g.players.get(st.who === 1 ? 2 : 1);
        if (st.input) {
          const { face, ...inp } = st.input;
          g.handleInput(st.who, { type: 'input', ...inp, yaw: face && p && o ? Math.atan2(o.y - p.y, o.x - p.x) : (st.input.yaw ?? 0) });
        } else if (st.action) g.handleAction(st.who, { type: 'action', ...st.action });
        else if (st.set && p && st.set.ult === 'max') p.ult = C.ULT_MAX * (p.char === 'hunter' ? C.HUNTER_ULT_MULT : 1);
        else if (st.set && st.set.reset) {
          for (const [id, x] of [[1, g.W / 2 - 1], [2, g.W / 2 + 0.2]]) {
            const q = g.players.get(id);
            Object.assign(q, { x, y: g.D / 2, z: 0, vz: 0, kbx: 0, kby: 0, grounded: true });
          }
        }
      }
      if (combat) combatTick(g, TICK);
      else g.tick(TICK);
      ticks++;
      const snap = g.snapshot(ticks % 300 === 0);
      snap.events = g.drainEvents();
      onLine({ t: ticks, logs, snap: JSON.stringify(snap) });
      logs = [];
    }
  } finally {
    Math.random = realRandom;
  }
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(new URL(import.meta.url).pathname)) {
  const arg = process.argv[2];
  if (arg === '--list') {
    SCRIPTS.forEach((s, i) => console.log(`${i}\t${s.name}\t${s.chars.join(' vs ')}\t단계 ${s.steps.length}`));
  } else if (arg === '--dump') {
    fs.writeFileSync(process.argv[3] ?? 'scripts.json', JSON.stringify(SCRIPTS));
  } else {
    const combat = process.argv.includes('--combat');
    const sc = /^\d+$/.test(arg ?? '') ? SCRIPTS[Number(arg)] : SCRIPTS.find((s) => s.name === arg);
    if (!sc) throw new Error(`각본 없음: ${arg} (--list)`);
    const out = process.argv[3] ?? 'js.jsonl';
    const fd = fs.openSync(out, 'w');
    let n = 0;
    try {
      runScript(sc, (line) => {
        fs.writeSync(fd, JSON.stringify(line) + '\n');
        n++;
      }, { combat });
    } finally {
      fs.closeSync(fd);
    }
    console.log(`${sc.name}: ${n - 1}틱 → ${out}`);
  }
}

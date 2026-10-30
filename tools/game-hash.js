// 동작 기준선 (2026-10-30 game.js 쪼개기 확인용): 시드 고정 봇 판 여러 가지를 돌려 틱마다 스냅샷·이벤트·로그를 해시.
// 코드를 옮기기만 했으면 해시가 한 글자도 안 바뀌어야 함. 실행: node tools/game-hash.js  (--verbose 면 판마다)
//   여러 판: 인원 2·4·8 · 모드 생존·블록 마스터·킬 점수전 · 팀전 · 캐릭터 켬/끔 · 하늘 계단 켬/끔 · 맵 7개 · 끊긴 사람 봇 대리 · 연습 (허수아비)
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { Game } from '../server/game.js';
import { MAP_IDS } from '../server/maps.js';
import { CONFIG as C } from '../shared/config.js';
import { mulberry32 } from './sim.js';

const TICK = 1000 / C.TICK_RATE;
const CAP_MS = 120000; // 판 하나 최대 (해시는 그때까지)

// [이름, 인원, 옵션]
export const SCENARIOS = [];
let k = 0;
for (const n of [2, 4, 8]) {
  for (const [mode, team] of [['survival', false], ['survival', true], ['master', false], ['kills', false], ['kills', true]]) {
    if (team && n < 4) continue;
    for (const characters of [true, false]) {
      for (const sky of [true, false]) {
        if (!characters && (mode !== 'survival' || n === 8)) continue; // 예전 규칙 판은 조금만
        SCENARIOS.push({ name: `${n}명 ${mode}${team ? ' 팀' : ''}${characters ? ' 캐릭터' : ''}${sky ? ' 하늘' : ''}`, n, mode, team, characters, sky, map: MAP_IDS[k % MAP_IDS.length], seed: 1000 + k });
        k++;
      }
    }
  }
}
SCENARIOS.push({ name: '4명 끊긴 사람 봇 대리', n: 4, mode: 'survival', team: false, characters: true, sky: true, map: 'pyramid', seed: 9002, away: true });
SCENARIOS.push({ name: '연습 허수아비', n: 1, mode: 'practice', team: false, characters: true, sky: false, map: 'flat', seed: 9001 });

export function runScenario(sc) {
  const h = crypto.createHash('sha256');
  const rnd = mulberry32(sc.seed);
  const realRandom = Math.random;
  Math.random = mulberry32(sc.seed ^ 0x5bd1e995); // 혹시 Math.random 을 쓰는 곳도 고정
  try {
    const g = new Game((line) => h.update(`L${line}\n`), { characters: sc.characters, skyStairs: sc.sky, countdownMs: 1500 });
    g.rng = rnd;
    if (sc.mode === 'practice') {
      g.addPlayer(1);
      g.setChar(1, 'ninja');
      g.startPractice();
      g.addDummy(1);
      g.addDummy(1);
    } else {
      if (sc.away) g.addPlayer(1); // 사람 하나 (끊겨서 봇이 대신)
      for (let i = sc.away ? 1 : 0; i < sc.n; i++) {
        const b = g.addBot();
        if (sc.characters) g.setChar(b.id, C.CHARACTERS[Math.floor(rnd() * C.CHARACTERS.length)]);
      }
      if (sc.team) g.setTeamMode(true);
      if (sc.mode !== 'survival') g.setMode(sc.mode);
      g.setMap(sc.map);
      if (!g.startRound()) throw new Error(`${sc.name}: 시작 못 함`);
    }
    let t = 0;
    let ticks = 0;
    const cap = sc.mode === 'practice' ? 20000 : CAP_MS;
    while (t < cap && g.phase !== 'over') {
      if (sc.mode === 'practice' && ticks % 15 === 0) {
        // 연습: 내가 앞으로 가며 평타·대시 (허수아비 콤보 기록)
        g.handleInput(1, { fwd: 1, strafe: 0, jump: ticks % 90 === 0, yaw: (ticks / 200) % (2 * Math.PI), pitch: 0 });
        g.handleAction(1, { name: ticks % 60 === 0 ? 'dash' : 'push' });
      }
      if (sc.away && ticks === 0) g.setAway(1, true);
      if (sc.away && ticks === 900) g.setAway(1, false);
      g.tick(TICK);
      t += TICK;
      ticks++;
      const snap = g.snapshot(ticks % 300 === 0); // 가끔 격자도 통째로
      snap.events = g.drainEvents();
      h.update(JSON.stringify(snap));
    }
    return { name: sc.name, hash: h.digest('hex'), ticks, phase: g.phase };
  } finally {
    Math.random = realRandom;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const verbose = process.argv.includes('--verbose');
  const all = crypto.createHash('sha256');
  const t0 = Date.now();
  for (const sc of SCENARIOS) {
    const r = runScenario(sc);
    all.update(r.hash);
    if (verbose) console.log(`${r.hash.slice(0, 16)}  ${String(r.ticks).padStart(5)}틱 ${r.phase.padEnd(8)} ${r.name}`);
  }
  console.log(`판 ${SCENARIOS.length}개 해시 ${all.digest('hex')} (${((Date.now() - t0) / 1000).toFixed(1)}초)`);
}

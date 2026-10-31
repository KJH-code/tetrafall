// 같은 시드 봇 판의 로그 파일 (JS 쪽): tools/game-hash.js 시나리오 34판을 runScenario 와 같은 순서로 돌려
// 판마다 방 로그 파일 모양 (`[0시 0분 0초] 줄`, 시각은 고정) 으로 <폴더>/<번호>_S<번호>.txt 에 씀 → npm run stats -- <폴더>.
// C# 쪽: dotnet godot/server/src/Tetrafall.Trace/bin/Release/net10.0/Tetrafall.Trace.dll logs <폴더> — 두 stats 결과를 diff
// 실행: node godot/server/tools/scenario-logs.mjs <폴더>
import fs from 'node:fs';
import path from 'node:path';
import { SCENARIOS } from '../../../tools/game-hash.js';
import { Game } from '../../../server/game.js';
import { CONFIG as C } from '../../../shared/config.js';
import { mulberry32 } from '../../../tools/sim.js';

const TICK = 1000 / C.TICK_RATE;
const CAP_MS = 120000;
const dir = process.argv[2] ?? 'js-logs';
fs.mkdirSync(dir, { recursive: true });
SCENARIOS.forEach((sc, i) => {
  const lines = [];
  const rnd = mulberry32(sc.seed);
  const realRandom = Math.random;
  Math.random = mulberry32(sc.seed ^ 0x5bd1e995);
  try {
    const g = new Game((line) => lines.push(`[0시 0분 0초] ${line}`), { characters: sc.characters, skyStairs: sc.sky, countdownMs: 1500 });
    g.rng = rnd;
    if (sc.mode === 'practice') {
      g.addPlayer(1);
      g.setChar(1, 'ninja');
      g.startPractice();
      g.addDummy(1);
      g.addDummy(1);
    } else {
      if (sc.away) g.addPlayer(1);
      for (let k = sc.away ? 1 : 0; k < sc.n; k++) {
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
        g.handleInput(1, { fwd: 1, strafe: 0, jump: ticks % 90 === 0, yaw: (ticks / 200) % (2 * Math.PI), pitch: 0 });
        g.handleAction(1, { name: ticks % 60 === 0 ? 'dash' : 'push' });
      }
      if (sc.away && ticks === 0) g.setAway(1, true);
      if (sc.away && ticks === 900) g.setAway(1, false);
      g.tick(TICK);
      t += TICK;
      ticks++;
      g.snapshot(ticks % 300 === 0);
      g.drainEvents();
    }
  } finally {
    Math.random = realRandom;
  }
  fs.writeFileSync(path.join(dir, `${String(i).padStart(2, '0')}_S${String(i).padStart(3, '0')}.txt`), lines.join('\n') + '\n');
});
console.log(`${SCENARIOS.length}판 → ${dir}`);

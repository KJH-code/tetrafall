// 튜토리얼 판 기록 (S4 검증): 캐릭터마다 사람 하나가 튜토리얼을 자동 조종 (shared/tutorial-pilot.js) 으로 끝까지. 게임 난수는 mulberry32(8000 + 캐릭터 번호).
// C# 는 src/Tetrafall.Trace/Scenarios.cs RunTutorial (+ TutorialPilot.cs) 이 같은 판을 돌림.
// 실행: node godot/server/tools/tutorial-trace.mjs <캐릭터> js.jsonl
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { Game } from '../../../server/game.js';
import { CONFIG as C } from '../../../shared/config.js';
import { TutorialPilot } from '../../../shared/tutorial-pilot.js';
import { mulberry32 } from '../../../tools/sim.js';

const TICK = 1000 / C.TICK_RATE;
export const TUTORIAL_CAP_MS = 240000;

// onLine({ t, logs, snap }) 틱마다 (t=0 = 시작 직후). 반환 { ticks, done, results }
export function runTutorial(char, onLine) {
  let logs = [];
  const g = new Game((l) => logs.push(l), { countdownMs: 0, characters: true, skyStairs: false });
  g.rng = mulberry32(8000 + C.CHARACTERS.indexOf(char));
  g.addPlayer(1);
  g.setChar(1, char);
  g.startTutorial(1);
  onLine({ t: 0, logs, snap: JSON.stringify(g.snapshot(true)) });
  logs = [];
  const pilot = new TutorialPilot();
  let ticks = 0;
  for (let t = 0; t < TUTORIAL_CAP_MS && !g.tutorial.done; t += TICK) {
    const { input, actions } = pilot.next(g.snapshot(false), 1);
    g.handleInput(1, input);
    for (const a of actions) g.handleAction(1, { name: a });
    g.tick(TICK);
    ticks++;
    const snap = g.snapshot(ticks % 300 === 0);
    snap.events = g.drainEvents();
    onLine({ t: ticks, logs, snap: JSON.stringify(snap) });
    logs = [];
  }
  return { ticks, done: g.tutorial.done, results: g.tutorial.results };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const char = process.argv[2] ?? 'tank';
  const out = process.argv[3] ?? 'js.jsonl';
  const fd = fs.openSync(out, 'w');
  const r = runTutorial(char, (line) => fs.writeSync(fd, JSON.stringify(line) + '\n'));
  fs.closeSync(fd);
  console.log(`튜토리얼 ${char}: ${r.ticks}틱 ${r.done ? '끝' : '못 끝냄'} [${r.results.join(' ')}] → ${out}`);
}

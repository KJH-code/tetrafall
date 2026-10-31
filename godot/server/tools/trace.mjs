// JS 판 기록 (C# 이식 검증용): tools/game-hash.js 의 시나리오 하나를 돌려 틱마다 한 줄 JSONL — {"t":틱,"logs":[...],"snap":스냅샷 글자}
// C# 쪽 (Tetrafall.Trace, 판 규칙을 옮긴 뒤) 도 같은 형식으로 쓰고 trace-diff.mjs 로 처음 갈라지는 곳을 찾음.
// 실행: node godot/server/tools/trace.mjs <시나리오 번호|이름 일부> <출력.jsonl>   (번호 목록: node godot/server/tools/trace.mjs --list)
import fs from 'node:fs';
import { SCENARIOS } from '../../../tools/game-hash.js';
import { Game } from '../../../server/game.js';
import { CONFIG as C } from '../../../shared/config.js';
import { mulberry32 } from '../../../tools/sim.js';
import { SCRIPTED, setupScripted, driveScripted } from './scripted.mjs';

if (process.argv[2] === '--list') {
  SCENARIOS.forEach((s, i) => console.log(`${i}\t${s.name}\t맵 ${s.map}\t시드 ${s.seed}`));
  SCRIPTED.forEach((s, i) => console.log(`s${i}\t${s.name}\t맵 ${s.map}\t시드 ${s.seed}`));
  process.exit(0);
}
const TICK0 = 1000 / C.TICK_RATE;
// 각본 입력 판 (s0, s1 …): scripted.mjs
if (/^s\d+$/.test(process.argv[2] ?? '')) {
  const sc = SCRIPTED[Number(process.argv[2].slice(1))];
  const outPath = process.argv[3] ?? 'js.jsonl';
  const fd = fs.openSync(outPath, 'w');
  let logs = [];
  const { g, rr } = setupScripted(Game, sc, (line) => logs.push(line));
  fs.writeSync(fd, JSON.stringify({ t: 0, logs, snap: JSON.stringify(g.snapshot(true)) }) + '\n');
  logs = [];
  let t = 0;
  let ticks = 0;
  while (t < 120000 && g.phase !== 'over') {
    driveScripted(g, rr, ticks);
    g.tick(TICK0);
    t += TICK0;
    ticks++;
    const snap = g.snapshot(ticks % 300 === 0);
    snap.events = g.drainEvents();
    fs.writeSync(fd, JSON.stringify({ t: ticks, logs, snap: JSON.stringify(snap) }) + '\n');
    logs = [];
  }
  fs.closeSync(fd);
  console.log(`${sc.name}: ${ticks}틱 ${g.phase} → ${outPath}`);
  process.exit(0);
}
const key = process.argv[2] ?? '0';
const sc = /^\d+$/.test(key) ? SCENARIOS[Number(key)] : SCENARIOS.find((s) => s.name.includes(key));
if (!sc) throw new Error(`시나리오 없음: ${key}`);
const outPath = process.argv[3] ?? 'js.jsonl';
const TICK = 1000 / C.TICK_RATE;
// tools/game-hash.js runScenario 와 같은 순서 (해시 대신 줄로)
const rnd = mulberry32(sc.seed);
const realRandom = Math.random;
Math.random = mulberry32(sc.seed ^ 0x5bd1e995);
const fd = fs.openSync(outPath, 'w');
let logs = [];
try {
  const g = new Game((line) => logs.push(line), { characters: sc.characters, skyStairs: sc.sky, countdownMs: 1500 });
  g.rng = rnd;
  if (sc.mode === 'practice') {
    g.addPlayer(1);
    g.setChar(1, 'ninja');
    g.startPractice();
    g.addDummy(1);
    g.addDummy(1);
  } else {
    if (sc.away) g.addPlayer(1);
    for (let i = sc.away ? 1 : 0; i < sc.n; i++) {
      const b = g.addBot();
      if (sc.characters) g.setChar(b.id, C.CHARACTERS[Math.floor(rnd() * C.CHARACTERS.length)]);
    }
    if (sc.team) g.setTeamMode(true);
    if (sc.mode !== 'survival') g.setMode(sc.mode);
    g.setMap(sc.map);
    if (!g.startRound()) throw new Error('시작 못 함');
  }
  fs.writeSync(fd, JSON.stringify({ t: 0, logs, snap: JSON.stringify(g.snapshot(true)) }) + '\n');
  logs = [];
  let t = 0;
  let ticks = 0;
  const cap = sc.mode === 'practice' ? 20000 : 120000;
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
    const snap = g.snapshot(ticks % 300 === 0);
    snap.events = g.drainEvents();
    fs.writeSync(fd, JSON.stringify({ t: ticks, logs, snap: JSON.stringify(snap) }) + '\n');
    logs = [];
  }
  console.log(`${sc.name}: ${ticks}틱 → ${outPath}`);
} finally {
  Math.random = realRandom;
  fs.closeSync(fd);
}

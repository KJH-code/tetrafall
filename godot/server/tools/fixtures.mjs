// JS 판에서 C# 테스트의 정답 자료를 뽑음 → tests/Tetrafall.Tests/fixtures/*.json. 실행: node godot/server/tools/fixtures.mjs
// - jsmath.json: Math.sin·cos·exp·atan2·hypot·round 의 입력·출력 비트 (C# JsMath 가 V8 과 비트까지 같은지)
// - jsnumber.json: 숫자 → JSON.stringify 글자 (C# JsNumber·JsonOut)
// - mulberry32.json: 시드별 처음 값들 (tools/sim.js mulberry32)
// - protocol-rooms.json: room-scenarios.mjs 각본마다 단계·JS 가 보낸 메시지·로그 (C# RoomScenarioTests 가 같은 각본을 돌림)
// - jsvalue.json: 받은 JSON 값의 String(x)·String(x ?? '')·!!x·Number(x) (C# JsValue), 이름 정리 (setNick·방 이름, C# JsText.Clean), BOT_LEVELS 키
// - protocol-lobby.json: 방 만들기·들어가기·핑·나가기 각본에서 JS 서버(rooms.js)가 보낸 메시지·로그 글자 그대로 (C# Rooms 가 같은지)
// - maps.json: 맵 7개 × 판 크기 10~19 시작 지형 (shared/maps.js mapColumns)
// - combat-trace.json: trace-scripted.mjs 각본 (캐릭터 8명) 을 전투만 도는 틱으로 돌린 틱 줄 sha256 앞 16자
// - blocks-trace.json: 같은 각본을 보통 틱 + 블록 낙하로 돌린 틱 줄 sha256 앞 16자
// - trace-t0.json: 시나리오 0~32 (tools/game-hash.js) 의 trace 첫 줄 (판 시작 직후, 격자 포함) sha256 — C# 판 시작이 글자까지 같은지
// - scripted.json: 각본 입력 판 8개 (scripted.mjs, 캐릭터 끔) 의 trace 줄 전체 sha256·틱 수 — C# 판 흐름·블록이 처음부터 끝까지 글자까지 같은지
// - game-hash.json: tools/game-hash.js 34판 판마다 해시·틱 수 (C# 가 그 판을 다 돌 수 있게 되면 같아야 함 — 봇 판은 S5 뒤)
// - tutorial-trace.json: 캐릭터 8명 튜토리얼 자동 조종 판 (tutorial-trace.mjs) trace 줄 전체 sha256·틱 수·결과
// - sim.json: tools/sim.js 작은 판 (2·3인 × 맵 7개, 28판 × 자리 바꿔 2번) summarizeSim·formatSim 결과 + 판 로그 sha256 (C# Tetrafall.Sim 이 같은지)
// - physics.json: 맵 7개 × 2·4·8인, 무작위 입력·넉백으로 물리만 300틱 (integratePlayer·groundKind) → 10틱마다 위치·속도
import fs from 'node:fs';
import crypto from 'node:crypto';
import { SCENARIOS as HASH_SCENARIOS, runScenario } from '../../../tools/game-hash.js';
import { runTutorial } from './tutorial-trace.mjs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Rooms } from '../../../server/rooms.js';
import { mulberry32, parseArgs as simArgs, planJobs, runJob, summarizeSim, formatSim } from '../../../tools/sim.js';
import { SCENARIOS as ROOM_SCENARIOS, runJs } from './room-scenarios.mjs';
import { SCRIPTS as COMBAT_SCRIPTS, runScript } from './trace-scripted.mjs';
import { Game } from '../../../server/game.js';
import { MAP_IDS, mapColumns } from '../../../shared/maps.js';
import { SCRIPTED, setupScripted, driveScripted } from './scripted.mjs';
import { CONFIG as C } from '../../../shared/config.js';

const out = path.join(path.dirname(fileURLToPath(import.meta.url)), '../tests/Tetrafall.Tests/fixtures');
const bits = (x) => Buffer.from(new Float64Array([x]).buffer).toString('hex');
const r = mulberry32(4242);
const write = (name, data) => fs.writeFileSync(path.join(out, name), JSON.stringify(data));

// 수학: 게임에 나오는 범위 + 경계
const ins = [];
for (let i = 0; i < 1500; i++) ins.push([(r() - 0.5) * (i % 4 === 0 ? 60 : 8), (r() - 0.5) * 20, (r() - 0.5) * 6]);
ins.push([0, 0, 0], [-0, 1, 0], [Math.PI / 2, -Math.PI, 0], [1e-300, -1e-300, 0], [700, -745, 3], [0.5, -0.5, 2.5], [-2.5, 1.5, -0.4999999999999999]);
const math = ins.map(([a, b, c]) => [bits(a), bits(b), bits(c), bits(Math.sin(a)), bits(Math.cos(a)), bits(Math.exp(a > 50 ? 50 : a)), bits(Math.atan2(a, b)), bits(Math.hypot(a, b)), bits(Math.hypot(a, b, c)), bits(Math.round(c)), bits(Math.round(a))]);
write('jsmath.json', math);

// 숫자 글자
const nums = [0, -0, 0.125, -0.125, 0.5, -0.5, 1.005, 2.5, -2.5, 0.045, -0.04, 1e21 + 1, 1, -1, 1e-7, 1.5e-7, 1e-6, 123456789012345680000, 1e21, 1e20, 0.1 + 0.2, 1 / 3, -2.5, 1000 / 30, 5e-324, 1.7976931348623157e308, 2 ** 53, 2 ** 53 + 2, 1e15, 1e16, 123.456, -0.000001];
for (let i = 0; i < 1500; i++) nums.push((r() - 0.5) * 10 ** Math.floor(r() * 50 - 25));
write('jsnumber.json', nums.map((x) => [bits(x), JSON.stringify(x), x.toFixed(0), x.toFixed(1), x.toFixed(2), x.toFixed(3)]));

// mulberry32
write('mulberry32.json', [1, 1000, 4242, 0xffffffff].map((seed) => { const f = mulberry32(seed); return [seed, Array.from({ length: 20 }, () => bits(f()))]; }));

// 대기실 프로토콜 각본 (C# ProtocolTests 와 같은 순서)
const sent = [];
const logs = [];
const sock = (i) => ({ readyState: 1, OPEN: 1, send: (t) => sent.push([i, t]) });
let tk = 0;
class FixedRooms extends Rooms {
  newSeat(room, conn) {
    const token = `token${++tk}`;
    room.seats.set(conn.id, { token, conn, awayAt: null });
    return token;
  }
}
const rooms = new FixedRooms({ rng: mulberry32(77), openLog: (code) => ({ log: (m) => logs.push(`[${code}] ${m}`), close: () => logs.push(`[${code}] (닫음)`) }), serverLog: (m) => logs.push(`[서버] ${m}`), now: () => 0 });
const TICK = 1000 / 30;
const step = () => { rooms.tick(TICK); rooms.broadcast(); };
const c1 = rooms.connect(sock(1));
rooms.message(c1, { type: 'create', name: '', nick: '  재혁\u0001  최고 ' });
step();
const code = c1.room.code;
const c2 = rooms.connect(sock(2));
rooms.message(c2, { type: 'join', code: ` ${code.toLowerCase()} ` });
step();
rooms.message(c2, { type: 'ping', t: 123.5 });
rooms.message(c2, { type: 'ping', t: 'x' });
rooms.message(c1, { type: 'join', code: 'ZZZZ' }); // 방 안이라 무시
rooms.message(c2, { type: 'leave' });
step();
const c3 = rooms.connect(sock(3));
rooms.message(c3, { type: 'join', code: 'nope' });
rooms.message(c3, { type: 'join' });
rooms.message(c3, { type: 'create', name: '이름이 아주 아주 아주 아주 긴 방 이름입니다', nick: 5 });
step();
rooms.broadcastList(true);
rooms.message(c1, { type: 'leave' });
rooms.broadcastList();
write('protocol-lobby.json', { sent, logs });

// 받은 값 → JS 값 바꾸기 (rooms.js 가 msg.x 에 하는 것) + 이름 정리
const vals = ['null', 'true', 'false', '0', '-0', '1', '2.5', '1e21', '1e-7', '"12"', '" 12 "', '""', '"abc"', '"0x1f"', '"0o17"', '"0b101"', '"1e3"', '".5"', '"5."', '"Infinity"', '"-Infinity"', '"+3"', '"1_000"', '"١٢"', '"\\u00a012\\u3000"', '[]', '[5]', '[1,[2,null],"a"]', '[null]', '{}', '{"a":1}', '"0x"', '"-0x10"', '"  "'];
const bitsOrNull = (x) => bits(x);
const jsvalue = vals.map((t) => {
  const v = JSON.parse(t);
  return [t, String(v), String(v ?? ''), !!v, bitsOrNull(Number(v))];
});
const raws = ['  재혁\u0001  최고 ', 'a b  c﻿', '\t\n\r ', '😀😀😀😀😀😀😀😀😀😀', 'ㄱ'.repeat(255) + '😀', 'x'.repeat(300), 'ab\u007fcd\u0000', '\u0085x᠎', '  a  b  ', 'abcdefghijklmnopqrstu'];
const g = new Game(() => {});
g.addPlayer(1);
const clean = [];
for (const raw of raws) {
  g.setNick(1, raw);
  clean.push([raw, C.NAME_MAX_LEN, g.players.get(1).nick]);
  const r = new Rooms({ rng: mulberry32(1) });
  const c = r.connect({ readyState: 1, OPEN: 1, send() {} });
  r.message(c, { type: 'create', name: raw, nick: 'n' });
  clean.push([raw, C.ROOM_NAME_MAX_LEN, c.room.name === 'n의 방' && raw.trim() === '' ? '' : c.room.name]);
}
write('jsvalue.json', { values: jsvalue, clean, botLevels: Object.keys(C.BOT_LEVELS) });

// 방 각본 (S6, room-scenarios.mjs): 재접속·방 안 설정·상한·예외 격리·빈도 제한
const scen = ROOM_SCENARIOS.map((sc) => ({ ...sc, ...runJs(sc) }));
write('protocol-rooms.json', scen);

// 시작 지형
const maps = {};
for (const id of MAP_IDS) for (let n = 10; n <= 19; n++) maps[`${id}:${n}`] = mapColumns(id, n, n);
write('maps.json', maps);

// 물리만 (판 흐름·블록 없이): 틱마다 game.js tick 의 물리 부분과 같은 순서
const phys = [];
let pk = 0;
for (const id of MAP_IDS) {
  for (const n of [2, 4, 8]) {
    const rr = mulberry32(500 + pk++);
    const g = new Game(() => {}, { countdownMs: 1 });
    g.rng = rr;
    for (let i = 1; i <= n; i++) g.addPlayer(i);
    g.setMap(id);
    g.startRound();
    g.phase = 'playing';
    const frames = [];
    for (let k = 0; k < 300; k++) {
      for (const p of g.players.values()) {
        if (k % 10 === 0) g.handleInput(p.id, { fwd: Math.floor(rr() * 3) - 1, strafe: Math.floor(rr() * 3) - 1, jump: rr() < 0.3, yaw: (rr() - 0.5) * 8, pitch: 0 });
        if (rr() < 0.04) g.handleAction(p.id, { name: 'jump' });
        if (rr() < 0.02) {
          p.kbx = (rr() - 0.5) * 30;
          p.kby = (rr() - 0.5) * 30;
          p.vz = rr() * 6;
          p.stunUntil = g.time + 400;
          p.wallBounced = false;
          p.grounded = false;
        }
      }
      g.time += TICK;
      let remaining = TICK / 1000;
      while (remaining > 0) {
        const h = Math.min(remaining, C.MAX_STEP_DT);
        for (const p of g.players.values()) if (g.onField(p)) g.integratePlayer(p, h);
        remaining -= h;
      }
      for (const p of g.players.values()) if (p.grounded && p.alive && g.onField(p)) p.lastGround = g.groundKind(p);
      if (k % 10 === 9) frames.push([...g.players.values()].map((p) => [p.x, p.y, p.z, p.vz, p.kbx, p.kby, p.grounded, p.lastGround ?? null, p.airJumps])); // 숫자는 JSON 글자 그대로 (되읽으면 비트까지 같음)
    }
    phys.push({ map: id, n, frames, events: g.drainEvents().length });
  }
}
write('physics.json', phys);
// 판 시작 (trace.mjs 첫 줄과 같은 만들기)
const t0 = [];
HASH_SCENARIOS.forEach((sc, i) => {
  if (sc.mode === 'practice') return;
  const rnd = mulberry32(sc.seed);
  const logs = [];
  const g = new Game((l) => logs.push(l), { characters: sc.characters, skyStairs: sc.sky, countdownMs: 1500 });
  g.rng = rnd;
  if (sc.away) g.addPlayer(1);
  for (let k = sc.away ? 1 : 0; k < sc.n; k++) {
    const b = g.addBot();
    if (sc.characters) g.setChar(b.id, C.CHARACTERS[Math.floor(rnd() * C.CHARACTERS.length)]);
  }
  if (sc.team) g.setTeamMode(true);
  if (sc.mode !== 'survival') g.setMode(sc.mode);
  g.setMap(sc.map);
  g.startRound();
  const line = JSON.stringify({ t: 0, logs, snap: JSON.stringify(g.snapshot(true)) });
  t0.push([i, crypto.createHash('sha256').update(line).digest('hex')]);
});
write('trace-t0.json', t0);
// 각본 입력 판 (trace.mjs s0 … 와 같은 줄)
const scripted = SCRIPTED.map((sc) => {
  const h = crypto.createHash('sha256');
  let logs = [];
  const { g, rr } = setupScripted(Game, sc, (l) => logs.push(l));
  h.update(JSON.stringify({ t: 0, logs, snap: JSON.stringify(g.snapshot(true)) }) + '\n');
  logs = [];
  let ticks = 0;
  for (let t = 0; t < 120000 && g.phase !== 'over'; t += TICK) {
    driveScripted(g, rr, ticks);
    g.tick(TICK);
    ticks++;
    const snap = g.snapshot(ticks % 300 === 0);
    snap.events = g.drainEvents();
    h.update(JSON.stringify({ t: ticks, logs, snap: JSON.stringify(snap) }) + '\n');
    logs = [];
  }
  return [sc.name, ticks, h.digest('hex')];
});
write('scripted.json', scripted);

// 전투만 도는 각본 판 (S3, trace-scripted.mjs --combat): 캐릭터마다 틱 줄의 sha256 (C# CombatTraceTests 가 같은 각본을 돌림)
const combat = COMBAT_SCRIPTS.map((sc) => {
  const hashes = [];
  runScript(sc, (line) => hashes.push(crypto.createHash('sha256').update(JSON.stringify(line)).digest('hex').slice(0, 16)), { combat: true });
  return { ...sc, hashes };
});
write('combat-trace.json', combat);
// 판 34개 해시 (node tools/game-hash.js --verbose 와 같음)
const gameHash = HASH_SCENARIOS.map((sc) => {
  const r = runScenario(sc);
  return [sc.name, r.hash, r.ticks];
});
write('game-hash.json', gameHash);
// 튜토리얼 판
const tutorial = C.CHARACTERS.map((ch) => {
  const h = crypto.createHash('sha256');
  const r = runTutorial(ch, (line) => h.update(JSON.stringify(line) + '\n'));
  return [ch, r.ticks, r.done, h.digest('hex')];
});
write('tutorial-trace.json', tutorial);
// 같은 각본을 보통 틱 + 블록 낙하로 (S2·S3 합친 뒤: 갈고리 블록 잡기·층 지우기·압사까지, C# CombatTraceTests 의 blocks 판)
const blocksTrace = COMBAT_SCRIPTS.map((sc) => {
  const hashes = [];
  runScript(sc, (line) => hashes.push(crypto.createHash('sha256').update(JSON.stringify(line)).digest('hex').slice(0, 16)), { blocks: true });
  return { name: sc.name, hashes };
});
write('blocks-trace.json', blocksTrace);
// 봇 판 시뮬레이션 (워커 없이 한 줄로: 결과는 워커 수와 상관없음)
const simO = simArgs(['--rounds', '28', '--players', '2,3', '--workers', '1']);
const simLog = crypto.createHash('sha256');
const simResults = planJobs(simO).map((job) => runJob(job, simO, (m) => simLog.update(`${m}\n`)));
const simSum = summarizeSim(simResults);
write('sim.json', { summary: JSON.stringify(simSum), text: formatSim(simSum), logSha: simLog.digest('hex'), jobs: simResults.length });
console.log(`maps ${Object.keys(maps).length}, physics ${phys.length}판, trace-t0 ${t0.length}판, 각본 ${scripted.map((x) => x[1]).join('·')}틱, 전투 각본 ${combat.length}개, 블록 각본 ${blocksTrace.length}개`);
console.log(`jsmath ${math.length}, jsnumber ${nums.length}, 프로토콜 메시지 ${sent.length}개·로그 ${logs.length}줄, 방 각본 ${scen.length}개`);

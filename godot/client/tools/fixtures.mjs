// JS 화면 계산에서 고도 테스트의 정답 자료를 뽑음 → tests/fixtures/*.json. 실행 (레포 뿌리): node godot/client/tools/fixtures.mjs
// interp.json: 들쭉날쭉 도착하는 스냅샷 + 순간이동 + 새 방 → 프레임마다 SnapClock 시각·보간 위치 (client/interp.js)
// net.json: 핑·스냅샷·프레임 순서 → NetMeter view (shared/net.js)
// keys.json: 키 이름 글자·이모트 바퀴 칸·묶음 글자 (client/keys.js)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SnapClock, pushTrack, sampleTrack } from '../../../client/interp.js';
import { NetMeter } from '../../../shared/net.js';
import { mulberry32 } from '../../../tools/sim.js';
import { CONFIG as C } from '../../../shared/config.js';

const out = path.join(path.dirname(fileURLToPath(import.meta.url)), '../tests/fixtures');
fs.mkdirSync(out, { recursive: true });
const r = mulberry32(31);

// 보간: 서버 30Hz, 도착은 0~60ms 흔들림, 1500ms 에 순간이동, 4000ms 에 새 방 (서버 시각 처음부터)
const events = [];
let server = 0;
for (let i = 0; i < 180; i++) {
  server = i === 120 ? 10 : server + 1000 / 30; // 새 방
  const arrive = 100 + i * (1000 / 30) + r() * 60;
  const x = i < 45 ? i * 0.15 : i < 120 ? 20 + i * 0.1 : 3 + i * 0.05; // 45번째에 순간이동
  events.push({ type: 'snap', at: arrive, server, x, y: Math.sin(i / 7) * 2, z: i % 20 < 5 ? 1 : 0 });
}
for (let t = 100; t < 6200; t += 16.6 + (r() < 0.1 ? 40 : 0)) events.push({ type: 'frame', at: t });
events.sort((a, b) => a.at - b.at || (a.type === 'snap' ? -1 : 1));
const clock = new SnapClock();
const track = [];
let lastFrame = null;
const frames = [];
for (const e of events) {
  if (e.type === 'snap') {
    clock.onSnapshot(e.server, e.at);
    pushTrack(track, e.server, e.x, e.y, e.z);
  } else {
    const dt = lastFrame === null ? 16.6 : e.at - lastFrame;
    lastFrame = e.at;
    const t = clock.advance(e.at, dt);
    const s = t === null ? null : sampleTrack(track, t - C.INTERP_DELAY_MS, C.INTERP_EXTRAP_MS);
    frames.push([e.at, dt, t, s ? [s.x, s.y, s.z] : null, track.length]);
  }
}
fs.writeFileSync(path.join(out, 'interp.json'), JSON.stringify({ events, frames }));

// 핑 계산
const m = new NetMeter();
const seq = [];
let now = 0;
for (let i = 0; i < 400; i++) {
  now += 16 + (i % 97 === 0 ? 300 : 0);
  m.onFrame(now);
  if (i % 3 === 0) { m.onState(now); seq.push(['state', now]); }
  if (i % 60 === 0) {
    const rtt = i > 200 && i < 300 ? 200 + r() * 100 : 5 + r() * 20;
    const msg = { t: now - rtt, workMs: i === 240 ? 30 : 1, behindMs: 0 };
    m.onPong(msg, now);
    seq.push(['pong', now, msg]);
  }
  seq.push(['frame', now, m.view(now)]);
}
fs.writeFileSync(path.join(out, 'net.json'), JSON.stringify(seq));

const { keyLabel, wheelSlot, groupLabel, DEFAULT_BINDS, conflicts } = await import('../../../client/keys.js');
const labels = ['KeyF', 'Digit1', 'Mouse2', 'Mouse7', 'Numpad5', 'ShiftLeft', 'ArrowUp', 'Backslash', 'F3', '', 'Quote'].map((c) => [c, keyLabel(c)]);
const wheel = [];
for (let i = 0; i < 60; i++) {
  const w = { x: (r() - 0.5) * 80, y: (r() - 0.5) * 80 };
  wheel.push([w.x, w.y, wheelSlot(w, C.EMOTE_NAMES.length, C.EMOTE_PICK_PX)]);
}
const groups = [[['fwd', 'left', 'back', 'right'], groupLabel(DEFAULT_BINDS, ['fwd', 'left', 'back', 'right'])], [['rotL', 'rotR'], groupLabel(DEFAULT_BINDS, ['rotL', 'rotR'])], [['pieceUp', 'pieceDown', 'pieceLeft', 'pieceRight'], groupLabel(DEFAULT_BINDS, ['pieceUp', 'pieceDown', 'pieceLeft', 'pieceRight'])]];
const clash = { ...DEFAULT_BINDS, skill: 'KeyR' };
fs.writeFileSync(path.join(out, 'keys.json'), JSON.stringify({ labels, wheel, groups, defaults: DEFAULT_BINDS, conflicts: conflicts(clash) }));
console.log(`interp 프레임 ${frames.length}, net ${seq.length}, keys 바퀴 ${wheel.length}`);

// ui.json (G4): 화면 계산 — shared/hud-layout.js · kills-hud.js · wipe.js · char-select.js · leave.js
{
  const { cardLayout, lobbyDock, labelSizes } = await import('../../../shared/hud-layout.js');
  const { KillTally, streakText, progress, topBar, scoreRows, respawnSecs, hpFrac } = await import('../../../shared/kills-hud.js');
  const { screenOf, wipeKind, wipePlan } = await import('../../../shared/wipe.js');
  const { stageYaw, tauntAt, randomReel } = await import('../../../shared/char-select.js');
  const { leaveNeedsConfirm } = await import('../../../shared/leave.js');
  const u = {};
  u.cards = [];
  for (const n of [1, 2, 3, 4, 5, 6, 7, 8]) for (const w of [640, 800, 960, 1100, 1280, 1920]) u.cards.push([n, w, cardLayout(n, w)]);
  u.dock = [600, 800, 960, 1100, 1280, 1600, 1920, 2560].map((w) => [w, lobbyDock(w)]);
  u.labels = [];
  for (let k = 0; k < 20; k++) {
    const d = Array.from({ length: 1 + Math.floor(r() * 8) }, () => Math.round(r() * 20 * 10) / 10);
    u.labels.push([d, labelSizes(d)]);
  }
  // 킬 세기: 무작위 죽음 묶음 (id 1~5, by 없음·자기 자신 섞음, 가끔 서버 streak)
  const t = new KillTally();
  u.tally = [];
  for (let k = 0; k < 80; k++) {
    const who = 1 + Math.floor(r() * 5);
    const x = r();
    const by = x < 0.15 ? null : x < 0.2 ? who : 1 + Math.floor(r() * 5);
    const e = { who, by };
    if (r() < 0.1) e.streak = 1 + Math.floor(r() * 6);
    u.tally.push([e, t.add(e)]);
  }
  const players = [1, 2, 3, 4, 5, 6].map((id, i) => ({ id, slot: i, score: Math.floor(r() * 9) - 2, team: i % 2 ? 'blue' : 'red', spectator: id === 6 }));
  players.push({ id: 7, slot: 6, score: 9, dummy: true });
  players[2].kills = 4; // 서버 필드가 있으면 그것
  u.stats = players.map((p) => [p, t.stats(p)]);
  u.top = [1, 2, 3, 4, 5, 9].map((me) => [me, topBar(players, me)]);
  u.rows = [false, true].map((team) => [team, scoreRows(players, t, team)]);
  u.streak = [0, 1, 2, 3, 4, 5, 6, 11].map((n) => [n, streakText(n)]);
  u.progress = [[0, 7], [3, 7], [-2, 7], [9, 7], [5, 0]].map(([s, g]) => [s, g, progress(s, g)]);
  u.respawn = [5000, 4001, 4000, 1, 0, -5, null].map((ms) => [ms, respawnSecs(ms)]);
  u.hp = [[{ hp: 60 }, 120], [{ hp: -5 }, 120], [{ hp: 50, hpMax: 200 }, 120], [{ damage: 30 }, 120], [{ hp: 60 }, null]].map(([p, m]) => [p, m, hpFrac(p, m)]);
  const screens = ['menu', 'lobby', 'game', 'results', null];
  u.screens = [];
  for (const inRoom of [false, true]) for (const phase of ['lobby', 'countdown', 'playing', 'over']) for (const hero of [false, true]) for (const closeup of [false, true]) u.screens.push([inRoom, phase, hero, closeup, screenOf({ inRoom, phase, hero, closeup })]);
  u.kinds = [];
  for (const a of screens) for (const b of screens) u.kinds.push([a, b, wipeKind(a, b)]);
  u.plans = ['short', 'big', 'none', null].flatMap((k) => [false, true].map((red) => [k, red, wipePlan(k, red)]));
  u.yaw = [0, 0.5, 1, 1.2, 2, 5, 10].map((s) => [s, stageYaw(s)]);
  u.taunt = [-1, 0, 300, C.EMOTE_MS, C.EMOTE_MS + 1].map((ms) => [ms, tauntAt(ms)]);
  // 랜덤 뽑기: 쓴 난수를 그대로 적어 고도가 같은 순서로 씀
  u.reels = [];
  for (let k = 0; k < 6; k++) {
    const used = [];
    const rnd = () => { const v = r(); used.push(v); return v; };
    const cur = k === 5 ? 'zzz' : C.CHARACTERS[k];
    u.reels.push([cur, used, randomReel(C.CHARACTERS, cur, rnd)]);
  }
  u.leave = [];
  for (const phase of ['lobby', 'countdown', 'playing', 'over']) for (const practice of [false, true]) for (const alive of [true, false]) u.leave.push([phase, practice, alive, leaveNeedsConfirm({ phase, practice, alive })]);
  fs.writeFileSync(path.join(out, 'ui.json'), JSON.stringify(u));
  console.log(`ui 카드 ${u.cards.length}, 킬 ${u.tally.length}, 전환 ${u.kinds.length}, 랜덤 ${u.reels.length}`);
}

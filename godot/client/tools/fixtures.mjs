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
import { register } from 'node:module';

register('../../../test/support/client-loader.mjs', import.meta.url); // client/ 의 '/shared/…' 주소를 파일로 (sound.js)

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
// 소리 계산 (audio/sound_math.gd): 거리·좌우 (sound.js bus·falloff), 타격 단계, 앰비언트·곡·위험 지속음 크기, 째깍 시각
const { Sound } = await import('../../../client/sound.js');
const { hitTier, hitStep } = await import('../../../client/hit-tier.js');
const { Music } = await import('../../../client/music.js');
const { lobbyTheme } = await import('../../../shared/title.js');
const { bigTicks } = await import('../../../shared/bblock-look.js');
const listens = [];
const fakeCtx = { createGain: () => ({ gain: {}, connect(x) { return x; } }), createStereoPanner: () => ({ pan: {}, connect(x) { return x; } }) };
for (let i = 0; i < 200; i++) {
  const s = new Sound();
  s.ctx = fakeCtx;
  let pan = 0;
  s.ctx.createStereoPanner = () => ({ pan: { set value(v) { pan = v; } }, connect(x) { return x; } });
  let gain = null;
  s.ctx.createGain = () => ({ gain: { set value(v) { gain = v; } }, connect(x) { return x; } });
  s.listener = i % 10 === 0 ? null : { x: r() * 19, y: r() * 19, z: r() * 6, yaw: (r() - 0.5) * 7 };
  const dist = i % 7 === 0 ? undefined : i % 5 === 0 ? 0 : r() * 20;
  const pos = i % 3 === 0 ? undefined : { x: r() * 19, y: r() * 19, z: r() * 5 };
  pan = 0;
  s.bus(dist, pos, {});
  listens.push([s.listener, dist ?? null, pos ?? null, gain, pan]);
}
const kinds = ['push', 'blast', 'projectile', 'glide', 'slash', 'execute', 'note', undefined];
const hits = [];
for (let i = 0; i < 80; i++) {
  const e = { crit: r() < 0.15, finish: r() < 0.15, star: r() < 0.1, kind: kinds[Math.floor(r() * kinds.length)], n: r() < 0.5 ? Math.floor(r() * 5) : undefined, streak: r() < 0.5 ? Math.floor(r() * 6) : undefined };
  hits.push([e, hitTier(e), hitStep(e)]);
}
const states = [
  null,
  { phase: 'lobby', practice: null, map: { choice: 'random', id: 'flat' } },
  { phase: 'lobby', practice: null, map: { choice: 'pyramid', id: 'flat' } },
  { phase: 'lobby', practice: { x: 1 }, map: { choice: 'pyramid', id: 'pyramid' } },
  { phase: 'playing', practice: null, map: { choice: 'random', id: 'bowl' }, lava: { active: false, z: -1 } },
  { phase: 'playing', practice: null, map: { choice: 'random', id: 'spiral' }, lava: { active: true, z: 2 } },
  { phase: 'countdown', practice: null, map: { choice: 'random', id: 'nope' }, lava: { active: false, z: -1 } },
  { phase: 'over', practice: null, map: { choice: 'stairs', id: 'stairs' }, lava: { active: true, z: 3 } },
];
const themes = states.map((st) => {
  const amb = [];
  for (const menu of [null, 'crystal', 'nope']) amb.push([menu, Music.ambientTheme(st, menu), lobbyTheme(st, menu)]);
  const m = new Music({ ready: () => false });
  const mood = st ? (st.phase === 'playing' || st.phase === 'countdown' ? (st.lava && st.lava.active ? 'lava' : 'battle') : 'calm') : 'calm';
  m.setMood(mood);
  m.update(st, null);
  const key = m.songKey() + (mood === 'lava' && m.songKey() !== 'lobby' ? '.tense' : '');
  const theme = st && st.map && C.WORLD_MAP_THEME?.[st.map.id];
  const style = (theme && C.WORLD_THEMES?.[theme]?.hazard?.style) || C.SFX_HAZARD.fallback;
  return [st, amb, mood, key, style];
});
const H = C.SFX_HAZARD;
const levels = [];
for (const style of [...Object.keys(H.vol), 'nope']) for (const dist of [0, 2.5, 8, 30, Infinity]) {
  const near = Math.max(H.min, 1 - dist / H.range);
  levels.push([style, dist === Infinity ? null : dist, (H.vol[style] ?? 0.3) * (Number.isFinite(dist) ? near : 0)]);
}
fs.writeFileSync(path.join(out, 'audio.json'), JSON.stringify({ listens, hits, themes, levels, ticks: [[4000, bigTicks(4000)], [2500, bigTicks(2500)]] }));
console.log(`interp 프레임 ${frames.length}, net ${seq.length}, keys 바퀴 ${wheel.length}`);

// ---------- G1 판 그리기 (world/) ----------
// camera.json: 관전 궤도 (shared/camera.js) — 격자에 막히는 경우 포함
// sky.json: 하늘 시점 (shared/sky-view.js) · cells.json: 칸 색 (render.js cellColor 를 그대로 옮긴 식) · hazard.json: 위험 계산 (client/hazard-field.js)
{
  const r = mulberry32(131); // 묶음마다 따로 (앞 묶음이 난수를 더 써도 이 정답은 그대로)
  const { orbitEye, followDist, overviewScale } = await import('../../../shared/camera.js');
  const { skyPose, turnYaw, easeYaw, landingPreview } = await import('../../../shared/sky-view.js');
  const HF = await import('../../../client/hazard-field.js');
  const W = 12;
  const D = 10;
  const H = 8;
  const grid = new Array(W * D * H).fill(0);
  for (let y = 0; y < D; y++) for (let x = 0; x < W; x++) {
    const h = (x * 7 + y * 3) % 5 === 0 ? 4 : x < 3 ? 2 : (x + y) % 4 === 0 ? 1 : 0;
    for (let z = 0; z < h; z++) grid[(z * D + y) * W + x] = 1 + ((x + y + z) % 3);
  }
  const solid = (x, y, z) => {
    const gx = Math.floor(x), gy = Math.floor(y), gz = Math.floor(z);
    if (gx < 0 || gy < 0 || gx >= W || gy >= D) return false;
    if (gz < 0) return true;
    return gz < H && !!grid[(gz * D + gy) * W + gx];
  };
  const orbit = [];
  for (let i = 0; i < 80; i++) {
    const c = { x: r() * W, y: r() * D, z: r() * 3 };
    const yaw = r() * Math.PI * 2;
    const pitch = (r() - 0.6) * 2.4;
    const dist = 1 + r() * 10;
    const blocked = i % 2 === 0;
    const opt = { margin: r() < 0.5 ? 0.3 : 0.5 };
    orbit.push([c, yaw, pitch, dist, blocked, opt.margin, orbitEye(c, yaw, pitch, dist, blocked ? solid : null, opt)]);
  }
  const follow = [];
  for (let i = 0; i < 30; i++) {
    const cur = i % 7 === 0 ? null : r() * 5;
    const want = r() * 5;
    const dt = r() * 0.1;
    follow.push([cur, want, dt, 4, followDist(cur, want, dt, 4)]);
  }
  const over = [10, 14, 19, 8].map((s) => [s, C.GRID_W, overviewScale(s, C.GRID_W)]);
  fs.writeFileSync(path.join(out, 'camera.json'), JSON.stringify({ W, D, H, grid, orbit, follow, over }));

  const poses = [];
  for (const n of [10, 13, 19]) for (const aspect of [16 / 9, 4 / 3, 21 / 9]) for (const yaw of [0, Math.PI / 2, Math.PI, 4.1]) poses.push([n, n + (n % 2), yaw, aspect, skyPose(n, n + (n % 2), yaw, aspect)]);
  const turns = [];
  for (let i = 0; i < 20; i++) {
    const y = r() * 8 - 1;
    const d = i % 2 ? 1 : -1;
    turns.push([y, d, turnYaw(y, d)]);
  }
  const eases = [];
  for (let i = 0; i < 20; i++) {
    const a = r() * 7;
    const b = r() * 7;
    const k = r();
    eases.push([a, b, k, easeYaw(a, b, k)]);
  }
  const lands = [
    { cells: [[3, 3, 9], [4, 3, 9], [5, 3, 9], [4, 4, 10]], landZ: 2, fits: true },
    { cells: [[1, 1, 3], [2, 1, 3], [1, 2, 3], [2, 2, 3]], landZ: 3, fits: false },
    { cells: [[6, 2, 7], [6, 3, 6], [6, 4, 5], [6, 5, 4]], landZ: 0, fits: true },
  ].map((pc) => [pc, landingPreview(pc)]);
  fs.writeFileSync(path.join(out, 'sky.json'), JSON.stringify({ poses, turns, eases, lands }));

  // cellColor: render.js 의 식 (three.js 색 관리 = 선형 공간 곱) 을 three 로 직접 계산
  const THREE = await import('three');
  const { CELL, SHAPE_NAMES } = await import('../../../shared/pieces.js');
  const shade = (hex) => new THREE.Color(hex).multiplyScalar(C.BLOCK_LANDED_SHADE).getHex();
  const cellColor = (v, colors) => {
    if (v === CELL.BUILD) return C.BUILD_COLOR;
    if (v >= CELL.GHOST_BASE) return shade(C.PLAYER_PALETTE[(v - CELL.GHOST_BASE) % C.PLAYER_PALETTE.length]);
    if (v === CELL.THROWN) return C.THROWN_COLOR;
    const s = SHAPE_NAMES[v - CELL.SHAPE_BASE];
    return s ? shade(colors[s]) : C.TERRAIN_COLOR;
  };
  const meadow = { ...C.SHAPE_COLORS, ...(C.WORLD_THEMES.meadow.piece?.colors || {}) };
  const cells = [];
  for (let v = 1; v < 40; v++) cells.push([v, cellColor(v, C.SHAPE_COLORS), cellColor(v, meadow)]);
  fs.writeFileSync(path.join(out, 'cells.json'), JSON.stringify({ cells }));

  const cols = [];
  for (const zs of [-0.5, 0, 0.4, 1.0, 1.7, 3.2, 5]) for (const [x, y] of [[0, 0], [1, 2], [5, 5], [-1, 3], [W, 0], [10, 9]]) cols.push([x, y, zs, HF.columnAt(grid, W, D, H, x, y, zs)]);
  const fields = [];
  for (const zs of [-0.3, 0.6, 1.5, 3.4]) {
    const f = HF.hazardField(grid, W, D, H, zs);
    const pick = [];
    for (let k = 0; k < f.dist.length; k += 37) pick.push([k, f.dist[k], f.ground[k]]);
    let sum = 0;
    for (const v of f.dist) sum += v;
    fields.push([zs, { nx: f.nx, ny: f.ny, x0: f.x0, y0: f.y0, w: f.w, d: f.d, sum, pick, contacts: f.contacts }]);
  }
  const steps = [0, 0.49, 0.5, 1.2, 3.75, 7.5].map((z) => [z, HF.riseStep(z)]);
  const vig = [[-1, 0], [0, 0], [1.2, 0.5], [2.4, 0], [3, 0], [3, 1], [0.5, 2]].map(([g, p]) => [g, p, HF.vignetteStrength(g, p)]);
  const drops = [0, 10, 20, 35, 80, 125].map((d) => [d, HF.seaDrop(d)]);
  const objs = [];
  for (let i = 0; i < 12; i++) objs.push({ x: (r() - 0.5) * 200, y: (r() - 0.5) * 200, zBot: -4 + r() * 4, zTop: 2 + r() * 10, rBot: 3 + r() * 6, rTop: r() * 2 });
  const rings = [-2, 1, 4, 9].map((zs) => [zs, HF.farRings(objs, zs, C.HAZARD_FAR_RINGS, 6, 5)]);
  fs.writeFileSync(path.join(out, 'hazard.json'), JSON.stringify({ W, D, H, grid, cols, fields, steps, vig, drops, objs, rings }));
  console.log(`world: 궤도 ${orbit.length}, 하늘 ${poses.length}, 칸 색 ${cells.length}, 위험 ${fields.length}`);
}
{
  const r = mulberry32(137);
  // labels.json: 머리 위 이름표 크기 (shared/hud-layout.js labelSizes) — 같은 거리 포함
  const { labelSizes } = await import('../../../shared/hud-layout.js');
  const cases = [];
  for (let n = 1; n <= 8; n++) for (let k = 0; k < 3; k++) {
    const d = [];
    for (let i = 0; i < n; i++) d.push(k === 2 && i % 2 ? d[i - 1] : Math.round(r() * 300) / 10);
    cases.push([d, labelSizes(d).map((o) => [o.scale, o.opacity])]);
  }
  fs.writeFileSync(path.join(out, 'labels.json'), JSON.stringify(cases));
}

// ui.json (G4): 화면 계산 — shared/hud-layout.js · kills-hud.js · wipe.js · char-select.js · leave.js
{
  const { cardLayout, lobbyDock, labelSizes } = await import('../../../shared/hud-layout.js');
  const { KillTally, streakText, progress, topBar, scoreRows, respawnSecs, hpFrac, hpView, hpColor } = await import('../../../shared/kills-hud.js');
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
  const hst = { hpMode: true, hpMax: 120 };
  u.hpView = [[{ hp: 86.2 }, hst], [{ hp: 300, hpMax: 400 }, hst], [{ hp: -4 }, hst], [{ hp: 20 }, hst], [{ hp: 60 }, { hpMax: 120 }], [{ damage: 30 }, hst], [null, hst], [{ hp: 60 }, null]].map(([p, s]) => [p, s, hpView(p, s)]);
  u.hpColor = [1, 0.75, 0.5, 0.31, 0.2, 0, -1, 1.5].map((f) => [f, hpColor(f)]);
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

// figure_pose.json (G2): 걸음걸이·공중·기울임·평소 버릇 목표 자세 (client/figure-pose.js). 빈 자세 T 에서 시작해 함수 하나 부른 뒤 T 전체
{
  const P = await import('../../../client/figure-pose.js');
  const rest = () => ({ waistPitch: 0, waistRoll: 0, waistSide: 0, neckPitch: 0, hipsZ: 0, shFwd: [0, 0], shOut: [0.2, 0.2], elbow: [0.15, 0.15], thFwd: [0, 0], thOut: [0, 0], knee: [0, 0] });
  const D = { hunch: 0.1, spread: 0.22 };
  const cases = [];
  for (const ch of C.FIGURE_CHARS) {
    for (const [hs, walk] of [[C.MOVE_SPEED, 0], [C.MOVE_SPEED, 1], [C.MOVE_SPEED * 0.5, 2.5], [0, 1], [C.MOVE_SPEED * 2, 4.2]]) {
      const T = rest();
      P.gaitPose(T, D, { hs, walk }, P.gaitOf(ch));
      cases.push({ fn: 'gait', char: ch, hs, walk, T });
    }
  }
  for (const vz of [6, 2, 0, -1.5, -6, NaN]) {
    for (const [t, attacking] of [[0.3, false], [1.7, false], [1.7, true]]) {
      const T = rest();
      P.airPose(T, D, { vz }, t, attacking);
      cases.push({ fn: 'air', vz: Number.isFinite(vz) ? vz : null, t, attacking, T });
    }
  }
  for (const [accF, accS] of [[10, -5], [1e6, -1e6], [-30, 40], [NaN, null]]) {
    const T = rest();
    P.accLean(T, { accF, accS });
    cases.push({ fn: 'acc', accF: Number.isFinite(accF) ? accF : null, accS: Number.isFinite(accS) ? accS : null, T });
  }
  for (const w of [1, 0.5]) {
    const T = rest();
    P.overlayT(T, P.SUPERMAN, w);
    cases.push({ fn: 'superman', w, T });
  }
  for (const h of Object.values(C.FIGURE_IDLE)) {
    for (const u of [0, 0.2, 0.5, 0.7, 1]) {
      for (const form of [null, 'metal']) {
        const T = rest();
        P.idlePose(T, h.kind, u, h.len * u, form);
        cases.push({ fn: 'idle', kind: h.kind, u, s: h.len * u, form, T });
      }
    }
  }
  fs.writeFileSync(path.join(out, 'figure_pose.json'), JSON.stringify({ D, rest: rest(), cases }));
  console.log(`figure_pose ${cases.length}`);
}

// figure_motion.json (G2): 몸 자세 계산 (client/figure.js 안 함수 — 내보내지 않아 소스에서 잘라 씀): restPose·springPose·hitPose·stepSway·overlay·poseAt (도발/승리 loop 포함)
{
  const { register } = await import('node:module');
  register('../../../test/support/client-loader.mjs', import.meta.url);
  const { POSES, MOVES } = await import('../../../client/figure.js');
  const src = fs.readFileSync(new URL('../../../client/figure.js', import.meta.url), 'utf8');
  const cut = (head) => {
    const i = src.indexOf(head);
    if (i < 0) throw new Error(`figure.js 에 ${head} 없음`);
    let depth = 0;
    for (let j = src.indexOf('{', i); j < src.length; j++) {
      if (src[j] === '{') depth++;
      else if (src[j] === '}' && --depth === 0) return src.slice(i, j + 1);
    }
    throw new Error(head);
  };
  const names = ['function restPose', 'function zeroPose', 'function springPose', 'function hitPose', 'function stepSway', 'function overlay', 'function poseAt', 'function mergeSides'];
  const body = [src.match(/^const SPRING_GROUP = .*$/m)[0], 'const ease = (u) => { const x = Math.max(0, Math.min(1, u)); return x * x * (3 - 2 * x); };', ...names.map(cut), 'return { restPose, zeroPose, springPose, hitPose, stepSway, overlay, poseAt };'].join('\n');
  const F = Function('C', body)(C);
  const r2 = mulberry32(77);
  const cases = [];
  const D = { hunch: 0.12, spread: 0.25, bend: 0.1 };
  cases.push({ fn: 'rest', d: D, P: F.restPose(D) });
  // 스프링: 무작위 목표로 여러 프레임 (dt 들쭉날쭉, fast)
  {
    const P = F.restPose(D);
    const V = F.zeroPose(P);
    const steps = [];
    for (let i = 0; i < 40; i++) {
      const T = F.restPose(D);
      for (const k of Object.keys(T)) T[k] = Array.isArray(T[k]) ? T[k].map(() => (r2() - 0.5) * 3) : (r2() - 0.5) * 2;
      const dt = [1 / 60, 1 / 30, 0.1, 0.003][i % 4];
      const fast = i % 5 === 0 ? C.FIGURE_SPRING_FLIP : 1;
      F.springPose(P, V, T, dt, fast);
      steps.push({ T, dt, fast, P: JSON.parse(JSON.stringify(P)), V: JSON.parse(JSON.stringify(V)) });
    }
    cases.push({ fn: 'spring', d: D, steps });
  }
  for (const [dx, dy, pow] of [[1, 0, 1], [-0.6, 0.8, 1.5], [0.2, -1, 2.4]]) {
    const T = F.restPose(D);
    F.hitPose(T, dx, dy, pow);
    cases.push({ fn: 'hit', d: D, dx, dy, pow, T });
  }
  {
    const sw = { x: 0.3, y: -0.2, vx: 4, vy: -2 };
    const seq = [];
    for (const dt of [0.016, 0.033, 0.1, 0.005, 0.05]) {
      F.stepSway(sw, dt);
      seq.push({ dt, sw: { ...sw } });
    }
    cases.push({ fn: 'sway', start: { x: 0.3, y: -0.2, vx: 4, vy: -2 }, seq });
  }
  // overlay: 공격 동작 몇 개 (W·S·BROKEN 비슷한 crouch 포함), 무게 여러 개, V 있음
  for (const name of ['punch', '주먹', '어깨 박치기', '앞차기', 'hookSlam']) {
    for (const part of ['W', 'S']) {
      const pose = MOVES[name][part];
      if (!pose) continue;
      for (const w of [0.3, 1, 1.4]) {
        const P = F.restPose(D);
        const T = F.restPose(D);
        T.knee = [0.2, 0.4];
        const V = F.zeroPose(P);
        for (const k of Object.keys(V)) V[k] = Array.isArray(V[k]) ? V[k].map(() => 2) : 2;
        F.overlay(P, T, pose, w, V);
        cases.push({ fn: 'overlay', d: D, move: name, part, w, T, P, V });
      }
    }
  }
  // 도발·승리: 캐릭터(폼)마다 시간 여러 개 (준비·튐·결정+loop·풀림)
  for (const who of Object.keys(POSES)) {
    for (const kind of ['taunt', 'victory']) {
      for (const t of [0.05, 0.25, 0.3, 0.5, 1.3, 2.7, C.EMOTE_MS / 1000 - 0.1]) {
        const end = kind === 'victory' ? Infinity : C.EMOTE_MS / 1000;
        const P = F.restPose(D);
        const T = F.restPose(D);
        const V = F.zeroPose(P);
        F.poseAt(P, T, V, POSES[who][kind], t, end);
        cases.push({ fn: 'poseAt', d: D, who, kind, t, end: Number.isFinite(end) ? end : null, P });
      }
    }
  }
  fs.writeFileSync(path.join(out, 'figure_motion.json'), JSON.stringify({ cases }));
  console.log(`figure_motion ${cases.length}`);
}
{
  // victory.json (G1): 판 끝 연출 순서 (shared/victory.js) + 승자 고르기 (client/main.js 판 끝의 star 식을 그대로)
  const { victoryPlan, victoryStage } = await import('../../../shared/victory.js');
  const plans = [];
  for (const star of [true, false]) for (const slow of [0, 900, Infinity, -5]) for (const reduced of [false, true]) {
    const p = victoryPlan({ star, slowLeftMs: slow, reduced });
    plans.push([star, Number.isFinite(slow) ? slow : null, reduced, p, [-1, 0, 500, 1200, 3000, 4000, 9000].map((t) => [t, victoryStage(p, t)])]);
  }
  const starOf = (state) => {
    const playerById = (id) => state.players.find((x) => x.id === id);
    const wt = state.round.winnerTeam;
    const ws = (state.round.winnerIds || []).map(playerById).filter(Boolean);
    const star = wt ? state.players.find((x) => x.team === wt && x.alive) || state.players.find((x) => x.team === wt) : ws.find((x) => x.alive) || ws[0];
    return star ? star.id : null;
  };
  const P = (id, alive, team) => ({ id, alive, team });
  const stars = [
    { players: [P(1, true), P(2, false)], round: { winnerIds: [1] } },
    { players: [P(1, false), P(2, true), P(3, true)], round: { winnerIds: [1, 3] } },
    { players: [P(1, false), P(2, false)], round: { winnerIds: [2, 1] } },
    { players: [P(1, true)], round: { winnerIds: [] } },
    { players: [P(1, true, 'red'), P(2, false, 'blue'), P(3, true, 'blue')], round: { winnerTeam: 'blue', winnerIds: [2, 3] } },
    { players: [P(1, true, 'red'), P(2, false, 'blue')], round: { winnerTeam: 'blue' } },
    { players: [P(1, true)], round: { winnerIds: [9] } },
  ].map((s) => [s, starOf(s)]);
  fs.writeFileSync(path.join(out, 'victory.json'), JSON.stringify({ plans, stars }));
}
{
  // ghost.json (G1): 유령 투하 조준 기둥 고르기 — render.js pickColumn 의 시선 걷기 (카메라 unproject 뒤) 를 그대로, 시선은 무작위
  const r = mulberry32(141);
  const W = 9, D = 8, H = 6;
  const grid = new Array(W * D * H).fill(0);
  for (let y = 0; y < D; y++) for (let x = 0; x < W; x++) for (let z = 0; z < (x * 3 + y * 5) % 4; z++) grid[(z * D + y) * W + x] = 1;
  const solidAt = (x, y, z) => {
    const gx = Math.floor(x), gy = Math.floor(y), gz = Math.floor(z);
    if (gx < 0 || gy < 0 || gx >= W || gy >= D) return false;
    if (gz < 0) return true;
    return gz < H && !!grid[(gz * D + gy) * W + gx];
  };
  const top = (x, y) => { for (let z = H - 1; z >= 0; z--) if (grid[(z * D + y) * W + x]) return z + 1; return 0; };
  const pick = (o, d) => {
    for (let t = 0.3; t < C.GHOST_AIM_RANGE; t += 0.05) {
      const x = o.x + d.x * t, y = o.y + d.y * t, z = o.z + d.z * t;
      if (z < -0.5) break;
      const gx = Math.floor(x), gy = Math.floor(y);
      if (gx < 0 || gy < 0 || gx >= W || gy >= D) continue;
      if (z <= 0 || solidAt(x, y, z)) return { x: gx, y: gy, z: top(gx, gy) };
    }
    return null;
  };
  const rays = [];
  for (let i = 0; i < 60; i++) {
    const o = { x: -4 + r() * (W + 8), y: -4 + r() * (D + 8), z: 2 + r() * 10 };
    const a = r() * Math.PI * 2, el = -0.1 - r() * 1.4;
    const d = { x: Math.cos(a) * Math.cos(el), y: Math.sin(a) * Math.cos(el), z: Math.sin(el) };
    rays.push([o, d, pick(o, d)]);
  }
  fs.writeFileSync(path.join(out, 'ghost.json'), JSON.stringify({ W, D, H, grid, rays }));
}

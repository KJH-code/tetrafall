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

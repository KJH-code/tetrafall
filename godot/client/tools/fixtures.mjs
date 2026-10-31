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

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
